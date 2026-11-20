# MIPS I HI/LO and coprocessor-write hazards under `.set reorder`: the
# integrated assembler matches gas byte for byte, including the address of
# every label (MIC-20). See docs/ps1/hazards.md, H4, H5 and H7.
#
# The CHECK lines are the gas output: this file assembled with GNU as 2.47
# (`mipsel-none-elf-as -march=r3000 -EL -O1`) and disassembled with
# llvm-objdump -d -z. See load-delay-gas-parity.s for why -O1.
#
# Left out because other tickets cover them: cfc2, ctc2 and `cop2 imm25`
# (MIC-42), rfe (MIC-18).
#
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=r3000a -filetype=obj \
# RUN:   | llvm-objdump -d -z - | FileCheck %s
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d -z - | FileCheck %s

	.set reorder
# mflo/mfhi: the next two instructions must not write LO/HI.
lo_mult: mflo $2
	mult $4, $5
lo_multu: mflo $2
	addu $9, $9, $9
	multu $4, $5
lo_div:	mflo $2
	div $0, $4, $5
lo_divu: mflo $2
	addu $9, $9, $9
	addu $9, $9, $9
	divu $0, $4, $5
lo_mtlo: mflo $2
	mtlo $4
lo_mthi: mflo $2
	mthi $4
hi_mthi: mfhi $2
	addu $9, $9, $9
	mthi $4
hi_mtlo: mfhi $2
	mtlo $4
	addu $9, $9, $9
hi_mult: mfhi $2
	mult $4, $5
both:	mflo $2
	mfhi $3
	mult $2, $3
# A branch and its delay slot are the two instructions.
lo_br:	mflo $2
	beq $4, $0, lo_br
	mult $4, $5
# mflo/mfhi read GPRs into, so their result has no load delay.
lo_use:	mflo $2
	addu $3, $2, $2
# Coprocessor writes: one nop before the next coprocessor instruction.
c2_c2:	mtc2 $2, $9
	mfc2 $3, $10
c2_c0:	mtc2 $2, $9
	mfc0 $3, $12
c2_mtc2: mtc2 $2, $9
	mtc2 $3, $10
c2_swc2: mtc2 $2, $9
	swc2 $9, 0($4)
c2_lwc2: mtc2 $2, $9
	lwc2 $10, 0($4)
	addu $3, $2, $2
c2_gpr:	mtc2 $2, $9
	addu $3, $2, $2
	mfc2 $3, $10
c0_c2:	mtc0 $2, $12
	mtc2 $3, $9
c0_c0:	mtc0 $2, $12
	mfc0 $3, $12
	addu $3, $3, 1
# Labels: the nops go before the label.
lab_lo:	mflo $2
LL:	mult $4, $5
lab_c2:	mtc2 $2, $9
LC:	mfc2 $3, $10
	addu $3, $3, 1
# Data and section switches pad for the worst case.
dat_lo:	mflo $2
	.word 0x11111111
dat_lo1: mflo $2
	addu $9, $9, $9
	.word 0x22222222
dat_c2:	mtc2 $2, $9
	.word 0x33333333
dat_c21: mtc2 $2, $9
	addu $9, $9, $9
	.word 0x44444444
# Loads and HI/LO together: the larger count wins.
mix:	mflo $2
	lw $3, 0($4)
	mult $3, $5
# End of the file pads after a trailing mfhi.
tail:	mfhi $2

