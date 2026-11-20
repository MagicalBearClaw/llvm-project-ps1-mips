; Inline asm is assembled in `.set reorder` mode, as GCC does, so a load inside
; it whose result the next asm instruction reads gets a nop in the object file
; (MIC-19, docs/ps1/hazards.md, H1). Assembly output keeps the asm text as
; written inside `.set reorder`, and the assembler that reads it pads it.
;
; RUN: llc < %s -mtriple=mipsel-sony-psx -filetype=obj \
; RUN:   | llvm-objdump -d --no-show-raw-insn - | FileCheck %s --check-prefix=OBJ
; RUN: llc < %s -mtriple=mipsel-sony-psx | FileCheck %s --check-prefix=ASM

define i32 @load_then_use(ptr %p) {
; OBJ-LABEL: <load_then_use>:
; OBJ:       lw $2, 0x0($4)
; OBJ-NEXT:  nop
; OBJ-NEXT:  addiu $2, $2, 0x1
;
; ASM-LABEL: load_then_use:
; ASM:       .set reorder
; ASM:       lw $2, 0($4)
; ASM-NEXT:  addiu $2, $2, 1
  %r = call i32 asm sideeffect "lw $0, 0($1)\0A\09addiu $0, $0, 1", "=&r,r"(ptr %p)
  ret i32 %r
}

define i32 @load_then_other(ptr %p, i32 %x) {
; OBJ-LABEL: <load_then_other>:
; OBJ:       lw $2, 0x0($4)
; OBJ-NEXT:  addiu $5, $5, 0x1
  %r = call i32 asm sideeffect "lw $0, 0($1)\0A\09addiu $2, $2, 1", "=&r,r,r"(ptr %p, i32 %x)
  ret i32 %r
}
