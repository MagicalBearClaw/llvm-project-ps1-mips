//===-------- MipsELFStreamer.cpp - ELF Object Output ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "MipsELFStreamer.h"
#include "MipsMCTargetDesc.h"
#include "MipsOptionRecord.h"
#include "MipsTargetStreamer.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCDwarf.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCSymbolELF.h"

using namespace llvm;

MipsELFStreamer::MipsELFStreamer(MCContext &Context,
                                 std::unique_ptr<MCAsmBackend> MAB,
                                 std::unique_ptr<MCObjectWriter> OW,
                                 std::unique_ptr<MCCodeEmitter> Emitter)
    : MCELFStreamer(Context, std::move(MAB), std::move(OW),
                    std::move(Emitter)) {
  RegInfoRecord = new MipsRegInfoRecord(this, Context);
  MipsOptionRecords.push_back(
      std::unique_ptr<MipsRegInfoRecord>(RegInfoRecord));
}

MipsELFStreamer::~MipsELFStreamer() = default;

// What \p Inst leaves pending for the instructions after it on MIPS I.
static MipsELFStreamer::HazardSource getHazardSource(const MCInst &Inst) {
  using Src = MipsELFStreamer::HazardSource;
  switch (Inst.getOpcode()) {
  // Loads and coprocessor reads: the GPR is not ready for the next
  // instruction.
  case Mips::LB:
  case Mips::LBu:
  case Mips::LH:
  case Mips::LHu:
  case Mips::LW:
  case Mips::LWL:
  case Mips::LWR:
  case Mips::MFC0:
  case Mips::MFC2:
    return {Src::Load, Inst.getOperand(0).getReg()};
  // lwc2 loads a GTE register. Like gas, check no instruction against it.
  case Mips::LWC2:
    return {Src::Load, MCRegister()};
  case Mips::MFLO:
    return {Src::ReadHiLo, Mips::LO0};
  case Mips::MFHI:
    return {Src::ReadHiLo, Mips::HI0};
  case Mips::MTC0:
  case Mips::MTC2:
    return {Src::CopWrite, MCRegister()};
  default:
    return {};
  }
}

static bool writesHiLo(const MCInst &Inst, MCRegister HiOrLo) {
  switch (Inst.getOpcode()) {
  case Mips::MULT:
  case Mips::MULTu:
  case Mips::SDIV:
  case Mips::UDIV:
    return true;
  case Mips::MTHI:
    return HiOrLo == Mips::HI0;
  case Mips::MTLO:
    return HiOrLo == Mips::LO0;
  default:
    return false;
  }
}

// The coprocessor instructions gas holds back after a coprocessor write. Not
// lwc2, and not COP1, which has rules of its own.
static bool isCopInstruction(const MCInst &Inst) {
  switch (Inst.getOpcode()) {
  case Mips::MFC0:
  case Mips::MTC0:
  case Mips::MFC2:
  case Mips::MTC2:
  case Mips::SWC2:
    return true;
  default:
    return false;
  }
}

static bool readsGPR(const MCInst &Inst, const MCInstrInfo &MII,
                     MCRegister Reg) {
  // lwl and lwr merge into their destination, but the merge does not wait for
  // a load still pending to it, so like gas only their base register counts.
  if (Inst.getOpcode() == Mips::LWL || Inst.getOpcode() == Mips::LWR)
    return Inst.getOperand(1).getReg() == Reg;

  // Explicit uses follow the defs.
  const MCInstrDesc &Desc = MII.get(Inst.getOpcode());
  for (unsigned I = Desc.getNumDefs(), E = Inst.getNumOperands(); I != E; ++I) {
    const MCOperand &Op = Inst.getOperand(I);
    if (Op.isReg() && Op.getReg() == Reg)
      return true;
  }
  return llvm::is_contained(Desc.implicit_uses(), Reg);
}

