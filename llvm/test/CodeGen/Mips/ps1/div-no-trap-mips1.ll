; The R3000A (MIPS I) has no conditional trap instructions: teq, tne, tge,
; tgeu, tlt and tltu are MIPS II and raise a Reserved Instruction exception.
; Integer division by zero must therefore be checked with a branch and
; `break 7`, never with a trap (backport of llvm/llvm-project#201133, MIC-11).
; See docs/ps1/hazards.md, H12. The exact GCC instruction sequence is checked
; in div-zero-check.ll.
;
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -O0 \
; RUN:   | FileCheck %s --implicit-check-not='{{[[:space:]]t(eq|ne|ge|geu|lt|ltu)i?[[:space:]]}}'
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -O2 \
; RUN:   | FileCheck %s --implicit-check-not='{{[[:space:]]t(eq|ne|ge|geu|lt|ltu)i?[[:space:]]}}'

define i32 @sdiv(i32 %a, i32 %b) {
; CHECK-LABEL: sdiv:
; CHECK:       break 7
  %r = sdiv i32 %a, %b
  ret i32 %r
}

define i32 @udiv(i32 %a, i32 %b) {
; CHECK-LABEL: udiv:
; CHECK:       break 7
  %r = udiv i32 %a, %b
  ret i32 %r
}

define i32 @srem(i32 %a, i32 %b) {
; CHECK-LABEL: srem:
; CHECK:       break 7
  %r = srem i32 %a, %b
  ret i32 %r
}

define i32 @urem(i32 %a, i32 %b) {
; CHECK-LABEL: urem:
; CHECK:       break 7
  %r = urem i32 %a, %b
  ret i32 %r
}
