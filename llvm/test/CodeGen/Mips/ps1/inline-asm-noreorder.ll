; Who pads a hazard at an inline asm boundary (MIC-21, docs/ps1/hazards.md, H9):
;
; * The compiler's own load before asm: the compiler pads it, since the asm
;   text may read the register by name.
; * A hazard the asm leaves at its end is on the asm's side. Codegen adds
;   nothing. The asm is assembled in reorder mode, so the assembler pads it
;   when the next instruction needs it, as gas does across #APP; in assembly
;   output, the assembler that reads the file does.
; * Code in `.set noreorder` is never changed, inside asm or out, so a
;   hand-written old-value read in a load delay slot stays as written, and a
;   noreorder load at the end of an asm block is the programmer's.
;
; RUN: llc < %s -mtriple=mipsel-sony-psx -filetype=obj \
; RUN:   | llvm-objdump -d --no-show-raw-insn - | FileCheck %s --check-prefix=OBJ
; RUN: llc < %s -mtriple=mipsel-sony-psx | FileCheck %s --check-prefix=ASM

; The noreorder asm reads the old value of $t then: it is emitted as written.
define i32 @old_value(ptr %p, i32 %old) {
; OBJ-LABEL: <old_value>:
; OBJ:       lw $5, 0x0($4)
; OBJ-NEXT:  move $2, $5
;
; ASM-LABEL: old_value:
; ASM:       .set reorder
; ASM-EMPTY:
; ASM-NEXT:  .set noreorder
; ASM-NEXT:  lw $5, 0($4)
; ASM-NEXT:  move $2, $5
; ASM-NEXT:  .set reorder
  %r = call { i32, i32 } asm sideeffect ".set noreorder\0A\09lw $1, 0($2)\0A\09addu $0, $1, $$zero\0A\09.set reorder", "=&r,=r,r,1"(ptr %p, i32 %old)
  %v = extractvalue { i32, i32 } %r, 0
  ret i32 %v
}

; The compiler's load, then asm that reads it: the compiler pads.
define i32 @load_then_asm(ptr %p) {
; OBJ-LABEL: <load_then_asm>:
; OBJ:       lw $[[R:[0-9]+]], 0x0($4)
; OBJ-NEXT:  nop
; OBJ-NEXT:  move $2, $[[R]]
;
; ASM-LABEL: load_then_asm:
; ASM:       lw $[[R:[0-9]+]], 0($4)
; ASM-NEXT:  nop
; ASM-NEXT:  #APP
  %v = load i32, ptr %p
  %r = call i32 asm sideeffect "addu $0, $1, $$zero", "=r,r"(i32 %v)
  ret i32 %r
}

; Asm ends in a load that the compiler reads next. Codegen adds nothing; the
; assembler pads the object.
define void @asm_load_then_use(ptr %p, ptr %q) {
; OBJ-LABEL: <asm_load_then_use>:
; OBJ:       lw $[[R:[0-9]+]], 0x0($4)
; OBJ-NEXT:  nop
; OBJ-NEXT:  addiu ${{[0-9]+}}, $[[R]], 0x1
;
; ASM-LABEL: asm_load_then_use:
; ASM:       lw $[[R:[0-9]+]], 0($4)
; ASM:       #NO_APP
; ASM-NEXT:  addiu ${{[0-9]+}}, $[[R]], 1
  %v = call i32 asm sideeffect "lw $0, 0($1)", "=r,r"(ptr %p)
  %r = add i32 %v, 1
  store volatile i32 %r, ptr %q
  store volatile i32 %r, ptr %p
  ret void
}

; The same load in noreorder asm is the programmer's: nothing is added.
define void @asm_noreorder_load_then_use(ptr %p, ptr %q) {
; OBJ-LABEL: <asm_noreorder_load_then_use>:
; OBJ:       lw $[[R:[0-9]+]], 0x0($4)
; OBJ-NEXT:  addiu ${{[0-9]+}}, $[[R]], 0x1
  %v = call i32 asm sideeffect ".set noreorder\0A\09lw $0, 0($1)\0A\09.set reorder", "=r,r"(ptr %p)
  %r = add i32 %v, 1
  store volatile i32 %r, ptr %q
  store volatile i32 %r, ptr %p
  ret void
}

; An asm block with no instructions leaves no hazard.
define i32 @empty_asm(i32 %x) {
; OBJ-LABEL: <empty_asm>:
; OBJ-NOT:   nop
; OBJ:       jr $ra
  %r = call i32 asm sideeffect "", "=r,0"(i32 %x)
  %s = add i32 %r, 1
  ret i32 %s
}
