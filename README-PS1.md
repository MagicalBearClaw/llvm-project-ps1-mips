# LLVM for the Sony PlayStation (R3000A)

This fork adds PlayStation 1 support to LLVM so that Clang and Zig can build
PS-X executables. The CPU is the LSI CW33300, a MIPS R3000A (MIPS I) core.

* **Base:** `llvmorg-22.1.8` (the LLVM that Zig 0.17.1 pins)
* **Default branch:** `ps1/main`
* **Planning:** [PS1 MIPS Toolchain (LLVM + Zig)](https://linear.app/whilrwind/project/ps1-mips-toolchain-llvm-zig-3ecc49f68e82) on Linear
* **Companion repos:** `MagicalBearClaw/zig-ps1` (Zig fork), `MagicalBearClaw/ps1-toolchain-bench` (test and benchmark harness)

This fork is not upstreamed. It stays a downstream fork.

## Goal

Match the code quality and correctness of the GCC PS1 toolchain. The
reference is [nugget](https://github.com/pcsx-redux/nugget): stock GCC 16.2
and binutils 2.47 targeting `mipsel-none-elf`. Psy-Q (GCC 2.x + ASPSX)
behaviour is opt-in only.

## Target

| Item | Value |
|---|---|
| Triple | `mipsel-sony-psx` (new `psx` OS in `Triple`) |
| Processor | `r3000a` (MIPS I, matches Zig's CPU name) |
| ABI | o32, static, no abicalls, soft-float |
| Divide checks | GCC 16 style `bnez` + `break 7`; ASPSX `break 6` is opt-in |
| Atomics | libcalls that mask interrupts |

## Hardware fidelity

Generated code must behave like real PS1 hardware, quirks included:

* Never assume interlocks. Load delays, HI/LO, COP0 and GTE hazards are
  modelled exactly, in both codegen and the integrated assembler.
* Never touch code inside `.set noreorder`.
* Never "fix" hardware quirks or undefined behaviour away.

## Executables

* Output: ELF, PS-X EXE, CPE and `.bin`, through a converter tool first.
  Native lld PS-X EXE output is a stretch goal.
* Runtime: nugget's crt0 and linker scripts (including `OVERLAY`).
  compiler-rt for C, Zig's `compiler_rt` for Zig.
* Psy-Q `.OBJ`/`.LIB` input via `psyq-obj-parser`.
* GTE (COP2): mnemonics in MC first, `llvm.mips.gte.*` intrinsics later.

## Optimization

Code size and speed within 5% of GCC 16 at `-Os` and `-O2`, measured by
`ps1-toolchain-bench` against a committed baseline.

## Testing

* lit / FileCheck tests for every change, written first (TDD).
* Differential tests: Clang vs GCC output run in PCSX-Redux (headless).
* Four tiers: micro, suites, examples, hazard torture.
* Emulator first, then a burned CD on real hardware.
* Debugging: DWARF through the PCSX-Redux GDB server.

## Workflow

* One Linear ticket per branch and PR. Branches are named `MIC-<n>-<name>`.
* Small, testable changes. No hacks.
* Local builds only (no CI). One worktree per ticket, sccache shared.

Hazard details will live in `docs/ps1/hazards.md` (written in MIC-10).
