# R3000A hazard catalogue

Every pipeline hazard and quirk of the PlayStation CPU that a compiler or
assembler must respect, compared across four implementations:

* **Hardware**: what the CPU does, from [psx-spx][spx-cpu] (CPU) and
  [psx-spx GTE][spx-gte].
* **GCC 16**: nugget's GCC 16.2.0 + binutils 2.47 (`mipsel-none-elf`,
  `-march=mips1`). "gas" means the GNU assembler in `.set reorder` mode.
* **ASPSX**: the Psy-Q assembler, as reimplemented by [maspsx][maspsx].
* **LLVM 22.1.8**: this fork's base, before any PS1 changes. Codegen is
  `llc -mcpu=mips1`; "IAS" is the integrated assembler (`llvm-mc`).

The rule for this fork is to be hardware-faithful: never assume interlocks the
CPU does not have, never touch `.set noreorder` code, and never fix hardware
quirks away. When GCC and the hardware documentation disagree, the hardware wins
and the difference is recorded here.

Each row links a lit test under `llvm/test/CodeGen/Mips/ps1/` or
`llvm/test/MC/Mips/ps1/`. The test checks the **correct** output. Where LLVM
22.1.8 is wrong or suboptimal, the test is marked `XFAIL: *` and names the
ticket that fixes it. The fix removes the `XFAIL` line.

## Summary

| # | Hazard | LLVM codegen | LLVM IAS | Fix |
|---|---|---|---|---|
| H1 | GPR load delay (lb/lbu/lh/lhu/lw) | correct | correct (MIC-19) | none |
| H2 | Load delay across branches, calls, returns | correct (MIC-17) | n/a | none |
| H3 | lwl/lwr pair | suboptimal | correct (MIC-19) | MIC-55 |
| H4 | HI/LO (mflo/mfhi then mult/div/mthi/mtlo) | correct | **wrong** | MIC-20 |
| H5 | GTE: mfc2/cfc2 delay, mtc2/ctc2/lwc2 write latency, missing opcodes | mfc2 delay correct (MIC-16); rest **wrong** | **wrong** | MIC-42, MIC-20, MIC-44 |
| H6 | COP0 read delay (mfc0) | correct (MIC-16) | correct (MIC-19) | MIC-18 |
| H7 | COP0 write latency (SR, COP2 enable): pad 2 | n/a | **wrong** | MIC-18 |
| H8 | `rfe` | n/a | **wrong** (missing) | MIC-18 |
| H9 | Branch delay slots, `.set noreorder` | correct | correct | MIC-21 (guard) |
| H10 | Interrupt during a load delay | correct | correct | none |
| H11 | Unaligned access | correct | correct | none |
| H12 | Divide by zero | correct (MIC-11) | n/a | MIC-22 |
| H13 | Divide overflow, add overflow | correct | n/a | none (opt-in MIC-61) |
| H14 | MMIO store width | correct | n/a | MIC-24 (upper bits) |
| H15 | DMA buffer ordering (plain stores before the MMIO start) | correct (with a barrier) | n/a | none (MIC-12 tests) |
| H16 | Instruction cache after loading code | n/a (runtime) | n/a | MIC-30 (`__clear_cache`) |

## H1. GPR load delay

* **Hardware.** "The loaded data is NOT available to the next opcode, ie. the
  target register isn't updated until the next opcode has completed. So, if
  the next opcode tries to read from the load destination register, then it
  would (usually) receive the OLD value of that register" ([psx-spx, Load/Store
  Opcodes][spx-cpu]). Applies to `lb lbu lh lhu lw lwl lwr`. No interlock.
* **GCC 16.** Schedules around it and fills the slot, often with the `jr $ra`:
  `lw $2,0($4); jr $31; addiu $2,$2,1`.
* **gas.** In reorder mode it inserts a `nop` when the next instruction reads
  the register, and only then.
* **ASPSX.** Inserts a `nop` when the next instruction reads the register
  (`_handle_nop_before_next_instruction`).
