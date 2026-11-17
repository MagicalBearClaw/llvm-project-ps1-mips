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

; Starting a DMA transfer: the packet is written with plain stores, then
; DMA2 MADR (0x1f8010a0) and CHCR (0x1f8010a8) with volatile ones. No
; instruction is needed between them (no data cache, FIFO write queue), but the
; packet stores must stay before the volatile ones. See dma-barrier-opt.ll for
; why the barrier is needed.
define void @dma_kick(ptr %pkt, i32 %w0, i32 %w1) {
; CHECK-LABEL: dma_kick:
; CHECK-DAG:   sw $5, 0($4)
; CHECK-DAG:   sw $6, 4($4)
; CHECK:       #MEMBARRIER
; The address is built with lui+ori and stored at offset 0, where GCC folds the
; low half into the store. That is a size issue for MIC-52, not an ordering one.
; CHECK:       ori $[[MADR:[0-9]+]], ${{[0-9]+}}, 4256
; CHECK:       sw $4, 0($[[MADR]])
; CHECK:       ori $[[CHCR:[0-9]+]], ${{[0-9]+}}, 4264
; CHECK:       sw ${{[0-9]+}}, 0($[[CHCR]])
  store i32 %w0, ptr %pkt
  %p1 = getelementptr i32, ptr %pkt, i32 1
  store i32 %w1, ptr %p1
  fence release
  %addr = ptrtoint ptr %pkt to i32
  store volatile i32 %addr, ptr inttoptr (i32 528486560 to ptr)
  store volatile i32 16778241, ptr inttoptr (i32 528486568 to ptr)
  ret void
}
