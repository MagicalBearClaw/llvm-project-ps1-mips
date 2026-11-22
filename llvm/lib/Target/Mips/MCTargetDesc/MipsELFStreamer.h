//===- MipsELFStreamer.h - ELF Object Output --------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This is a custom MCELFStreamer which allows us to insert some hooks before
// emitting data into an actual object file.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_MIPS_MCTARGETDESC_MIPSELFSTREAMER_H
#define LLVM_LIB_TARGET_MIPS_MCTARGETDESC_MIPSELFSTREAMER_H

#include "MipsOptionRecord.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/MC/MCELFStreamer.h"
#include "llvm/MC/MCInst.h"
#include <array>
#include <memory>
#include <optional>

namespace llvm {

class MCAsmBackend;
class MCCodeEmitter;
class MCContext;
class MCInstrInfo;
class MCSubtargetInfo;
struct MCDwarfFrameInfo;

class MipsELFStreamer : public MCELFStreamer {
  SmallVector<std::unique_ptr<MipsOptionRecord>, 8> MipsOptionRecords;
  MipsRegInfoRecord *RegInfoRecord;
  SmallVector<MCSymbol*, 4> Labels;

  // MIPS I hazard padding for assembler input under `.set reorder`, the way
  // gas does it (docs/ps1/hazards.md, H1, H4, H5, H6, H9). Like gas, it keeps
  // the last two instructions and what each still waits for:
  //  * a load or coprocessor read: the next instruction must not read the
  //    register;
  //  * mflo/mfhi: the next two must not write LO/HI;
  //  * mtc0/mtc2: the next must not be a coprocessor instruction.
  //
  // Code in `.set noreorder`, and all codegen output, is never changed: a
  // hazard between two noreorder instructions is the programmer's. A hazard
  // with a reorder instruction on one side is padded. When the consumer is a
  // noreorder instruction, the noreorder code is held back until the hazard
  // runs out, and the nops go before all of it, so none lands inside it or
  // between a branch and its delay slot.
public:
  struct HazardSource {
    enum KindTy { None, Load, ReadHiLo, CopWrite } Kind = None;
    // Load: the GPR loaded, or none for lwc2, which gas checks against no
    // instruction. ReadHiLo: Mips::HI0 or Mips::LO0.
    MCRegister Reg;
  };

private:
  struct HistoryEntry {
    HazardSource Src;
    // Emitted by the assembler parser in reorder mode.
    bool Reorder = false;
  };
  // The last two instructions emitted, most recent first.
  std::array<HistoryEntry, 2> History;
  // Set while the assembler parser emits instructions in reorder mode.
  bool RecordHazards = false;
  // Created on the first MIPS I instruction. The parser's own MCInstrInfo
  // does not live long enough: codegen follows an inline asm block.
  std::unique_ptr<MCInstrInfo> HazardMII;
  const MCSubtargetInfo *HistorySTI = nullptr;

  // What was held back: labels seen while a hazard may still need nops
  // before them, and noreorder instructions that a reorder hazard reaches.
  struct HeldBack {
    MCSymbol *Label = nullptr;
    SMLoc Loc;
    MCInst Inst;
    const MCSubtargetInfo *STI = nullptr;
  };
  SmallVector<HeldBack, 4> Held;
  unsigned HeldInstructions = 0;

  /// The nops needed before \p Inst, \p Age instructions after the current
  /// history, or before anything that is not an instruction if \p Inst is
  /// null. Only entries with a reorder side count, unless \p Reorder.
  unsigned nopsBefore(const MCInst *Inst, bool Reorder, unsigned Age = 0) const;
  unsigned requiredDistance(const HazardSource &Src, const MCInst *Inst) const;
  /// Whether a reorder hazard can still need nops \p Age instructions after
  /// the current history.
  bool reorderHazardPending(unsigned Age) const;
  void emitAndRecord(const MCInst &Inst, const MCSubtargetInfo &STI,
                     bool Reorder);
  void emitHazardNops(unsigned Count);
  /// Pad for the held-back noreorder instructions, then emit what was held.
  /// \p UnknownNext pads as if anything may follow them.
  void releaseHeld(bool UnknownNext);
  /// Emit the held labels, when no instruction is held.
  void emitHeldLabels();

public:
  /// Record hazards from the instructions that follow, and pad after them.
  /// The parser enables it under `.set reorder` on MIPS I.
  void setHazardPadding(bool Enable);

