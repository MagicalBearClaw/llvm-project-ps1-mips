; MFC0/MFC2/CFC2 have the same one-instruction delay as memory loads (psx-spx
; "CPU Coprocessor Opcodes", Caution - Load Delay; "GTE Load Delay Slots").
; When the read comes from inline asm, the next compiler-generated instruction
; must not use the result. gas tracks this across the asm boundary and pads
; with a nop when needed. See docs/ps1/hazards.md, H5 and H6.
;
; Status: correct. The read is the asm's hazard, so codegen adds nothing after
; asm (MIC-21). The asm is assembled in reorder mode and the object streamer
; pads it, as gas does (MIC-19, MIC-20): the next instruction gets a nop only
; if it reads the result. See docs/ps1/hazards.md, H9.
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none -filetype=obj \
; RUN:   | llvm-objdump -d --no-show-raw-insn - | FileCheck %s

define i32 @read_sr() {
; CHECK-LABEL: <read_sr>:
; CHECK:       mfc0 $[[R:[0-9]+]], $12
; CHECK-NEXT:  nop
; CHECK-NEXT:  addiu ${{[0-9]+}}, $[[R]], 0x1
  %v = call i32 asm sideeffect "mfc0 $0, $$12", "=r"()
  %a = add i32 %v, 1
  %r = mul i32 %a, %a
  ret i32 %r
}

define i32 @read_gte() {
; CHECK-LABEL: <read_gte>:
; CHECK:       mfc2 $[[R:[0-9]+]], $9
; CHECK-NEXT:  nop
; CHECK-NEXT:  addiu ${{[0-9]+}}, $[[R]], 0x1
  %v = call i32 asm sideeffect "mfc2 $0, $$9", "=r"()
  %a = add i32 %v, 1
  %r = mul i32 %a, %a
  ret i32 %r
}

; The second asm statement takes the first one's output as input: nop.
define i32 @asm_feeds_asm() {
; CHECK-LABEL: <asm_feeds_asm>:
; CHECK:       mfc2 $[[R:[0-9]+]], $9
; CHECK-NEXT:  nop
; CHECK-NEXT:  mtc2 $[[R]], $10
  %v = call i32 asm sideeffect "mfc2 $0, $$9", "=r"()
  call void asm sideeffect "mtc2 $0, $$10", "r"(i32 %v)
  ret i32 0
}

; Independent asm statements, as in psyqo's GTE register writes. Codegen adds
; no nop between them. The asm text is assembled in reorder mode, where gas,
; and since MIC-20 the integrated assembler, put one nop between a coprocessor
; write and the next coprocessor instruction. GCC 16 with gas emits the same.
; MIC-44 checks on hardware whether mtc2 to mtc2 needs it.
define void @asm_independent(i32 %a, i32 %b) {
; CHECK-LABEL: <asm_independent>:
; CHECK:       mtc2 $4, $0
; CHECK-NEXT:  nop
; CHECK-NEXT:  mtc2 $5, $1
  call void asm sideeffect "mtc2 $0, $$0", "r"(i32 %a)
  call void asm sideeffect "mtc2 $0, $$1", "r"(i32 %b)
  ret void
}
