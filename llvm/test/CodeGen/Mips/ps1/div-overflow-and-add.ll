; Arithmetic results the hardware defines without trapping:
; * div INT_MIN / -1 gives LO=0x80000000, HI=0 and no exception (psx-spx "CPU
;   Multiply/Divide Opcodes"). GCC 16 adds no check; ASPSX added `break 6`,
;   which is opt-in here (MIC-61).
; * Wrapping adds use addu/addiu, never the trapping add/addi.
; See docs/ps1/hazards.md, H13.
;
; Status: correct in LLVM 22.1.8.
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

define i32 @sdiv_no_overflow_check(i32 %a, i32 %b) {
; CHECK-LABEL: sdiv_no_overflow_check:
; CHECK-NOT:   break 6
; CHECK:       div $zero, $4, $5
; CHECK-NOT:   break 6
; CHECK:       .end sdiv_no_overflow_check
  %r = sdiv i32 %a, %b
  ret i32 %r
}

define i32 @add_wraps(i32 %a, i32 %b) {
; CHECK-LABEL: add_wraps:
; CHECK-NOT:   {{[[:space:]]add[[:space:]]}}
; CHECK:       addu $2,
  %r = add nsw i32 %a, %b
  ret i32 %r
}

define i32 @addi_wraps(i32 %a) {
; CHECK-LABEL: addi_wraps:
; CHECK-NOT:   {{[[:space:]]addi[[:space:]]}}
; CHECK:       addiu $2, $4, 100
  %r = add nsw i32 %a, 100
  ret i32 %r
}