* **LLVM codegen: correct.** `MipsBranchExpansion::handleLoadDelaySlot` inserts
  a `nop` when the next instruction, looking through fall-through blocks,
  reads the loaded register. `HasLoadDelaySlot` covers LB, LBu, LH, LHu, LW,
  LWL and LWR. It does **not** cover LWC1, LWC2, MFC0, MFC2 or CFC2 (see H5, H6).
* **gas details** (binutils 2.47, measured for MIC-19):
  * A store, a base register and a branch operand all count as reads.
  * `lwl`/`lwr` never wait for a load to their own destination, which they
    merge into: `lw $2; lwl $2,3($4)` gets no `nop`. Only their base
    register counts.
  * With a label in between, the `nop` goes before the label, and only if
    the instruction after the label reads the register.
  * Directives that emit nothing (`.globl`, `.type`, `.loc`, `.size`,
    `.set at`, `.set push`/`pop`, `.set noreorder`) change nothing; the
    first instruction after `.set noreorder` is still checked.
  * Data, `.space`, alignment and a section switch, even to the same
    section, get a `nop` first, since the next instruction is unknown. So
    does the end of the file.
* **LLVM IAS: correct (MIC-19).** `MipsELFStreamer` pads like gas, for
  instructions the parser emits in reorder mode on MIPS I. That includes
  inline asm, which is assembled in reorder mode, as GCC does. It holds a
  label back while a load is pending, so the `nop` goes before it.
  `load-delay-gas-parity.s` matches `as -march=r3000 -O1` byte for byte. Only
  object output pads; assembly output keeps the text inside `.set reorder`,
  for the next assembler to pad.
* Tests: [load-delay-gpr.ll](../../llvm/test/CodeGen/Mips/ps1/load-delay-gpr.ll),
  [load-delay-reorder.s](../../llvm/test/MC/Mips/ps1/load-delay-reorder.s),
  [load-delay-gas-parity.s](../../llvm/test/MC/Mips/ps1/load-delay-gas-parity.s),
  [load-delay-label-redef.s](../../llvm/test/MC/Mips/ps1/load-delay-label-redef.s),
  [inline-asm-load-delay.ll](../../llvm/test/CodeGen/Mips/ps1/inline-asm-load-delay.ll).

## H2. Load delay across control flow

* **Hardware.** A load in a branch delay slot is still pending when the first
  instruction at the target executes. A load in the delay slot of `jal` or
  `jr $ra` is pending at the callee's or the caller's next instruction.
* **GCC 16.** Never puts a load whose result is live in a return or call delay
  slot: `lw $2,0($4); jr $31; nop`.
* **ASPSX.** Same rule as H1; looks across labels.
* **The rule.** The instruction after a load is decided by execution order.
  A block that falls through continues with the first real instruction of
  the next block, and that instruction is checked like any other; a label in
  between changes nothing, because a branch to the label does not run the
  load. A load in a branch delay slot is checked against the first real
  instruction of both successors. Where the next instruction is unknown (the
  slot of a call, a return or an indirect branch, or the end of the
  function), the register is assumed to be read. GCC 16 with gas applies the
  same rule: `lw $2; $L7: addiu $5,$5,-1` gets no nop.
* **LLVM codegen: correct (MIC-17).**
  `MipsDelaySlotFiller::delayHasHazard` refuses loads in the slot of calls,
  returns and indirect branches, and checks the first instruction of both
  successors of a conditional branch. `getNextMachineInstr` in
  `MipsBranchExpansion` follows fall-through successors and assumes a hazard
  otherwise. MIC-17 fixed the filler reading a successor's first
  MachineInstr: with `-g` a `DBG_VALUE` there hid the real use, so a load
  could sit in a `j` slot right before an instruction reading it. It also
  cost a nop when the `DBG_VALUE` was at the fall-through block. The filler
  now looks past instructions that emit no code and follows empty blocks.
