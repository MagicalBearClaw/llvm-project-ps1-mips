; Divide-by-zero check on MIPS I. The R3000A has no trap instructions (teq is
; MIPS II and raises a Reserved Instruction exception). GCC 16 emits
; `bnez $rt, 1f; div (in the delay slot); break 7; 1:`.
; See docs/ps1/hazards.md, H12.
;
; Status: WRONG in LLVM 22.1.8: it emits `teq $rt, $zero, 7`, which the R3000A
; cannot execute. MIC-22 fixes this.
; XFAIL: *
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

define i32 @sdiv(i32 %a, i32 %b) {
; CHECK-LABEL: sdiv:
; CHECK-NOT:   teq
; CHECK:       bnez $5, [[L:\$[A-Za-z0-9_]+]]
; CHECK-NEXT:  div $zero, $4, $5
; CHECK-NEXT:  break 7
; CHECK:       [[L]]:
; CHECK-NEXT:  mflo $2
  %r = sdiv i32 %a, %b
  ret i32 %r
}

define i32 @udiv(i32 %a, i32 %b) {
; CHECK-LABEL: udiv:
; CHECK-NOT:   teq
; CHECK:       bnez $5,
; CHECK-NEXT:  divu $zero, $4, $5
; CHECK-NEXT:  break 7
  %r = udiv i32 %a, %b
  ret i32 %r
}

define i32 @srem(i32 %a, i32 %b) {
; CHECK-LABEL: srem:
; CHECK-NOT:   teq
; CHECK:       bnez $5,
; CHECK-NEXT:  div $zero, $4, $5
; CHECK-NEXT:  break 7
; CHECK:       mfhi $2
  %r = srem i32 %a, %b
  ret i32 %r
}
