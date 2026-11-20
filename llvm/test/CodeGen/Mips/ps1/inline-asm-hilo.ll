; An mflo at the end of an inline asm block, followed by a compiler-generated
; mult. Codegen cannot see inside the asm, so it adds one nop, as after a load.
; The HI/LO hazard needs two instructions between them. The asm is assembled
; in reorder mode, and the object streamer keeps its last instructions, so the
; second nop is added when the mult is emitted, as gas does (MIC-20,
; docs/ps1/hazards.md, H4).
;
; The streamer checks the mult after the asm parser that emitted the mflo is
; gone, so it must not use anything the parser owned.
;
; RUN: llc < %s -mtriple=mipsel-sony-psx -filetype=obj \
; RUN:   | llvm-objdump -d -z --no-show-raw-insn - | FileCheck %s

define i32 @asm_mflo_then_mult(i32 %b) {
; CHECK-LABEL: <asm_mflo_then_mult>:
; CHECK:       mflo $[[R:[0-9]+]]
; CHECK-NEXT:  nop
; CHECK-NEXT:  nop
; CHECK-NEXT:  mult $[[R]], $4
  %lo = call i32 asm sideeffect "mflo $0", "=r"()
  %m = mul i32 %lo, %b
  ret i32 %m
}
