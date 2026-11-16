# Code inside `.set noreorder` is emitted exactly as written, hazards included.
# The programmer owns it (gas behaves the same). See docs/ps1/hazards.md, H9.
#
# Status: correct in LLVM 22.1.8. MIC-21 keeps it that way once the integrated
# assembler starts inserting hazard nops in reorder mode.
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d --no-show-raw-insn - | FileCheck %s

        .set noreorder
# CHECK:      lw $2, 0x0($4)
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