* **Remaining differences from GCC.** Inline asm at the start of the next
  block gets a nop (H5); gas reads the asm text and may not. The hazard pass
  in `MipsBranchExpansion` does not re-check a load already in a delay slot,
  so the filler is the only guard there.
* Tests: [hazards-across-blocks.ll](../../llvm/test/CodeGen/Mips/ps1/hazards-across-blocks.ll),
  [load-delay-slot-debug.mir](../../llvm/test/CodeGen/Mips/ps1/load-delay-slot-debug.mir),
  [load-delay-control-flow.ll](../../llvm/test/CodeGen/Mips/ps1/load-delay-control-flow.ll).

## H3. lwl/lwr pair

* **Hardware.** `lwl` and `lwr` to the same register merge their halves
  ([psx-spx, Unaligned Load/Store][spx-cpu]). An `lwl`/`lwr` in the delay slot
  of a load to the same register merges with the value still in flight, so
  the pair needs no `nop` between them. psx-spx does not say this directly;
  PCSX-Redux models it in `InterpretedCPU::mergeUnalignedLoad`. The
  instruction after the pair still sees the load delay.
* **GCC 16.** Codegen emits `lwl $2,4($4); nop; lwr $2,1($4)`, the same as
  LLVM.
* **gas.** In reorder mode it emits `lwl; lwr; nop; use`, with no `nop`
  between the pair.
* **ASPSX.** Treats `lwl`/`lwr` as loads, with the same rule as H1.
* **LLVM codegen: suboptimal.** Always inserts a `nop` between `lwl` and `lwr`,
  because `SafeInLoadDelaySlot` sees the tied source operand as a read.
  Correct, and equal to GCC, but one wasted cycle and four bytes per unaligned
  access. MIC-55 can beat GCC here.
* **LLVM IAS: correct (MIC-19).** `lwl; lwr; nop; use`, as gas. Like gas,
  `lwl`/`lwr` also follow any load to the same register without a `nop`;
  codegen could do the same (MIC-55).
* Tests: [load-delay-lwl-lwr.ll](../../llvm/test/CodeGen/Mips/ps1/load-delay-lwl-lwr.ll)
  (XFAIL, MIC-55), [load-delay-reorder.s](../../llvm/test/MC/Mips/ps1/load-delay-reorder.s).

## H4. HI/LO hazard

* **Hardware.** Reading HI/LO while `mult`/`div` is busy stalls the CPU (this
  is interlocked) ([psx-spx, Multiply/Divide][spx-cpu]). Separately, on the
  R3000 family an `mflo`/`mfhi` followed within two instructions by an
  instruction that writes HI/LO (`mult multu div divu mthi mtlo`) corrupts the
  read. psx-spx does not describe this; the MIPS R3000 architecture rule and
  gas's `mips_hazards` do.
* **GCC 16 / gas.** Two instructions between them: `mflo $2; nop; nop; div`.
  gas pads `mflo; mult` and `mfhi; mthi` with two `nop`s.
* **ASPSX.** Two `nop`s (`_handle_mflo_mfhi`, `nop_mflo_mfhi=True`).
* **LLVM codegen: correct.** `MipsBranchExpansion::handleMFLO` keeps two
  instructions before a mult/div. Upstream walked whole bundles and missed a
  mult/div in a branch delay slot; the #201133 backport puts `div` there, so
  MIC-11 made it look inside bundles (`mflo; nop; bnez; div`).
  `SafeAfterMflo` only checks `IsDIVMULT`, so `mthi`/`mtlo` are not covered.
  Codegen does not emit those today; MIC-20 covers it.
  Across blocks: the lookahead follows fall-through, so `mflo` ending a block
  gets two `nop`s before a `mult` at the next block. A taken branch needs
  none, because the branch and its delay slot are the two instructions and
  the filler never puts `mflo`/`mfhi` in a delay slot (MIC-17).
