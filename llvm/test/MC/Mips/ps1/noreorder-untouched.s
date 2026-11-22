# Code inside `.set noreorder` is emitted exactly as written, hazards included.
# The programmer owns it (gas behaves the same). See docs/ps1/hazards.md, H9.
#
# Status: correct. The integrated assembler pads hazards in reorder mode since
# MIC-19 and MIC-20, and never between two noreorder instructions (MIC-21).
# noreorder-boundary-gas-parity.s covers the boundary with reorder code.
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d -z --no-show-raw-insn - | FileCheck %s

        .set noreorder
# Hand-tuned code reads the old value of $t0 in the load delay slot.
# CHECK:      lw $8, 0x0($4)
# CHECK-NEXT: move $9, $8
        lw      $t0, 0($a0)
        addu    $t1, $t0, $zero
# CHECK-NEXT: lw $2, 0x0($4)
# CHECK-NEXT: addiu $2, $2, 0x1
        lw      $2, 0($4)
        addiu   $2, $2, 1
# CHECK-NEXT: mfc0 $3, $12
# CHECK-NEXT: addu $3, $3, $3
        mfc0    $3, $12
        addu    $3, $3, $3
# CHECK-NEXT: mflo $2
# CHECK-NEXT: mult $4, $5
        mflo    $2
        mult    $4, $5
# CHECK-NEXT: beq $4, $5,
# CHECK-NEXT: lw $6, 0x0($4)
        beq     $4, $5, 1f
        lw      $6, 0($4)
1:
# CHECK-NEXT: addu $6, $6, $6
        addu    $6, $6, $6
