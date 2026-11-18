// Predefined macros for the PlayStation 1 (MIC-15). __psx__ comes from the
// psx OS. The r3000a CPU defines __R3000A__ plus the macros GCC defines for
// -march=mips1 (an R3000): __R3000, __R3000__, _R3000, R3000 (GNU modes), and
// __mips 1 / _MIPS_ISA _MIPS_ISA_MIPS1.

// RUN: %clang --target=mipsel-sony-psx -E -dM %s -o - \
// RUN:   | FileCheck %s --check-prefixes=CHECK,PSX \
// RUN:       --implicit-check-not=__mips_hard_float \
// RUN:       --implicit-check-not=__mips_isa_rev \
// RUN:       --implicit-check-not=__mips_abicalls
// RUN: %clang --target=mipsel-unknown-none-elf -mcpu=r3000a -E -dM %s -o - \
// RUN:   | FileCheck %s --check-prefix=CHECK --implicit-check-not=__psx__
// RUN: %clang --target=mipsel-sony-psx -std=c11 -E -dM %s -o - \
// RUN:   | FileCheck %s --check-prefix=STRICT \
// RUN:       --implicit-check-not="#define R3000 1"

// PSX-DAG:   #define __psx__ 1
// PSX-DAG:   #define __STDC_HOSTED__ 0
// CHECK-DAG: #define __R3000A__ 1
// CHECK-DAG: #define __R3000 1
// CHECK-DAG: #define __R3000__ 1
// CHECK-DAG: #define _R3000 1
// CHECK-DAG: #define R3000 1
// CHECK-DAG: #define __mips 1
// CHECK-DAG: #define _MIPS_ISA _MIPS_ISA_MIPS1
// CHECK-DAG: #define _MIPS_ARCH "r3000a"
// CHECK-DAG: #define __mips_soft_float 1

// STRICT: #define __R3000__ 1