// How many instructions must separate \p Src from \p Inst, or from anything
// that is not an instruction if \p Inst is null.
unsigned MipsELFStreamer::requiredDistance(const HazardSource &Src,
                                           const MCInst *Inst) const {
  switch (Src.Kind) {
  case HazardSource::None:
    return 0;
  case HazardSource::Load:
    if (!Inst)
      return 1;
    return Src.Reg && Src.Reg != Mips::ZERO &&
                   readsGPR(*Inst, *HazardMII, Src.Reg)
               ? 1
               : 0;
  case HazardSource::ReadHiLo:
    return !Inst || writesHiLo(*Inst, Src.Reg) ? 2 : 0;
  case HazardSource::CopWrite:
    // gas needs one instruction before a known coprocessor instruction, and
    // assumes two when it cannot see the next instruction.
    if (!Inst)
      return 2;
    return isCopInstruction(*Inst) ? 1 : 0;
  }
  llvm_unreachable("unknown hazard kind");
}

unsigned MipsELFStreamer::nopsBefore(const MCInst *Inst, bool Reorder,
                                     unsigned Age) const {
  unsigned Nops = 0;
  for (unsigned I = 0; I != History.size(); ++I) {
    const HistoryEntry &Entry = History[I];
    // A hazard between two noreorder instructions is the programmer's.
    if (!Reorder && !Entry.Reorder)
      continue;
    unsigned Distance = requiredDistance(Entry.Src, Inst);
    unsigned Between = I + Age;
    if (Distance > Between)
      Nops = std::max(Nops, Distance - Between);
  }
  return Nops;
}

bool MipsELFStreamer::reorderHazardPending(unsigned Age) const {
  return nopsBefore(nullptr, /*Reorder=*/false, Age) != 0;
}

void MipsELFStreamer::emitAndRecord(const MCInst &Inst,
                                    const MCSubtargetInfo &STI, bool Reorder) {
  MCELFStreamer::emitInstruction(Inst, STI);

  if (HazardMII) {
    HistorySTI = &STI;
    History[1] = History[0];
    History[0] = {getHazardSource(Inst), Reorder};
  }

  MCContext &Context = getContext();
  const MCRegisterInfo *MCRegInfo = Context.getRegisterInfo();

  for (unsigned OpIndex = 0; OpIndex < Inst.getNumOperands(); ++OpIndex) {
    const MCOperand &Op = Inst.getOperand(OpIndex);

    if (!Op.isReg())
      continue;

    MCRegister Reg = Op.getReg();
    RegInfoRecord->SetPhysRegUsed(Reg, MCRegInfo);
  }

  createPendingLabelRelocs();
}

void MipsELFStreamer::emitHazardNops(unsigned Count) {
  MCInst Nop;
  Nop.setOpcode(Mips::SLL);
  Nop.addOperand(MCOperand::createReg(Mips::ZERO));
  Nop.addOperand(MCOperand::createReg(Mips::ZERO));
  Nop.addOperand(MCOperand::createImm(0));
  for (unsigned I = 0; I != Count; ++I)
    emitAndRecord(Nop, *HistorySTI, /*Reorder=*/false);
}

void MipsELFStreamer::releaseHeld(bool UnknownNext) {
  unsigned Nops = 0;
  unsigned Age = 0;
  for (const HeldBack &H : Held) {
    if (H.Label)
      continue;
    Nops = std::max(Nops, nopsBefore(&H.Inst, /*Reorder=*/false, Age));
    ++Age;
  }
  if (UnknownNext)
    Nops = std::max(Nops, nopsBefore(nullptr, /*Reorder=*/false, Age));
  emitHazardNops(Nops);

  // Emit everything up to the last instruction. Labels after it stay held:
  // nops for what follows still go before them.
  SmallVector<HeldBack, 4> ToEmit;
  std::swap(ToEmit, Held);
  HeldInstructions = 0;
  size_t End = UnknownNext ? ToEmit.size() : 0;
  for (size_t I = 0; I != ToEmit.size(); ++I)
    if (!ToEmit[I].Label)
      End = std::max(End, I + 1);
  for (size_t I = 0; I != ToEmit.size(); ++I) {
    HeldBack &H = ToEmit[I];
    if (I >= End)
      Held.push_back(std::move(H));
    else if (H.Label) {
      MCELFStreamer::emitLabel(H.Label);
      Labels.push_back(H.Label);
    } else {
      emitAndRecord(H.Inst, *H.STI, /*Reorder=*/false);
    }
  }
}

