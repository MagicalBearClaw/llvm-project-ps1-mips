# COP0 on the R3000A:
# * mfc0 has a one-instruction load delay (psx-spx "CPU Coprocessor Opcodes").
# * RFE (cop0 command 0x10) pops the SR interrupt/mode stack and is normally
#   placed in the delay slot of `jr $k0` (psx-spx "COP0 - Exception Handling").
# * mtc0 to SR is free of store delays, except that enabling COP2 (SR bit 30)
#   takes about two cycles. Store delays count cycles, not opcodes (psx-spx
#   "Caution - Store Delay"), and code runs from cached RAM, so that is two
#   instructions. gas pads only one; OpenBIOS gets away with one because it
#   runs from uncached ROM. Hardware-faithful output pads two (MIC-18).
# See docs/ps1/hazards.md, H6, H7 and H8.
#
# Status: WRONG in LLVM 22.1.8: `rfe` is not accepted, and no nop is inserted
# after mfc0 or mtc0. MIC-18 fixes this.
# XFAIL: *
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d - | FileCheck %s

        .set reorder
# CHECK:      40026000 mfc0 $2, $12
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 24420001 addiu $2, $2, 0x1
        mfc0    $2, $12
        addiu   $2, $2, 1
# CHECK-NEXT: 40826000 mtc0 $2, $12
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 4a180001
        mtc0    $2, $12
        cop2    0x180001

        .set noreorder
# CHECK-NEXT: 03400008 jr $26
# CHECK-NEXT: 42000010 rfe
        jr      $k0
        rfe
