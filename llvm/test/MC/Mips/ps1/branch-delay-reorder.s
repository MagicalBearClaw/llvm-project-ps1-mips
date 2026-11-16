# Branch delay slots (psx-spx "CPU Jump Opcodes": the instruction after a
# branch is always executed). In `.set reorder` mode the assembler fills the
# slot with a nop; in `.set noreorder` mode the slot holds whatever comes next.
# See docs/ps1/hazards.md, H9.
#
# Status: correct in LLVM 22.1.8.
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d --no-show-raw-insn - | FileCheck %s

        .set reorder
# CHECK:      beq $4, $5,
# CHECK-NEXT: nop
# CHECK-NEXT: jal
# CHECK-NEXT: nop
# CHECK-NEXT: jr $ra
# CHECK-NEXT: nop
1:      beq     $4, $5, 1b
        jal     1b
        jr      $ra

        .set noreorder
# CHECK-NEXT: bne $4, $5,
# CHECK-NEXT: addiu $2, $2, 0x1
        bne     $4, $5, 1b
        addiu   $2, $2, 1