void MipsELFStreamer::emitHeldLabels() {
  assert(!HeldInstructions && "only labels may be held here");
  SmallVector<HeldBack, 4> ToEmit;
  std::swap(ToEmit, Held);
  for (HeldBack &H : ToEmit) {
    MCELFStreamer::emitLabel(H.Label);
    Labels.push_back(H.Label);
  }
}

void MipsELFStreamer::setHazardPadding(bool Enable) {
  RecordHazards = Enable;
  if (Enable && !HazardMII)
    HazardMII.reset(createMipsMCInstrInfo());
}

void MipsELFStreamer::flushPendingHazards() {
  if (!HazardMII)
    return;
  releaseHeld(/*UnknownNext=*/true);
  History = {};
}

void MipsELFStreamer::emitInstruction(const MCInst &Inst,
                                      const MCSubtargetInfo &STI) {
  // Hazards are tracked on MIPS I only. Codegen output is recorded too, so a
  // hazard it leaves for inline asm that follows is padded, as gas does.
  if (!HazardMII && STI.hasFeature(Mips::FeatureMips1) &&
      !STI.hasFeature(Mips::FeatureMips2))
    HazardMII.reset(createMipsMCInstrInfo());
  if (!HazardMII) {
    emitAndRecord(Inst, STI, /*Reorder=*/false);
    return;
  }
  HistorySTI = &STI;

  if (!RecordHazards) {
    // A noreorder instruction. If a reorder hazard can reach it, hold it
    // until the hazard runs out, so the nops go before all of them.
    if (HeldInstructions || reorderHazardPending(0)) {
      Held.push_back({nullptr, SMLoc(), Inst, &STI});
      ++HeldInstructions;
      if (!reorderHazardPending(HeldInstructions))
        releaseHeld(/*UnknownNext=*/false);
      return;
    }
    emitHeldLabels();
    emitAndRecord(Inst, STI, /*Reorder=*/false);
    return;
  }

  // A reorder instruction: noreorder instructions held before it go first,
  // then the nops it needs, before any labels in front of it.
  if (HeldInstructions)
    releaseHeld(/*UnknownNext=*/false);
  emitHazardNops(nopsBefore(&Inst, /*Reorder=*/true));
  emitHeldLabels();
  emitAndRecord(Inst, STI, /*Reorder=*/true);
}

void MipsELFStreamer::emitCFIStartProcImpl(MCDwarfFrameInfo &Frame) {
  Frame.Begin = getContext().createTempSymbol();
  MCELFStreamer::emitLabel(Frame.Begin);
}

MCSymbol *MipsELFStreamer::emitCFILabel() {
  MCSymbol *Label = getContext().createTempSymbol("cfi", true);
  MCELFStreamer::emitLabel(Label);
  return Label;
}

void MipsELFStreamer::emitCFIEndProcImpl(MCDwarfFrameInfo &Frame) {
  Frame.End = getContext().createTempSymbol();
  MCELFStreamer::emitLabel(Frame.End);
}

void MipsELFStreamer::createPendingLabelRelocs() {
  MipsTargetELFStreamer *ELFTargetStreamer =
      static_cast<MipsTargetELFStreamer *>(getTargetStreamer());

  // FIXME: Also mark labels when in MIPS16 mode.
  if (ELFTargetStreamer->isMicroMipsEnabled()) {
    for (auto *L : Labels) {
      auto *Label = static_cast<MCSymbolELF *>(L);
      getAssembler().registerSymbol(*Label);
      Label->setOther(ELF::STO_MIPS_MICROMIPS);
    }
  }

  Labels.clear();
}

