; Volatile MMIO accesses keep their width. Some IO ports only react to one store
; width, for example the PCSX-Redux exit port 0x1f802082 needs a 16-bit store.
; Also, 8- and 16-bit stores drive all 32 GPR bits onto the bus, so some
; 32-bit IO registers see the whole register (psx-spx "CPU Load/Store
; Opcodes", Caution - 8/16-bit writes). See docs/ps1/hazards.md, H14.
;
; Status: correct in LLVM 22.1.8 for width. MIC-24 audits the upper bits.
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips1 -mattr=+soft-float \
; RUN:   -relocation-model=static -frame-pointer=none | FileCheck %s

define void @exit16() {
; CHECK-LABEL: exit16:
; CHECK:       sh ${{[0-9]+}},
; CHECK-NOT:   sb
; CHECK-NOT:   sw
  store volatile i16 42, ptr inttoptr (i32 528490626 to ptr), align 2
  ret void
}

define i32 @read32() {
; CHECK-LABEL: read32:
; CHECK:       lw ${{[0-9]+}},
; CHECK-NOT:   lhu
  %v = load volatile i32, ptr inttoptr (i32 528486512 to ptr), align 4
  ret i32 %v
}
