# GTE (COP2) on the PS1 (psx-spx "GTE Load Delay Slots"):
# * mfc2/cfc2 have a one-instruction load delay into the GPR.
# * Writes to GTE registers (mtc2, ctc2, lwc2) take two cycles before a GTE
#   command or a read sees them. gas pads one nop after mtc2/ctc2 and none after
#   lwc2; psyqo writes `nop; nop` by hand. Hardware-faithful output uses two.
# * cfc2/ctc2 and `cop2 imm25` must assemble.
# See docs/ps1/hazards.md, H5.
#
# Status: WRONG in LLVM 22.1.8: cfc2, ctc2 and `cop2 imm25` are rejected and no
# hazard nops are inserted. MIC-42 adds the instructions; MIC-20 and MIC-44
# add the hazard handling.
# XFAIL: *
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d - | FileCheck %s

        .set reorder
# CHECK:      48024800 mfc2 $2, $9
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 24420001 addiu $2, $2, 0x1
        mfc2    $2, $9
        addiu   $2, $2, 1
# CHECK-NEXT: 4843f800 cfc2 $3, $31
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 00631821 addu $3, $3, $3
        cfc2    $3, $31
        addu    $3, $3, $3
# CHECK-NEXT: 48824800 mtc2 $2, $9
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 4a180001
        mtc2    $2, $9
        cop2    0x180001
# CHECK-NEXT: 48c2f800 ctc2 $2, $31
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 4a180001
        ctc2    $2, $31
        cop2    0x180001
# CHECK-NEXT: c8810000 lwc2 $1, 0x0($4)
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 00000000 nop
# CHECK-NEXT: 4a180001
        lwc2    $1, 0($4)
        cop2    0x180001
