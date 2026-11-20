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
  // gas does it (docs/ps1/hazards.md, H1, H4, H5, H6). Like gas, it keeps the
  // last two instructions and what each still waits for:
  //  * a load or coprocessor read: the next instruction must not read the
  //    register;
  //  * mflo/mfhi: the next two must not write LO/HI;
  //  * mtc0/mtc2: the next must not be a coprocessor instruction.
public:
  struct HazardSource {
    enum KindTy { None, Load, ReadHiLo, CopWrite } Kind = None;
    // Load: the GPR loaded, or none for lwc2, which gas checks against no
    // instruction. ReadHiLo: Mips::HI0 or Mips::LO0.
    MCRegister Reg;
  };

private:
  // The last two instructions emitted, most recent first.
  std::array<HazardSource, 2> History;
  // Set while the assembler parser emits instructions in reorder mode.
  bool RecordHazards = false;
  // Created when recording first starts, and kept to check the instructions
  // that follow, which may come from codegen after an inline asm block. The
  // parser's own MCInstrInfo may not live that long.
  std::unique_ptr<MCInstrInfo> HazardMII;
  const MCSubtargetInfo *HistorySTI = nullptr;
  // Labels seen while a hazard is pending. gas puts the nops before them, and
  // how many depends on the instruction after them.
  SmallVector<std::pair<MCSymbol *, SMLoc>, 2> DeferredLabels;

  /// The nops needed before \p Inst, or before anything that is not an
  /// instruction if \p Inst is null.
  unsigned nopsBefore(const MCInst *Inst) const;
  unsigned requiredDistance(const HazardSource &Src, const MCInst *Inst) const;
  void pushHistory(HazardSource Src);
  void emitHazardNops(unsigned Count);
  void emitDeferredLabels();

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
