# A label that follows a pending load is held back until the next instruction
# shows whether a nop goes before it (MIC-19). It is not defined yet while held
# back, so the streamer reports a second definition itself.
#
# RUN: not llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 \
# RUN:   -filetype=obj -o /dev/null 2>&1 | FileCheck %s

        .set reorder
        lw      $2, 0($4)
# CHECK: :[[#@LINE+2]]:1: error: invalid symbol redefinition
foo:
foo:
        addu    $3, $2, $5
