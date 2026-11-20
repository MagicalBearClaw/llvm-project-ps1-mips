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

// Return the register that \p Inst loads with a delay on MIPS I, if it is a
// load or a coprocessor read whose result is not ready for the next
// instruction (docs/ps1/hazards.md, H1, H5 and H6). lwc2 loads a GTE
// register, not a GPR, and gas checks no conflict for it, so it returns no
// register but still counts as a delayed load.
static std::optional<MCRegister> getDelayedLoad(const MCInst &Inst) {
  switch (Inst.getOpcode()) {
  case Mips::LB:
  case Mips::LBu:
  case Mips::LH:
  case Mips::LHu:
  case Mips::LW:
  case Mips::LWL:
  case Mips::LWR:
  case Mips::MFC0:
  case Mips::MFC2:
    return Inst.getOperand(0).getReg();
  case Mips::LWC2:
    return MCRegister();
  default:
    return std::nullopt;
  }
}

bool MipsELFStreamer::readsPendingLoad(const MCInst &Inst) const {
  MCRegister Reg = PendingLoad->Reg;
  if (!Reg || Reg == Mips::ZERO)
    return false;

  // lwl and lwr merge into their destination, but the merge does not wait for
  // a load still pending to it, so like gas only their base register counts.
  if (Inst.getOpcode() == Mips::LWL || Inst.getOpcode() == Mips::LWR)
    return Inst.getOperand(1).getReg() == Reg;

  // Explicit uses follow the defs.
  const MCInstrDesc &Desc = PendingLoadMII->get(Inst.getOpcode());
  for (unsigned I = Desc.getNumDefs(), E = Inst.getNumOperands(); I != E; ++I) {
    const MCOperand &Op = Inst.getOperand(I);
    if (Op.isReg() && Op.getReg() == Reg)
      return true;
  }
  return llvm::is_contained(Desc.implicit_uses(), Reg);
}

void MipsELFStreamer::emitLoadDelayNop() {
  MCInst Nop;
  Nop.setOpcode(Mips::SLL);
  Nop.addOperand(MCOperand::createReg(Mips::ZERO));
  Nop.addOperand(MCOperand::createReg(Mips::ZERO));
  Nop.addOperand(MCOperand::createImm(0));
  MCELFStreamer::emitInstruction(Nop, *PendingLoad->STI);
}

void MipsELFStreamer::emitDeferredLabels() {
  SmallVector<std::pair<MCSymbol *, SMLoc>, 2> ToEmit;
  std::swap(ToEmit, DeferredLabels);
  for (auto [Symbol, Loc] : ToEmit)
    emitLabel(Symbol, Loc);
}

void MipsELFStreamer::flushPendingLoad() {
  if (!PendingLoad)
    return;
  emitLoadDelayNop();
  PendingLoad.reset();
  emitDeferredLabels();
}

void MipsELFStreamer::emitInstruction(const MCInst &Inst,
                                      const MCSubtargetInfo &STI) {
  if (PendingLoad) {
    if (readsPendingLoad(Inst))
      emitLoadDelayNop();
    PendingLoad.reset();
    emitDeferredLabels();
  }

  MCELFStreamer::emitInstruction(Inst, STI);

  if (LoadDelayMII) {
    if (std::optional<MCRegister> Reg = getDelayedLoad(Inst)) {
      PendingLoad = DelayedLoad{*Reg, &STI};
      PendingLoadMII = LoadDelayMII;
    }
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
  if (PendingLoad) {
    // A held-back label is not defined yet, so a second definition of it is
    // caught here.
    if (llvm::any_of(DeferredLabels,
                     [&](const auto &L) { return L.first == Symbol; })) {
      getContext().reportError(Loc, "invalid symbol redefinition");
      return;
    }
    DeferredLabels.emplace_back(Symbol, Loc);
    return;
  }
  MCELFStreamer::emitLabel(Symbol);
  Labels.push_back(Symbol);
}

void MipsELFStreamer::switchSection(MCSection *Section, uint32_t Subsection) {
  flushPendingLoad();
  MCELFStreamer::switchSection(Section, Subsection);
  Labels.clear();
}

void MipsELFStreamer::emitValueImpl(const MCExpr *Value, unsigned Size,
                                    SMLoc Loc) {
  flushPendingLoad();
  MCELFStreamer::emitValueImpl(Value, Size, Loc);
  Labels.clear();
}

void MipsELFStreamer::emitIntValue(uint64_t Value, unsigned Size) {
  flushPendingLoad();
  MCELFStreamer::emitIntValue(Value, Size);
  Labels.clear();
}

void MipsELFStreamer::emitBytes(StringRef Data) {
  flushPendingLoad();
  MCELFStreamer::emitBytes(Data);
}

void MipsELFStreamer::emitULEB128Value(const MCExpr *Value) {
  flushPendingLoad();
  MCELFStreamer::emitULEB128Value(Value);
}

void MipsELFStreamer::emitSLEB128Value(const MCExpr *Value) {
  flushPendingLoad();
  MCELFStreamer::emitSLEB128Value(Value);
}

void MipsELFStreamer::emitValueToAlignment(Align Alignment, int64_t Fill,
                                           uint8_t FillLen,
                                           unsigned MaxBytesToEmit) {
  flushPendingLoad();
  MCELFStreamer::emitValueToAlignment(Alignment, Fill, FillLen, MaxBytesToEmit);
}

void MipsELFStreamer::emitCodeAlignment(Align ByteAlignment,
                                        const MCSubtargetInfo *STI,
                                        unsigned MaxBytesToEmit) {
  flushPendingLoad();
  MCELFStreamer::emitCodeAlignment(ByteAlignment, STI, MaxBytesToEmit);
}

void MipsELFStreamer::emitValueToOffset(const MCExpr *Offset,
                                        unsigned char Value, SMLoc Loc) {
  flushPendingLoad();
  MCELFStreamer::emitValueToOffset(Offset, Value, Loc);
}

void MipsELFStreamer::emitFill(const MCExpr &NumBytes, uint64_t FillValue,
                               SMLoc Loc) {
  flushPendingLoad();
  MCELFStreamer::emitFill(NumBytes, FillValue, Loc);
}

void MipsELFStreamer::emitFill(const MCExpr &NumValues, int64_t Size,
                               int64_t Expr, SMLoc Loc) {
  flushPendingLoad();
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