* **LLVM IAS: wrong.** Emits `mflo; mult` as written in reorder mode.
* Tests: [hilo-hazard.ll](../../llvm/test/CodeGen/Mips/ps1/hilo-hazard.ll),
  [hazards-across-blocks.ll](../../llvm/test/CodeGen/Mips/ps1/hazards-across-blocks.ll),
  [hilo-reorder.s](../../llvm/test/MC/Mips/ps1/hilo-reorder.s) (XFAIL, MIC-20).

## H5. GTE (COP2)

* **Hardware.** ([psx-spx GTE Load Delay Slots][spx-gte].)
  * `mfc2`/`cfc2` have a one-instruction delay into the GPR, like a memory
    load. "Certain games are sensitive to this, with the notable example of
    Tekken 2."
  * Writes to GTE registers (`mtc2`, `ctc2`, `lwc2`) take two cycles before a
    GTE command or read sees them, and three for IRGB.
  * GTE commands are `cop2 imm25`. A command that reads a register while the
    previous command is still running stalls (interlocked).
  * Do not put GTE instructions in branch delay slots.
* **GCC 16.** Never generates COP2 instructions. psyqo uses raw `cop2 0x...`
  in inline asm with hand-written `nop; nop`.
* **gas.** Pads `mfc2`/`cfc2` reads with one `nop`, and pads `mtc2` and `ctc2`
  before a dependent COP2 instruction with one `nop`. It pads nothing after
  `lwc2`. Assembles `cfc2`, `ctc2` and `cop2 imm25` (shown as `c2`).
* **ASPSX.** Treats `lwc2` as a load from its base register only.
* **LLVM: wrong.**
  * IAS rejects `cfc2`/`ctc2` on mips1 ("requires a CPU feature") and does not
    know `cop2 imm25`.
  * Codegen: the `mfc2` read delay is handled since MIC-16, including after
    inline asm. `cfc2` joins it once MIC-42 adds the instruction.
  * IAS: the `mfc2` read delay is handled since MIC-19, as gas. Like gas, a
    read of a GTE register right after `lwc2` to it is not padded; MIC-44
    checks that on hardware.
  * No write-latency handling anywhere.
  * Hardware-faithful output pads two `nop`s after `mtc2`/`ctc2`/`lwc2` before
    a dependent GTE command, which is one more than gas.
* Tests: [cop2-gte-hazards.s](../../llvm/test/MC/Mips/ps1/cop2-gte-hazards.s)
  (XFAIL, MIC-42/MIC-20/MIC-44),
  [cop-read-inline-asm.ll](../../llvm/test/CodeGen/Mips/ps1/cop-read-inline-asm.ll),
  [cop-read-delay.mir](../../llvm/test/CodeGen/Mips/ps1/cop-read-delay.mir).
* Note: `cop2-gte-hazards.s` currently fails at assembly. After MIC-42 it will
  still fail, on the missing `nop`s, until MIC-20/MIC-44 land.

## H6. COP0 read delay

* **Hardware.** "When reading from a coprocessor register, the next opcode
  cannot use the destination register" ([psx-spx, Coprocessor
  Opcodes][spx-cpu]). psx-spx notes reports of a two-instruction delay but
  measured one.
* **GCC 16.** Never generates `mfc0`; it comes from inline asm. gas tracks the
  pending read across the `#APP`/`#NO_APP` boundary into the following
  `.set noreorder` code and pads with a `nop` only if the next instruction
  reads the register.
* **LLVM codegen: correct since MIC-16.** `MFC0` and `MFC2` are in
  `HasLoadDelaySlot`. Inline asm is opaque, so its outputs are treated like
  loaded registers: the next instruction gets a `nop` only if it reads one,
  which is what gas does across `#APP`. Between two asm blocks the operands
  decide, so independent GTE asm statements get no `nop`. LLVM 22.1.8 emitted
  inline-asm `mfc0 $1, $12` followed directly by `addiu $1, $1, 1`.
* **LLVM IAS: correct (MIC-19).** One `nop` after `mfc0` in reorder mode when
  the next instruction reads the register, as gas.
* Side note: LLVM picks `$at` for the `=r` asm output and warns "used $at
  without .set noat". GCC picks `$2`. A macro in the asm text that expands
  through `$at` would corrupt the operand. MIC-132 fixes it.
