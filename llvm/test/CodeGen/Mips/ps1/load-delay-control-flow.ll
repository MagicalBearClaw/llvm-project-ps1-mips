; R3000A load delay across control flow. A load placed in a branch delay slot
; is still in flight when the first instruction at the branch target (or the
; return address) executes. See docs/ps1/hazards.md, H2.
;
; Status: correct in LLVM 22.1.8 (MipsDelaySlotFiller::delayHasHazard refuses
; loads in the delay slot of calls, returns and indirect branches, and checks
; the first instruction of both successors of a conditional branch).
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

declare i32 @ext(i32)

; The callee may read $a0 in its first instruction, so the load must not sit in
; the jal delay slot.
define i32 @load_then_call(ptr %p) {
; CHECK-LABEL: load_then_call:
; CHECK:       lw $4, 0($4)
; CHECK-NOT:   lw
; CHECK:       jal ext
; CHECK-NEXT:  nop
  %v = load i32, ptr %p
  %r = call i32 @ext(i32 %v)
  ret i32 %r
}

; The caller may read $v0 right after returning, so the load must not sit in
; the jr $ra delay slot.
define i32 @load_ret(ptr %p) {
; CHECK-LABEL: load_ret:
; CHECK:       lw $2, 0($4)
; CHECK-NEXT:  jr $ra
; CHECK-NEXT:  nop
  %v = load i32, ptr %p
  ret i32 %v
}

; Both successors read the loaded value in their first instruction. The load
; must not be moved into the branch delay slot without a following nop.
define i32 @load_both_succ(ptr %p, i32 %c) {
; CHECK-LABEL: load_both_succ:
; CHECK:       lw $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  {{beqz|bnez|beq|bne}}
; CHECK-NOT:   lw
; CHECK:       $[[R]]
entry:
  %v = load i32, ptr %p
  %t = icmp eq i32 %c, 0
  br i1 %t, label %a, label %b
a:
  %r1 = mul i32 %v, 3
  ret i32 %r1
b:
  %r2 = mul i32 %v, 5
  ret i32 %r2
}
