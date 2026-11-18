// mipsel-sony-psx / mipsel-unknown-psx (MIC-15): the PlayStation 1. Defaults
// match nugget's GCC flags (common.mk ARCHFLAGS): r3000a, o32, static,
// -mno-abicalls, soft-float, -G0 without gpopt, no frame pointer,
// freestanding. Links with ld.lld, without a default crt0 or libc.

// RUN: %clang -### --target=mipsel-sony-psx -c %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CC1
// RUN: %clang -### --target=mipsel-unknown-psx -c %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=CC1
// CC1:     "-cc1" "-triple" "mipsel-{{sony|unknown}}-psx"
// CC1-DAG: "-mrelocation-model" "static"
// CC1-DAG: "-ffreestanding"
// CC1-DAG: "-mframe-pointer=none"
// CC1-DAG: "-target-cpu" "r3000a"
// CC1-DAG: "-target-feature" "+noabicalls"
// CC1-DAG: "-target-feature" "+soft-float"
// CC1-DAG: "-target-abi" "o32"
// CC1-DAG: "-mfloat-abi" "soft"
// CC1-DAG: "-mllvm" "-mips-ssection-threshold=0"
// CC1-NOT: "-mgpopt"

// Each default can be overridden.
// RUN: %clang -### --target=mipsel-sony-psx -fhosted -fno-omit-frame-pointer \
// RUN:   -G8 -mgpopt -c %s 2>&1 | FileCheck %s --check-prefix=OVERRIDE
// OVERRIDE:     "-cc1"
// OVERRIDE-NOT: "-ffreestanding"
// OVERRIDE-DAG: "-mframe-pointer=all"
// OVERRIDE-DAG: "-mllvm" "-mips-ssection-threshold=8"
// OVERRIDE-DAG: "-mllvm" "-mgpopt"

// RUN: %clang -### --target=mipsel-sony-psx --ld-path=ld.lld %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=LINK
// LINK:     "{{.*}}ld.lld{{(.exe)?}}"
// LINK-SAME: "-Bstatic"
// LINK-SAME: "-m" "elf32ltsmip"
// LINK-NOT: crt0.o
// LINK-NOT: crtbegin
// LINK-NOT: "-lc"

// The data layout is the o32 little-endian one, as in Rust's mipsel_sony_psx.
// RUN: %clang --target=mipsel-sony-psx -S -emit-llvm -o - %s \
// RUN:   | FileCheck %s --check-prefix=DL
// DL: target datalayout = "e-m:m-p:32:32-i8:8:32-i16:16:32-i64:64-n32-S64"
// DL: target triple = "mipsel-sony-psx"

int f(int x) { return x + 1; }
