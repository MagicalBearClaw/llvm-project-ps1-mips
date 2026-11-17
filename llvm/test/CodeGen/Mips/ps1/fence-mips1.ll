; MIPS I has no `sync` (MIPS II); the R3000A raises a Reserved Instruction
; exception on it. The PS1 has one CPU, and the only concurrency is interrupt
; handlers on that CPU, so a fence only has to stop the compiler from moving
; memory accesses across it (backport of llvm/llvm-project#190129, MIC-12).
;
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -O2 | FileCheck %s --implicit-check-not=sync

@a = global i32 0
@b = global i32 0

define void @fences() {
; CHECK-LABEL: fences:
  fence acquire
  fence release
  fence acq_rel
  fence seq_cst
  fence syncscope("singlethread") seq_cst
  ret void
}

; The fence is still a compiler barrier: the store to @a stays before the load
; of @b.
define i32 @store_fence_load(i32 %x) {
; CHECK-LABEL: store_fence_load:
; CHECK:       sw $4, %lo(a)(
; CHECK:       #MEMBARRIER
; CHECK:       lw $2, %lo(b)(
  store i32 %x, ptr @a
  fence seq_cst
  %v = load i32, ptr @b
  ret i32 %v
}
