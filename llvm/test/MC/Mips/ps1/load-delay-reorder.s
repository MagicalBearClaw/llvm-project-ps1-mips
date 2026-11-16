# In `.set reorder` mode gas inserts a nop after a load whose result is read by
# the next instruction, for -march=mips1. The integrated assembler should do the
# same. An lwl/lwr pair to the same register needs no nop between them.
# See docs/ps1/hazards.md, H1 and H3.
#
# Status: WRONG in LLVM 22.1.8: the integrated assembler inserts no load-delay
# nops. MIC-19 fixes this.
# XFAIL: *
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d --no-show-raw-insn - | FileCheck %s

        .set reorder
# CHECK:      lw $2, 0x0($4)
# CHECK-NEXT: nop
# CHECK-NEXT: addiu $2, $2, 0x1
        lw      $2, 0($4)
        addiu   $2, $2, 1
# CHECK-NEXT: lb $3, 0x0($4)
# CHECK-NEXT: nop
# CHECK-NEXT: addu $3, $3, $3
        lb      $3, 0($4)
        addu    $3, $3, $3
# CHECK-NEXT: lhu $3, 0x0($4)
# CHECK-NEXT: nop
# CHECK-NEXT: sw $3, 0x0($5)
        lhu     $3, 0($4)
        sw      $3, 0($5)
# No hazard: the next instruction does not read $6.
# CHECK-NEXT: lw $6, 0x0($4)
# CHECK-NEXT: addiu $7, $7, 0x1
        lw      $6, 0($4)
        addiu   $7, $7, 1
# CHECK-NEXT: lwl $5, 0x3($4)
# CHECK-NEXT: lwr $5, 0x0($4)
# CHECK-NEXT: nop
# CHECK-NEXT: addu $5, $5, $5
        lwl     $5, 3($4)
        lwr     $5, 0($4)
        addu    $5, $5, $5
