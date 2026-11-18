; -mcpu=r3000a (MIC-14): MIPS I with soft-float, notraps and gte. The MIPS I
; hazards come from the ISA level, so r3000a gets exactly the same hazard
; handling as mips1.
;
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=r3000a \
; RUN:   -relocation-model=static | FileCheck %s
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=r3000a \
; RUN:   -mattr=help 2>&1 | FileCheck %s --check-prefix=HELP

; The ELF header and MIPS ABI flags are those of -mcpu=mips1 -mattr=+soft-float.
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=r3000a \
; RUN:   -relocation-model=static -filetype=obj -o - \
; RUN:   | llvm-readelf -h -A - > %t.r3000a
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -filetype=obj -o - \
; RUN:   | llvm-readelf -h -A - > %t.mips1
; RUN: diff %t.mips1 %t.r3000a
; RUN: FileCheck %s --check-prefix=ELF < %t.r3000a

; ELF: ISA: MIPS1
; ELF: FP ABI: Soft float

; HELP-DAG: gte {{.*}}GTE (COP2)
; HELP-DAG: notraps {{.*}}trap instructions
; HELP-DAG: r3000a {{.*}}R3000A

; Load delay: the use of a loaded register is one instruction later.
define void @load_use(ptr %p) {
; CHECK-LABEL: load_use:
; CHECK:       lw $[[R:[0-9]+]], 0($4)
; CHECK-NEXT:  nop
; CHECK-NEXT:  addiu $[[S:[0-9]+]], $[[R]], 1
; CHECK-NEXT:  jr $ra
; CHECK-NEXT:  sw $[[S]], 0($4)
  %v = load i32, ptr %p
  %r = add i32 %v, 1
  store i32 %r, ptr %p
  ret void
}

; HI/LO: two instructions between mflo and the next div.
define i32 @mul_then_div(i32 %a, i32 %b, i32 %c) {
; CHECK-LABEL: mul_then_div:
; CHECK:       mflo $[[M:[0-9]+]]
; CHECK-NEXT:  nop
; CHECK-NEXT:  bnez $6,
; CHECK-NEXT:  div $zero, $[[M]], $6
; CHECK-NEXT:  # %bb.1:
; CHECK-NEXT:  break 7
  %m = mul i32 %a, %b
  %d = sdiv i32 %m, %c
  ret i32 %d
}

; soft-float is part of r3000a: float arithmetic is a libcall.
define float @fadd(float %a, float %b) {
; CHECK-LABEL: fadd:
; CHECK:       jal __addsf3
  %r = fadd float %a, %b
  ret float %r
}