* Tests: [cop-read-inline-asm.ll](../../llvm/test/CodeGen/Mips/ps1/cop-read-inline-asm.ll),
  [cop-read-delay.mir](../../llvm/test/CodeGen/Mips/ps1/cop-read-delay.mir),
  [cop-read-delay-slot.mir](../../llvm/test/CodeGen/Mips/ps1/cop-read-delay-slot.mir),
  [cop0-hazards.s](../../llvm/test/MC/Mips/ps1/cop0-hazards.s)
  (XFAIL, MIC-18).

## H7. COP0 write latency

* **Hardware.** "COP0 is more or less free of store delays (eg. one can read
  from a cop0 register immediately after writing to it), the only known
  exception is the cop2 enable bit in cop0r12.bit30 (setting that cop0 bit
  acts delayed, and cop2 isn't actually enabled until after 2 clock cycles or
  so)" ([psx-spx][spx-cpu]).
* **gas.** Pads `mtc0` before a COP2 instruction with one `nop`. That is gas's
  generic R3000 coprocessor-write rule, not PS1-specific.
* **OpenBIOS.** Enables COP2 at boot with `mtc0 $t0, $12; nop`. One `nop` is
  enough there because the BIOS runs from uncached ROM, and "store delays are
  counted in numbers of clock cycles (not in numbers of opcodes). For 3 cycle
  delay, one must usually insert 3 cached opcodes (or one uncached opcode)"
  ([psx-spx, Store Delay][spx-cpu]).
* **Games.** No known code relies on the delay. The only effect of issuing a
  COP2 instruction too early is that it runs while COP2 is still disabled.
  The retail BIOS shell and OpenBIOS both leave COP2 enabled before user code
  runs.
* **LLVM IAS: wrong.** Pads nothing.
* **Decision (MIC-18): pad two instructions** between `mtc0 $x, $12` and the
  next COP2 instruction in reorder mode. Compiled code runs from cached RAM,
  where two cycles means two instructions. PCSX-Redux does not emulate this
  delay, so MIC-40 (real hardware) confirms the count.
* Tests: [cop0-hazards.s](../../llvm/test/MC/Mips/ps1/cop0-hazards.s) (XFAIL,
  MIC-18).

## H8. `rfe`

* **Hardware.** COP0 command 0x10 (`0x42000010`). It pops the SR KU/IE stack
  (bits 2-3 to 0-1, 4-5 to 2-3) and does not jump. The handler returns with
  `jr $k0` and puts `rfe` in its delay slot ([psx-spx, RFE][spx-cpu]).
* **gas.** Assembles `rfe` for `-march=mips1`.
* **LLVM IAS: wrong.** "unknown instruction".
* Tests: [cop0-hazards.s](../../llvm/test/MC/Mips/ps1/cop0-hazards.s) (XFAIL,
  MIC-18).

## H9. Branch delay slots and `.set noreorder`

* **Hardware.** "The instruction following the branch will always be executed"
  ([psx-spx, Jump Opcodes][spx-cpu]). There are no likely-branches (MIPS II).
* **gas.** In reorder mode it fills or pads the slot. In noreorder mode it
  emits exactly what is written.
* **LLVM: correct.** The IAS pads branch slots with `nop` in reorder mode and
  leaves noreorder code untouched, hazards included. MIC-19 and MIC-20 add
  hazard `nop`s in reorder mode only; MIC-21 keeps noreorder untouched.
* Tests: [branch-delay-reorder.s](../../llvm/test/MC/Mips/ps1/branch-delay-reorder.s),
  [noreorder-untouched.s](../../llvm/test/MC/Mips/ps1/noreorder-untouched.s).

## H10. Interrupt during a load delay

* **Hardware.** If an IRQ is taken between a load and the next instruction,
  the load completes during the handler. The next instruction then sees the
  **new** value instead of the old one ([psx-spx, Load Delay][spx-cpu]).
  PCSX-Redux emulates this (`m_delayedLoadInfo`).
