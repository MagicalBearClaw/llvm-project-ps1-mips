; HI/LO hazard: an mflo/mfhi followed within two instructions by an instruction
; that writes HI/LO (mult/multu/div/divu/mthi/mtlo) gives an undefined result on
; the R3000 family. GCC 16 and gas keep two instructions between them.
; Reading HI/LO while mult/div is busy is interlocked (psx-spx "CPU
; Multiply/Divide Opcodes"). See docs/ps1/hazards.md, H4.
;
; Status: correct in LLVM 22.1.8 (MipsBranchExpansion::handleMFLO).
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

; The div is placed in the delay slot of the divide-by-zero check branch, so the
; hazard has to be found inside the branch bundle. One nop plus the branch make
; the two instructions.
define i32 @mul_then_div(i32 %a, i32 %b, i32 %c) {
; CHECK-LABEL: mul_then_div:
; CHECK:       mult
; CHECK-NEXT:  mflo $[[R:[0-9]+]]
; CHECK-NEXT:  nop
; CHECK-NEXT:  bnez $6,
; CHECK-NEXT:  div $zero, $[[R]], $6
  %m = mul i32 %a, %b
  %d = sdiv i32 %m, %c
  ret i32 %d
}

; mflo then mfhi is fine back to back: neither writes HI/LO.
define i64 @mul64(i32 %a, i32 %b) {
; CHECK-LABEL: mul64:
; CHECK:       mult
; CHECK-NEXT:  mflo $2
; CHECK-NEXT:  mfhi $3
  %x = sext i32 %a to i64
  %y = sext i32 %b to i64
  %m = mul i64 %x, %y
  ret i64 %m
}