void MipsELFStreamer::emitLabel(MCSymbol *Symbol, SMLoc Loc) {
  if (HazardMII &&
      (HeldInstructions || nopsBefore(nullptr, /*Reorder=*/true) != 0)) {
    // A held-back label is not defined yet, so a second definition of it is
    // caught here.
    if (llvm::any_of(Held,
                     [&](const HeldBack &H) { return H.Label == Symbol; })) {
      getContext().reportError(Loc, "invalid symbol redefinition");
      return;
    }
    Held.push_back({Symbol, Loc, MCInst(), nullptr});
    return;
  }
  MCELFStreamer::emitLabel(Symbol);
  Labels.push_back(Symbol);
}

void MipsELFStreamer::switchSection(MCSection *Section, uint32_t Subsection) {
  flushPendingHazards();
  MCELFStreamer::switchSection(Section, Subsection);
  Labels.clear();
}

void MipsELFStreamer::emitValueImpl(const MCExpr *Value, unsigned Size,
                                    SMLoc Loc) {
  flushPendingHazards();
  MCELFStreamer::emitValueImpl(Value, Size, Loc);
  Labels.clear();
}

void MipsELFStreamer::emitIntValue(uint64_t Value, unsigned Size) {
  flushPendingHazards();
  MCELFStreamer::emitIntValue(Value, Size);
  Labels.clear();
}

void MipsELFStreamer::emitBytes(StringRef Data) {
  flushPendingHazards();
  MCELFStreamer::emitBytes(Data);
}

void MipsELFStreamer::emitULEB128Value(const MCExpr *Value) {
  flushPendingHazards();
  MCELFStreamer::emitULEB128Value(Value);
}

void MipsELFStreamer::emitSLEB128Value(const MCExpr *Value) {
  flushPendingHazards();
  MCELFStreamer::emitSLEB128Value(Value);
}

void MipsELFStreamer::emitValueToAlignment(Align Alignment, int64_t Fill,
                                           uint8_t FillLen,
                                           unsigned MaxBytesToEmit) {
  flushPendingHazards();
  MCELFStreamer::emitValueToAlignment(Alignment, Fill, FillLen, MaxBytesToEmit);
}

void MipsELFStreamer::emitCodeAlignment(Align ByteAlignment,
                                        const MCSubtargetInfo *STI,
                                        unsigned MaxBytesToEmit) {
  flushPendingHazards();
  MCELFStreamer::emitCodeAlignment(ByteAlignment, STI, MaxBytesToEmit);
}

void MipsELFStreamer::emitValueToOffset(const MCExpr *Offset,
                                        unsigned char Value, SMLoc Loc) {
  flushPendingHazards();
  MCELFStreamer::emitValueToOffset(Offset, Value, Loc);
}

void MipsELFStreamer::emitFill(const MCExpr &NumBytes, uint64_t FillValue,
                               SMLoc Loc) {
  flushPendingHazards();
  MCELFStreamer::emitFill(NumBytes, FillValue, Loc);
}

void MipsELFStreamer::emitFill(const MCExpr &NumValues, int64_t Size,
                               int64_t Expr, SMLoc Loc) {
  flushPendingHazards();
  MCELFStreamer::emitFill(NumValues, Size, Expr, Loc);
}

void MipsELFStreamer::EmitMipsOptionRecords() {
  for (const auto &I : MipsOptionRecords)
    I->EmitMipsOptionRecord();
}

MCELFStreamer *
llvm::createMipsELFStreamer(MCContext &Context,
                            std::unique_ptr<MCAsmBackend> MAB,
                            std::unique_ptr<MCObjectWriter> OW,
                            std::unique_ptr<MCCodeEmitter> Emitter) {
  return new MipsELFStreamer(Context, std::move(MAB), std::move(OW),
                             std::move(Emitter));
}
