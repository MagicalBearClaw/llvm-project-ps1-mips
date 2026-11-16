; Unaligned word load with lwl/lwr. On the R3000A an lwl/lwr in the delay slot
; of a load to the same register merges with the value still in flight
; (PCSX-Redux InterpretedCPU::mergeUnalignedLoad; gas in reorder mode emits no
; nop between the pair). Only the instruction after the pair must not read the
; register. See docs/ps1/hazards.md, H3.
;
; Status: suboptimal in LLVM 22.1.8: it inserts a nop between lwl and lwr.
; GCC 16 codegen does the same. MIC-55 removes it.
; XFAIL: *
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

%pk = type <{ i8, i32 }>

define i32 @unaligned(ptr %s) {
; CHECK-LABEL: unaligned:
; CHECK:       lwl $[[R:[0-9]+]], 4($4)
; CHECK-NEXT:  lwr $[[R]], 1($4)
; CHECK-NEXT:  nop
; CHECK-NEXT:  {{.*}}$[[R]]
  %f = getelementptr inbounds %pk, ptr %s, i32 0, i32 1
  %v = load i32, ptr %f, align 1
  %r = add i32 %v, 1
  ret i32 %r
}
