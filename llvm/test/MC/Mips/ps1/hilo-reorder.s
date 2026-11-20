# HI/LO hazard in `.set reorder` mode: gas keeps two instructions between an
# mflo/mfhi and the next mult/multu/div/divu/mthi/mtlo. See docs/ps1/hazards.md,
# H4.
#
# Status: correct since MIC-20 (MipsELFStreamer), for MIPS I.
# hilo-cop-gas-parity.s compares a larger corpus with gas byte for byte.
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d -z --no-show-raw-insn - | FileCheck %s

        .set reorder
# CHECK:      mflo $2
# CHECK-NEXT: nop
# CHECK-NEXT: nop
# CHECK-NEXT: mult $4, $5
        mflo    $2
        mult    $4, $5
# CHECK-NEXT: mfhi $3
# CHECK-NEXT: nop
# CHECK-NEXT: nop
# CHECK-NEXT: mthi $4
        mfhi    $3
        mthi    $4
# One unrelated instruction in between: one nop is still needed.
# CHECK-NEXT: mflo $6
# CHECK-NEXT: addu $7, $7, $7
# CHECK-NEXT: nop
# CHECK-NEXT: mtlo $4
        mflo    $6
        addu    $7, $7, $7
        mtlo    $4
