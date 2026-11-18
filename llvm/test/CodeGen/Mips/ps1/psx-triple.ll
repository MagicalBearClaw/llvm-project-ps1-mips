; The mipsel-sony-psx triple (MIC-15) selects the r3000a CPU when no -mcpu is
; given, and r3000a does not print the "MIPS-I support is experimental"
; warning that plain mips1 does.
;
; RUN: llc < %s -mtriple=mipsel-sony-psx -relocation-model=static 2>&1 \
; RUN:   | FileCheck %s --implicit-check-not=experimental
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 2>&1 \
; RUN:   | FileCheck %s --check-prefix=MIPS1

; MIPS1: warning: MIPS-I support is experimental

; r3000a: soft-float and MIPS I load delays.
define float @fadd(float %a, float %b) {
; CHECK-LABEL: fadd:
; CHECK:       jal __addsf3
  %r = fadd float %a, %b
  ret float %r
}

define void @load_use(ptr %p) {
; CHECK-LABEL: load_use:
; CHECK:       lw $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  nop
; CHECK-NEXT:  addiu ${{[0-9]+}}, $[[R]], 1
  %v = load i32, ptr %p
  %r = add i32 %v, 1
  store i32 %r, ptr %p
  ret void
}