* **Compiler impact.** Code that reads the register in the delay slot behaves
  differently depending on interrupt timing, so it is unsafe. Compilers must
  never rely on the old-value behaviour. That is guaranteed by the H1 rule:
  the next instruction never reads the register.
* **LLVM: correct**, through H1. Hand-written `.set noreorder` code that
  depends on the old value is the programmer's choice and is left alone (H9).
* Tests: the H1 and H2 tests.

## H11. Unaligned access

* **Hardware.** A misaligned `lh/lhu/lw/sh/sw` raises an address error
  (AdEL/AdES) and sets BadVaddr ([psx-spx, COP0 Exception Handling][spx-cpu]).
  `lwl/lwr/swl/swr` handle unaligned words.
* **LLVM: correct.** `align 1` and `align 2` i32 accesses use
  `lwl/lwr`/`swl/swr`; `align 1` i16 uses two `lbu`.
* Tests: [unaligned-access.ll](../../llvm/test/CodeGen/Mips/ps1/unaligned-access.ll).

## H12. Divide by zero

* **Hardware.** No exception. `div` by zero gives LO=-1 or +1 and HI=Rs;
  `divu` gives LO=0xFFFFFFFF and HI=Rs ([psx-spx, Multiply/Divide][spx-cpu]).
  There are no trap instructions: `teq` is MIPS II and raises a Reserved
  Instruction exception on the R3000A.
* **GCC 16.** `bne $rt,$0,1f; div $0,$rs,$rt` (in the delay slot); `break 7;
  1: mflo`. `-mno-check-zero-division` removes the check.
