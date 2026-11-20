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

  // MIPS I load delay padding for assembler input under `.set reorder`, the
  // way gas does it (docs/ps1/hazards.md, H1). The register written by a load
  // is not ready for the next instruction, so a nop goes in between when the
  // next instruction reads it.
  struct DelayedLoad {
    // The GPR being loaded. No register for lwc2: gas checks no conflict for
    // it, but still pads when the next thing emitted is not an instruction.
    MCRegister Reg;
    const MCSubtargetInfo *STI;
  };
  // Set while the assembler parser emits instructions in reorder mode.
  const MCInstrInfo *LoadDelayMII = nullptr;
  // Kept after recording stops, to check the instruction that follows.
  const MCInstrInfo *PendingLoadMII = nullptr;
  std::optional<DelayedLoad> PendingLoad;
  // Labels seen while a load is pending. gas puts the nop before them, and
  // whether it is needed depends on the instruction after them.
  SmallVector<std::pair<MCSymbol *, SMLoc>, 2> DeferredLabels;

  bool readsPendingLoad(const MCInst &Inst) const;
  void emitLoadDelayNop();
  void emitDeferredLabels();

public:
  /// Record loads from the instructions that follow, and pad after them, if
  /// \p MII is not null. The parser sets it under `.set reorder` on MIPS I.
  void setLoadDelayPadding(const MCInstrInfo *MII) { LoadDelayMII = MII; }

  /// The next thing emitted is not an instruction, so pad after a pending
  /// load the way gas does when it cannot see the next instruction.
  void flushPendingLoad();

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

  // Anything else that emits bytes ends a pending load delay first.
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
