; R3000A hazards that span a block boundary (MIC-17). See docs/ps1/hazards.md,
; H2 and H4.
;
; The instruction after a load (or mflo/mfhi) is decided by execution order: a
; block that falls through continues with the first real instruction of the
; next block, so that instruction is checked like any other. A label in
; between changes nothing, because a branch to the label does not run the
; load. GCC 16 (and gas in reorder mode) apply the same rule. Only an
; unknown next instruction (a call, a return, an indirect branch, the end of
; the function) is assumed to read the register.
;
; Loads in branch delay slots are covered by load-delay-control-flow.ll and
; load-delay-slot-debug.mir.
;
; RUN: llc < %s -mtriple=mipsel-sony-psx -relocation-model=static | FileCheck %s

; The loop header reads the loaded value first: one nop before the label.
define i32 @load_falls_into_use(ptr %p, i32 %n) {
; CHECK-LABEL: load_falls_into_use:
; CHECK:       lw $2, 0($4)
; CHECK-NEXT:  nop
; CHECK-NEXT:  $BB0_1:
; CHECK-NEXT:  # =>This Inner Loop Header: Depth=1
; CHECK-NEXT:  mult $2, $2
entry:
  %v = load volatile i32, ptr %p
  br label %loop
loop:
  %acc = phi i32 [ %v, %entry ], [ %acc2, %loop ]
  %i = phi i32 [ %n, %entry ], [ %i2, %loop ]
  %acc2 = mul i32 %acc, %acc
  %i2 = add i32 %i, -1
  %t = icmp eq i32 %i2, 0
  br i1 %t, label %exit, label %loop
exit:
  ret i32 %acc2
}

; The loop header does not read the loaded value first: no nop. GCC 16 emits
; the same lw; addiu.
define i32 @load_falls_into_other(ptr %p, i32 %n) {
; CHECK-LABEL: load_falls_into_other:
; CHECK:       lw $2, 0($4)
; CHECK-NEXT:  $BB1_1:
; CHECK-NEXT:  # =>This Inner Loop Header: Depth=1
; CHECK-NEXT:  addiu $5, $5, -1
entry:
  %v = load volatile i32, ptr %p
  br label %loop
loop:
  %i = phi i32 [ %n, %entry ], [ %i2, %loop ]
  %i2 = add i32 %i, -1
  %t = icmp eq i32 %i2, 0
  br i1 %t, label %exit, label %loop
exit:
  ret i32 %v
}

; mflo ends the entry block and the loop header multiplies first: two nops.
; On the back edge, addiu, bnez and the delay slot already separate them.
define i32 @mflo_falls_into_mult(i32 %a, i32 %b, i32 %n) {
; CHECK-LABEL: mflo_falls_into_mult:
; CHECK:       mflo $2
; CHECK-NEXT:  nop
; CHECK-NEXT:  nop
; CHECK-NEXT:  $BB2_1:
; CHECK-NEXT:  # =>This Inner Loop Header: Depth=1
; CHECK-NEXT:  mult $2, $6
; CHECK-NEXT:  mflo $2
; CHECK-NEXT:  addiu $6, $6, -1
; CHECK-NEXT:  bnez $6, $BB2_1
; CHECK-NEXT:  nop
entry:
  %m = mul i32 %a, %b
  br label %loop
loop:
  %acc = phi i32 [ %m, %entry ], [ %acc2, %loop ]
  %i = phi i32 [ %n, %entry ], [ %i2, %loop ]
  %acc2 = mul i32 %acc, %i
  %i2 = add i32 %i, -1
  %t = icmp eq i32 %i2, 0
  br i1 %t, label %exit, label %loop
exit:
  ret i32 %acc2
}

; mflo before a branch: the branch and its delay slot are the two instructions,
; so a mult at the target needs no nop.
define i32 @mflo_branch_to_mult(i32 %a, i32 %b, i32 %c, ptr %p) {
; CHECK-LABEL: mflo_branch_to_mult:
; CHECK:       mflo $1
; CHECK-NEXT:  beqz $6, $BB3_2
; CHECK-NEXT:  sw $1, 0($7)
; CHECK-NEXT:  # %bb.1:
; CHECK-NEXT:  mult $6, $6
entry:
  %m = mul i32 %a, %b
  store volatile i32 %m, ptr %p
  %t = icmp eq i32 %c, 0
  br i1 %t, label %out, label %next
next:
  %m2 = mul i32 %c, %c
  ret i32 %m2
out:
  ret i32 0
}

; Inline asm starts the loop header. The compiler cannot see which registers
; the asm text reads, so it pads (MIC-16). gas reads the text, so GCC 16 emits
; no nop here.
define void @load_falls_into_asm(ptr %p, ptr %q, i32 %n) {
; CHECK-LABEL: load_falls_into_asm:
; CHECK:       lw $2, 0($4)
; CHECK-NEXT:  nop
; CHECK-NEXT:  $BB4_1:
; CHECK-NEXT:  # =>This Inner Loop Header: Depth=1
; CHECK-NEXT:  #APP
entry:
  %v = load volatile i32, ptr %p
  br label %loop
loop:
  %i = phi i32 [ %n, %entry ], [ %i2, %loop ]
  call void asm sideeffect "mtc2 $0, $$9", "r"(i32 %i)
  %i2 = add i32 %i, -1
  %t = icmp eq i32 %i2, 0
  br i1 %t, label %exit, label %loop
exit:
  store volatile i32 %v, ptr %q
  ret void
}
