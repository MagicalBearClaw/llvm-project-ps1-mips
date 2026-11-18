# -mcpu=r3000a and `.set arch=r3000a` (MIC-14): MIPS I only. Instructions from
# MIPS II and later are rejected, as on mips1.
#
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=r3000a -show-encoding \
# RUN:   --defsym VALID=1 | FileCheck %s
# RUN: not llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=r3000a \
# RUN:   --defsym INVALID=1 2>&1 | FileCheck %s --check-prefix=ERR
# RUN: not llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips32 \
# RUN:   --defsym SETARCH=1 2>&1 | FileCheck %s --check-prefix=ERR

.ifdef VALID
# CHECK: lw $2, 0($4)       # encoding: [0x00,0x00,0x82,0x8c]
# CHECK: mult $4, $5        # encoding: [0x18,0x00,0x85,0x00]
# CHECK: break 7            # encoding: [0x0d,0x00,0x07,0x00]
# CHECK: mfc2 $2, $1, 0     # encoding: [0x00,0x08,0x02,0x48]
        lw      $2, 0($4)
        mult    $4, $5
        break   7
        mfc2    $2, $1
.endif

.ifdef SETARCH
        .set arch=r3000a
.endif

.ifdef INVALID
.set SETARCH, 1
.endif

.ifdef SETARCH
# ERR: :[[@LINE+1]]:{{[0-9]+}}: error: instruction requires a CPU feature not currently enabled
        teq     $5, $zero, 7
# ERR: :[[@LINE+1]]:{{[0-9]+}}: error: instruction requires a CPU feature not currently enabled
        ll      $2, 0($4)
# ERR: :[[@LINE+1]]:{{[0-9]+}}: error: instruction requires a CPU feature not currently enabled
        sync
# ERR: :[[@LINE+1]]:{{[0-9]+}}: error: instruction requires a CPU feature not currently enabled
        beql    $4, $5, 0
.endif
