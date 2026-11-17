; DMA and plain memory on the PS1. There is no data cache and the write queue
; is FIFO, so the hardware needs no barrier instruction between building a DMA
; buffer in RAM and the volatile MMIO write that starts the transfer. The
; compiler does: `volatile` only orders volatile accesses, and the buffer stores
; are plain stores. A fence (which emits no instruction on mips1, MIC-12), a
; signal fence, or an asm memory clobber keeps them. See fence-mips1.ll for the
; machine code.
;
; RUN: opt < %s -S -O2 | FileCheck %s

target triple = "mipsel-unknown-none-elf"

; 528486568 is DMA2 (GPU) CHCR, 0x1f8010a8. 16778241 is 0x01000401: start a
; linked-list transfer to the GPU. Bit 24 (16777216) stays set while busy.

; The hazard: the packet is built, DMA is started, and the buffer is reused.
; Without a barrier the first store is dead as far as C and LLVM IR are
; concerned, and -O2 deletes it, so DMA reads stale data. This documents
; current behaviour; if LLVM stops deleting the store, the barrier is still
; required by the language rules.
define void @reuse_without_barrier(ptr %buf, i32 %a, i32 %b) {
; CHECK-LABEL: @reuse_without_barrier(
; CHECK-NOT:   store i32 %a
; CHECK:       store volatile i32 16778241
; CHECK-NEXT:  store i32 %b, ptr %buf
  store i32 %a, ptr %buf
  store volatile i32 16778241, ptr inttoptr (i32 528486568 to ptr)
  store i32 %b, ptr %buf
  ret void
}

; C11 atomic_thread_fence(memory_order_release).
define void @reuse_with_fence(ptr %buf, i32 %a, i32 %b) {
; CHECK-LABEL: @reuse_with_fence(
; CHECK:       store i32 %a, ptr %buf
; CHECK-NEXT:  fence release
; CHECK-NEXT:  store volatile i32 16778241
; CHECK-NEXT:  store i32 %b, ptr %buf
  store i32 %a, ptr %buf
  fence release
  store volatile i32 16778241, ptr inttoptr (i32 528486568 to ptr)
  store i32 %b, ptr %buf
  ret void
}

; C11 atomic_signal_fence(memory_order_release).
define void @reuse_with_signal_fence(ptr %buf, i32 %a, i32 %b) {
; CHECK-LABEL: @reuse_with_signal_fence(
; CHECK:       store i32 %a, ptr %buf
; CHECK-NEXT:  fence syncscope("singlethread") release
; CHECK-NEXT:  store volatile i32 16778241
; CHECK-NEXT:  store i32 %b, ptr %buf
  store i32 %a, ptr %buf
  fence syncscope("singlethread") release
  store volatile i32 16778241, ptr inttoptr (i32 528486568 to ptr)
  store i32 %b, ptr %buf
  ret void
}

; asm volatile("" ::: "memory"), the idiom much PS1 code uses.
define void @reuse_with_asm_clobber(ptr %buf, i32 %a, i32 %b) {
; CHECK-LABEL: @reuse_with_asm_clobber(
; CHECK:       store i32 %a, ptr %buf
; CHECK-NEXT:  call void asm sideeffect "", "~{memory}"()
; CHECK-NEXT:  store volatile i32 16778241
; CHECK-NEXT:  store i32 %b, ptr %buf
  store i32 %a, ptr %buf
  call void asm sideeffect "", "~{memory}"()
  store volatile i32 16778241, ptr inttoptr (i32 528486568 to ptr)
  store i32 %b, ptr %buf
  ret void
}

; The read side: after polling CHCR until the transfer is done, an acquire
; fence makes the buffer be read again rather than reusing the value loaded
; before the transfer.
define i32 @read_after_dma(ptr %buf) {
; CHECK-LABEL: @read_after_dma(
; CHECK:       %before = load i32, ptr %buf
; CHECK:       load volatile i32, ptr inttoptr (i32 528486568 to ptr)
; CHECK:       fence acquire
; CHECK-NEXT:  %after = load i32, ptr %buf
; CHECK-NEXT:  sub i32 %after, %before
entry:
  %before = load i32, ptr %buf
  store volatile i32 16778241, ptr inttoptr (i32 528486568 to ptr)
  br label %poll
poll:
  %c = load volatile i32, ptr inttoptr (i32 528486568 to ptr)
  %busy = and i32 %c, 16777216
  %b = icmp ne i32 %busy, 0
  br i1 %b, label %poll, label %done
done:
  fence acquire
  %after = load i32, ptr %buf
  %r = sub i32 %after, %before
  ret i32 %r
}
