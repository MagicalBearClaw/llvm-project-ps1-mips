// -mcpu=r3000a / -march=r3000a (MIC-14). The R3000A has no FPU, so the float
// ABI defaults to soft, and -mhard-float is rejected.

// RUN: %clang --target=mipsel-unknown-none-elf -mcpu=r3000a -### -c %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CPU
// RUN: %clang --target=mipsel-unknown-none-elf -march=r3000a -### -c %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CPU
// CPU: "-target-cpu" "r3000a"
// CPU-SAME: "-target-feature" "+soft-float"
// CPU-SAME: "-mfloat-abi" "soft"

// RUN: not %clang --target=mipsel-unknown-none-elf -mcpu=r3000a -mhard-float \
// RUN:   -c %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=HARD
// HARD: error: option '-mhard-float' cannot be specified with 'r3000a'

// RUN: %clang --target=mipsel-unknown-none-elf -mcpu=r3000a -E -dM %s -o - \
// RUN:   | FileCheck %s --check-prefix=MACROS
// MACROS-DAG: #define _MIPS_ARCH "r3000a"
// MACROS-DAG: #define _MIPS_ARCH_R3000A 1
// MACROS-DAG: #define __mips_soft_float 1
// MACROS-NOT: __mips_hard_float
// MACROS-NOT: __GCC_HAVE_SYNC_COMPARE_AND_SWAP
// MACROS-NOT: __mips_isa_rev