# CHECK:      00000000 <lo_mult>:
# CHECK-NEXT:        0: 12 10 00 00  	mflo	$2
# CHECK-NEXT:        4: 00 00 00 00  	nop
# CHECK-NEXT:        8: 00 00 00 00  	nop
# CHECK-NEXT:        c: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000010 <lo_multu>:
# CHECK-NEXT:       10: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       14: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       18: 00 00 00 00  	nop
# CHECK-NEXT:       1c: 19 00 85 00  	multu	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000020 <lo_div>:
# CHECK-NEXT:       20: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       24: 00 00 00 00  	nop
# CHECK-NEXT:       28: 00 00 00 00  	nop
# CHECK-NEXT:       2c: 1a 00 85 00  	div	$zero, $4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000030 <lo_divu>:
# CHECK-NEXT:       30: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       34: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       38: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       3c: 1b 00 85 00  	divu	$zero, $4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000040 <lo_mtlo>:
# CHECK-NEXT:       40: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       44: 00 00 00 00  	nop
# CHECK-NEXT:       48: 00 00 00 00  	nop
# CHECK-NEXT:       4c: 13 00 80 00  	mtlo	$4
# CHECK-EMPTY:
# CHECK-NEXT: 00000050 <lo_mthi>:
# CHECK-NEXT:       50: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       54: 11 00 80 00  	mthi	$4
# CHECK-EMPTY:
# CHECK-NEXT: 00000058 <hi_mthi>:
# CHECK-NEXT:       58: 10 10 00 00  	mfhi	$2
# CHECK-NEXT:       5c: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       60: 00 00 00 00  	nop
# CHECK-NEXT:       64: 11 00 80 00  	mthi	$4
# CHECK-EMPTY:
# CHECK-NEXT: 00000068 <hi_mtlo>:
# CHECK-NEXT:       68: 10 10 00 00  	mfhi	$2
# CHECK-NEXT:       6c: 13 00 80 00  	mtlo	$4
# CHECK-NEXT:       70: 21 48 29 01  	addu	$9, $9, $9
# CHECK-EMPTY:
# CHECK-NEXT: 00000074 <hi_mult>:
# CHECK-NEXT:       74: 10 10 00 00  	mfhi	$2
# CHECK-NEXT:       78: 00 00 00 00  	nop
# CHECK-NEXT:       7c: 00 00 00 00  	nop
# CHECK-NEXT:       80: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000084 <both>:
# CHECK-NEXT:       84: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       88: 10 18 00 00  	mfhi	$3
# CHECK-NEXT:       8c: 00 00 00 00  	nop
# CHECK-NEXT:       90: 00 00 00 00  	nop
# CHECK-NEXT:       94: 18 00 43 00  	mult	$2, $3
# CHECK-EMPTY:
# CHECK-NEXT: 00000098 <lo_br>:
# CHECK-NEXT:       98: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       9c: fe ff 80 10  	beqz	$4, 0x98
# CHECK-NEXT:       a0: 00 00 00 00  	nop
# CHECK-NEXT:       a4: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 000000a8 <lo_use>:
# CHECK-NEXT:       a8: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       ac: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000b0 <c2_c2>:
# CHECK-NEXT:       b0: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       b4: 00 00 00 00  	nop
# CHECK-NEXT:       b8: 00 50 03 48  	mfc2	$3, $10, 0x0
# CHECK-EMPTY:
# CHECK-NEXT: 000000bc <c2_c0>:
# CHECK-NEXT:       bc: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       c0: 00 00 00 00  	nop
# CHECK-NEXT:       c4: 00 60 03 40  	mfc0	$3, $12, 0x0
# CHECK-EMPTY:
# CHECK-NEXT: 000000c8 <c2_mtc2>:
# CHECK-NEXT:       c8: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       cc: 00 00 00 00  	nop
# CHECK-NEXT:       d0: 00 50 83 48  	mtc2	$3, $10, 0x0
# CHECK-NEXT:       d4: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 000000d8 <c2_swc2>:
# CHECK-NEXT:       d8: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       dc: 00 00 00 00  	nop
# CHECK-NEXT:       e0: 00 00 89 e8  	swc2	$9, 0x0($4)
# CHECK-EMPTY:
# CHECK-NEXT: 000000e4 <c2_lwc2>:
# CHECK-NEXT:       e4: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       e8: 00 00 8a c8  	lwc2	$10, 0x0($4)
# CHECK-NEXT:       ec: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000f0 <c2_gpr>:
# CHECK-NEXT:       f0: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       f4: 21 18 42 00  	addu	$3, $2, $2
# CHECK-NEXT:       f8: 00 50 03 48  	mfc2	$3, $10, 0x0
# CHECK-EMPTY:
# CHECK-NEXT: 000000fc <c0_c2>:
# CHECK-NEXT:       fc: 00 60 82 40  	mtc0	$2, $12, 0x0
# CHECK-NEXT:      100: 00 00 00 00  	nop
# CHECK-NEXT:      104: 00 48 83 48  	mtc2	$3, $9, 0x0
# CHECK-NEXT:      108: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 0000010c <c0_c0>:
# CHECK-NEXT:      10c: 00 60 82 40  	mtc0	$2, $12, 0x0
# CHECK-NEXT:      110: 00 00 00 00  	nop
# CHECK-NEXT:      114: 00 60 03 40  	mfc0	$3, $12, 0x0
# CHECK-NEXT:      118: 00 00 00 00  	nop
# CHECK-NEXT:      11c: 01 00 63 24  	addiu	$3, $3, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000120 <lab_lo>:
# CHECK-NEXT:      120: 12 10 00 00  	mflo	$2
# CHECK-NEXT:      124: 00 00 00 00  	nop
# CHECK-NEXT:      128: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 0000012c <LL>:
# CHECK-NEXT:      12c: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000130 <lab_c2>:
# CHECK-NEXT:      130: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:      134: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 00000138 <LC>:
# CHECK-NEXT:      138: 00 50 03 48  	mfc2	$3, $10, 0x0
# CHECK-NEXT:      13c: 00 00 00 00  	nop
# CHECK-NEXT:      140: 01 00 63 24  	addiu	$3, $3, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000144 <dat_lo>:
# CHECK-NEXT:      144: 12 10 00 00  	mflo	$2
# CHECK-NEXT:      148: 00 00 00 00  	nop
# CHECK-NEXT:      14c: 00 00 00 00  	nop
# CHECK-NEXT:      150: 11 11 11 11  	beq	$8, $17, 0x4598
# CHECK-EMPTY:
# CHECK-NEXT: 00000154 <dat_lo1>:
# CHECK-NEXT:      154: 12 10 00 00  	mflo	$2
# CHECK-NEXT:      158: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:      15c: 00 00 00 00  	nop
# CHECK-NEXT:      160: 22 22 22 22  	addi	$2, $17, 0x2222
# CHECK-EMPTY:
# CHECK-NEXT: 00000164 <dat_c2>:
# CHECK-NEXT:      164: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:      168: 00 00 00 00  	nop
# CHECK-NEXT:      16c: 00 00 00 00  	nop
# CHECK-NEXT:      170: 33 33 33 33  	andi	$19, $25, 0x3333
# CHECK-EMPTY:
# CHECK-NEXT: 00000174 <dat_c21>:
# CHECK-NEXT:      174: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:      178: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:      17c: 00 00 00 00  	nop
# CHECK-NEXT:      180: 44 44 44 44
# CHECK-EMPTY:
# CHECK-NEXT: 00000184 <mix>:
# CHECK-NEXT:      184: 12 10 00 00  	mflo	$2
# CHECK-NEXT:      188: 00 00 83 8c  	lw	$3, 0x0($4)
# CHECK-NEXT:      18c: 00 00 00 00  	nop
# CHECK-NEXT:      190: 18 00 65 00  	mult	$3, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000194 <tail>:
# CHECK-NEXT:      194: 10 10 00 00  	mfhi	$2
# CHECK-NEXT:      198: 00 00 00 00  	nop
# CHECK-NEXT:      19c: 00 00 00 00  	nop
