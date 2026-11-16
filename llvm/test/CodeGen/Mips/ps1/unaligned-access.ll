; The R3000A raises an address error (AdEL/AdES) on a misaligned lh/lhu/lw or
; sh/sw (psx-spx "COP0 - Exception Handling", BadVaddr). Loads and stores with
; less than natural alignment must be split or use lwl/lwr/swl/swr.
; See docs/ps1/hazards.md, H11.
;
; Status: correct in LLVM 22.1.8.
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

define i32 @load_align1(ptr %p) {
; CHECK-LABEL: load_align1:
; CHECK-NOT:   {{[[:space:]]lw[[:space:]]}}
; CHECK:       lwl
; CHECK:       lwr
  %v = load i32, ptr %p, align 1
  ret i32 %v
}

define void @store_align1(ptr %p, i32 %v) {
; CHECK-LABEL: store_align1:
; CHECK-NOT:   {{[[:space:]]sw[[:space:]]}}
; CHECK:       swl
; CHECK:       swr
  store i32 %v, ptr %p, align 1
  ret void
}

define i32 @load_align2(ptr %p) {
; CHECK-LABEL: load_align2:
; CHECK-NOT:   {{[[:space:]]lw[[:space:]]}}
; CHECK:       {{lwl|lhu}}
; CHECK:       {{lwr|lhu}}
  %v = load i32, ptr %p, align 2
  ret i32 %v
}

define i32 @load_i16_align1(ptr %p) {
; CHECK-LABEL: load_i16_align1:
; CHECK-NOT:   {{[[:space:]]lhu?[[:space:]]}}
; CHECK:       lbu
; CHECK:       lbu
  %v = load i16, ptr %p, align 1
  %z = zext i16 %v to i32
  ret i32 %z
}