* **ASPSX.** `bnez $rt; nop; break 7` after the `div`.
* **LLVM: correct since MIC-11** (backport of llvm/llvm-project#201133). It
  emits GCC's sequence. LLVM 22.1.8 emitted `div $zero,$4,$5; teq
  $5,$zero,7`, which the CPU cannot execute; `llvm-mc` rejects `teq` on mips1,
  but codegen encoded it straight into objects. The opt-in ASPSX `break 6`
  overflow check is MIC-22.
* Tests: [div-zero-check.ll](../../llvm/test/CodeGen/Mips/ps1/div-zero-check.ll),
  [div-no-trap-mips1.ll](../../llvm/test/CodeGen/Mips/ps1/div-no-trap-mips1.ll).

## H13. Divide overflow and add overflow

* **Hardware.** `div 0x80000000, -1` gives LO=0x80000000, HI=0, and no
  exception. `add`/`addi`/`sub` trap on signed overflow; the `u` forms do not.
* **GCC 16.** No overflow check on `div`. Uses `addu`/`addiu`.
* **ASPSX.** Adds an INT_MIN/-1 check ending in `break 6`. This is opt-in here
  (MIC-61, `-mpsyq-compat`).
* **LLVM: correct.** No overflow check; `add nsw` becomes `addu`/`addiu`.
* Tests: [div-overflow-and-add.ll](../../llvm/test/CodeGen/Mips/ps1/div-overflow-and-add.ll).

## H14. MMIO store width

* **Hardware.** Some IO ports only react to a specific width. For example, the
  PCSX-Redux exit port `0x1f802082` needs a 16-bit `sh`; `sb` does nothing.
  Also, "during an 8-bit or 16-bit store, all 32 bits of the GPR are placed on
  the bus", so some 32-bit IO registers see the whole register ([psx-spx,
  Load/Store Opcodes][spx-cpu]).
* **LLVM: correct** for width: a volatile i16 store is one `sh`. MIC-24 checks
  whether the upper GPR bits on narrow stores match GCC.
* Tests: [mmio-store-width.ll](../../llvm/test/CodeGen/Mips/ps1/mmio-store-width.ll).

## H15. DMA buffer ordering

* **Hardware.** There is no data cache (the 1 KiB scratchpad is separate RAM),
  and CPU writes leave through a FIFO write queue. Packet data stored to RAM
  therefore reaches memory before a later store to a DMA channel's CHCR starts
  the transfer, and no barrier instruction is needed. MIPS I has none anyway
  (`sync` is MIPS II).
* **Compiler.** `volatile` only orders volatile accesses against each other.
  The buffer stores are plain stores, so the compiler may move them after the
  volatile CHCR store or delete them: at `-O2`, a packet store followed by a
  DMA start and a reuse of the buffer is removed as dead. Code that starts DMA
  needs a compiler barrier between building the buffer and the MMIO store:
  `atomic_thread_fence(memory_order_release)`, `atomic_signal_fence(...)` or
  `asm volatile("" ::: "memory")`. On the read side, an acquire fence after
  polling for completion makes the buffer be read again.
* **LLVM: correct, given a barrier.** Since the #190129 backport (MIC-12), a
  fence on mips1 is a compiler barrier that emits no instruction. Before it,
  llc crashed on any fence for mips1.
* **Not covered by a fence.** Waiting for the device: poll the CHCR busy bit
  (bit 24) before reusing a buffer, and GPUSTAT's ready bits before sending
  more GPU commands. When a write to an MMIO register takes effect: because of
  the write queue, a store such as an I_STAT acknowledge can land after later
  instructions have run. Whether a following load waits for the queue to drain
  is not verified; MIC-40 checks it on hardware.
* Tests: [dma-barrier-opt.ll](../../llvm/test/CodeGen/Mips/ps1/dma-barrier-opt.ll),
  [fence-mips1.ll](../../llvm/test/CodeGen/Mips/ps1/fence-mips1.ll).

## H16. Instruction cache after loading code

* **Hardware.** The R3000A has a 4 KiB instruction cache that is not kept
  coherent with memory. Code written to RAM by DMA (a CD-ROM read of an
  overlay) or by CPU stores (a decompressor, self-modifying code) can be
  shadowed by stale cache lines until the cache is flushed. The BIOS provides
  `FlushCache`, A(44h). Data accesses are uncached anyway, so uncached KSEG1
  addresses do not matter for data, only for running code without the cache.
* **Compiler.** Nothing in codegen. `__builtin___clear_cache(begin, end)`
  lowers to a call to `__clear_cache`, as with GCC.
* **compiler-rt: wrong for the PS1.** The generic MIPS `__clear_cache` starts
  with `rdhwr` (MIPS32r2), which raises a Reserved Instruction exception on the
  R3000A. The psx builtins (MIC-30) need a `__clear_cache` that calls BIOS
  `FlushCache`, and overlay loaders must call it after loading code.
* Tests: none yet; MIC-30 adds one with its runtime tests.

## Other differences found during the audit

These are not hazards. They feed the optimization milestone.

* Clang keeps a frame pointer for `mipsel-none-elf` at `-O2`, so every function
  gets a 4-instruction prologue and epilogue that GCC does not emit. This needs
  `-fomit-frame-pointer` as the psx default (MIC-15).
* No sibling-call optimization: `return ext(*p)` is `jal ext` plus an epilogue
  in clang, but `j ext` in GCC (MIC-57).
* Clang warns "MIPS-I support is experimental".

## How the numbers were obtained

```powershell
clang --target=mipsel-none-elf -march=mips1 -mabi=32 -msoft-float -fno-pic -mno-abicalls -G0 -O2 -S
mipsel-none-elf-gcc -march=mips1 -mabi=32 -EL -fno-pic -mno-shared -mno-abicalls -mfp32 -mno-llsc -mno-gpopt -G0 -O2 -S
llvm-mc -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj   # vs mipsel-none-elf-as -march=mips1
```

To see why an XFAIL test fails, set `LIT_XFAIL_NOT="LLVM :: <path>"` and run
`llvm-lit -v` on it.

[spx-cpu]: https://psx-spx.consoledev.net/cpuspecifications/
[spx-gte]: https://psx-spx.consoledev.net/geometrytransformationenginegte/
[maspsx]: https://github.com/mkst/maspsx