  /// The next thing emitted is not an instruction, so pad for the worst case,
  /// as gas does when it cannot see the next instruction.
  void flushPendingHazards();

  ~MipsELFStreamer() override;
  MipsELFStreamer(MCContext &Context, std::unique_ptr<MCAsmBackend> MAB,
                  std::unique_ptr<MCObjectWriter> OW,
                  std::unique_ptr<MCCodeEmitter> Emitter);

  /// Overriding this function allows us to add arbitrary behaviour before the
  /// \p Inst is actually emitted. For example, we can inspect the operands and
  /// gather sufficient information that allows us to reason about the register
  /// usage for the translation unit.
  void emitInstruction(const MCInst &Inst, const MCSubtargetInfo &STI) override;

  /// Overriding this function allows us to record all labels that should be
  /// marked as microMIPS. Based on this data marking is done in
  /// EmitInstruction.
  void emitLabel(MCSymbol *Symbol, SMLoc Loc = SMLoc()) override;

  /// Overriding this function allows us to dismiss all labels that are
  /// candidates for marking as microMIPS when .section directive is processed.
  void switchSection(MCSection *Section, uint32_t Subsection = 0) override;

  /// Overriding these functions allows us to dismiss all labels that are
  /// candidates for marking as microMIPS when .word/.long/.4byte etc
  /// directives are emitted.
  void emitValueImpl(const MCExpr *Value, unsigned Size, SMLoc Loc) override;
  void emitIntValue(uint64_t Value, unsigned Size) override;

  // Anything else that emits bytes pads for pending hazards first.
  void emitBytes(StringRef Data) override;
  void emitULEB128Value(const MCExpr *Value) override;
  void emitSLEB128Value(const MCExpr *Value) override;
  void emitValueToAlignment(Align Alignment, int64_t Fill, uint8_t FillLen,
                            unsigned MaxBytesToEmit) override;
  void emitCodeAlignment(Align ByteAlignment, const MCSubtargetInfo *STI,
                         unsigned MaxBytesToEmit) override;
  void emitValueToOffset(const MCExpr *Offset, unsigned char Value,
                         SMLoc Loc) override;
  using MCStreamer::emitFill;
  void emitFill(const MCExpr &NumBytes, uint64_t FillValue, SMLoc Loc) override;
  void emitFill(const MCExpr &NumValues, int64_t Size, int64_t Expr,
                SMLoc Loc) override;

  // Overriding these functions allows us to avoid recording of these labels
  // in EmitLabel and later marking them as microMIPS.
  void emitCFIStartProcImpl(MCDwarfFrameInfo &Frame) override;
  void emitCFIEndProcImpl(MCDwarfFrameInfo &Frame) override;
  MCSymbol *emitCFILabel() override;

  /// Emits all the option records stored up until the point it's called.
  void EmitMipsOptionRecords();

  /// Mark labels as microMIPS, if necessary for the subtarget.
  void createPendingLabelRelocs();
};

MCELFStreamer *createMipsELFStreamer(MCContext &Context,
                                     std::unique_ptr<MCAsmBackend> MAB,
                                     std::unique_ptr<MCObjectWriter> OW,
                                     std::unique_ptr<MCCodeEmitter> Emitter);
} // end namespace llvm

#endif // LLVM_LIB_TARGET_MIPS_MCTARGETDESC_MIPSELFSTREAMER_H
