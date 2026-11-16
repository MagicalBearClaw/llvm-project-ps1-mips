; R3000A load delay: the register loaded by lb/lbu/lh/lhu/lw is not available
; to the next instruction (psx-spx "CPU Load/Store Opcodes", Caution - Load
; Delay). The next instruction must not read it. See docs/ps1/hazards.md, H1.
; The slot may hold any instruction that does not read the register; GCC 16
; puts the `jr $ra` there too.
;
; Status: correct in LLVM 22.1.8 (MipsBranchExpansion::handleLoadDelaySlot).
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

define i32 @lw_use(ptr %p) {
; CHECK-LABEL: lw_use:
; CHECK:       lw $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  {{(nop|jr[[:space:]]+\$ra)$}}
; CHECK-NEXT:  {{.*}}$[[R]]
  %v = load i32, ptr %p
  %r = add i32 %v, 1
  ret i32 %r
}

define i32 @lb_use(ptr %p) {
; CHECK-LABEL: lb_use:
; CHECK:       lb $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  {{(nop|jr[[:space:]]+\$ra)$}}
; CHECK-NEXT:  {{.*}}$[[R]]
  %v = load i8, ptr %p
  %s = sext i8 %v to i32
  %r = add i32 %s, 1
  ret i32 %r
}

define i32 @lbu_use(ptr %p) {
; CHECK-LABEL: lbu_use:
; CHECK:       lbu $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  {{(nop|jr[[:space:]]+\$ra)$}}
; CHECK-NEXT:  {{.*}}$[[R]]
  %v = load i8, ptr %p
  %z = zext i8 %v to i32
  %r = add i32 %z, 1
  ret i32 %r
}

define i32 @lh_use(ptr %p) {
; CHECK-LABEL: lh_use:
; CHECK:       lh $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  {{(nop|jr[[:space:]]+\$ra)$}}
; CHECK-NEXT:  {{.*}}$[[R]]
  %v = load i16, ptr %p
  %s = sext i16 %v to i32
  %r = add i32 %s, 1
  ret i32 %r
}

define i32 @lhu_use(ptr %p) {
; CHECK-LABEL: lhu_use:
; CHECK:       lhu $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  {{(nop|jr[[:space:]]+\$ra)$}}
; CHECK-NEXT:  {{.*}}$[[R]]
  %v = load i16, ptr %p
  %z = zext i16 %v to i32
  %r = add i32 %z, 1
  ret i32 %r
}

; A load whose result feeds a branch condition.
define i32 @lw_branch(ptr %p, i32 %a) {
; CHECK-LABEL: lw_branch:
; CHECK:       lw $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  nop
  %v = load i32, ptr %p
  %c = icmp eq i32 %v, 0
  br i1 %c, label %z, label %nz
z:
  ret i32 7
nz:
  ret i32 %a
}
