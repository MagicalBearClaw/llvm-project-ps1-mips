; notraps (MIC-14): the CPU cannot execute conditional trap instructions, so the
; divide-by-zero check uses `bnez` + `break 7` even on ISAs that have teq.
; r3000a implies it; Zig's allegrex CPU (mips2 + notraps) needs it on mips2.
;
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips2 -mattr=+notraps \
; RUN:   -relocation-model=static | FileCheck %s --check-prefix=NOTRAPS
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=r3000a \
; RUN:   -relocation-model=static | FileCheck %s --check-prefix=NOTRAPS
; RUN: llc < %s -mtriple=mipsel-unknown-none-elf -mcpu=mips2 \
; RUN:   -relocation-model=static | FileCheck %s --check-prefix=TRAPS

define i32 @sdiv(i32 %a, i32 %b) {
; NOTRAPS-LABEL: sdiv:
; NOTRAPS-NOT:   teq
; NOTRAPS:       bnez $5,
; NOTRAPS:       break 7
; TRAPS-LABEL:   sdiv:
; TRAPS:         teq $5, $zero, 7
  %r = sdiv i32 %a, %b
  ret i32 %r
}
