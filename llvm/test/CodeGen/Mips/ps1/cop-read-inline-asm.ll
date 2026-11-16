; MFC0/MFC2/CFC2 have the same one-instruction delay as memory loads (psx-spx
; "CPU Coprocessor Opcodes", Caution - Load Delay; "GTE Load Delay Slots").
; When the read comes from inline asm, the next compiler-generated instruction
; must not use the result. gas tracks this across the asm boundary and pads
; with a nop when needed. See docs/ps1/hazards.md, H5 and H6.
;
; Status: WRONG in LLVM 22.1.8: `mfc0 $1, $12` is followed directly by
; `addiu $1, $1, 1`. MIC-16 (codegen) and MIC-20 (integrated assembler) fix it.
; XFAIL: *
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
