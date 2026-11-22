# Code inside `.set noreorder` is never changed: a hazard between two
# noreorder instructions is the programmer's, which lets hand-tuned code read
# a register's old value in a load delay slot. A hazard with a reorder
# instruction on one side is padded, as gas does. When the consumer is
# noreorder code, the nops go before all of it, never inside it or between
# a branch and its delay slot (MIC-21). See docs/ps1/hazards.md, H9.
#
# The CHECK lines are the gas output: this file assembled with GNU as 2.47
# (`mipsel-none-elf-as -march=r3000 -EL -O1`) and disassembled with
# llvm-objdump -d -z. See load-delay-gas-parity.s for why -O1.
#
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=r3000a -filetype=obj \
# RUN:   | llvm-objdump -d -z - | FileCheck %s

	.set reorder
# A noreorder instruction pair is never padded, whatever it does.
	.set noreorder
old:	lw $8, 0($4)
	addu $9, $8, $0
	mflo $10
	mult $4, $5
	mtc2 $2, $9
	mfc2 $3, $10
	lw $11, 0($4)
	.word 0x11111111
	.set reorder
# A reorder source reaching into noreorder code: the nops go at the start
# of the noreorder code, never between two noreorder instructions.
r2n:	mflo $2
	.set noreorder
	mult $4, $5
	.set reorder
r2n1:	mflo $2
	.set noreorder
	addu $9, $9, $9
	mult $4, $5
	.set reorder
r2nbr:	mflo $2
	.set noreorder
	bnez $4, r2nbr
	mult $4, $5
	.set reorder
r2nbr2:	mflo $2
	.set noreorder
	bnez $4, r2nbr
	addu $9, $9, $9
	mult $4, $5
	.set reorder
r2nld:	lw $2, 0($4)
	.set noreorder
	bnez $2, r2nld
	addu $3, $2, $2
	.set reorder
r2ncop:	mtc2 $2, $9
	.set noreorder
	bnez $4, r2ncop
	mfc2 $3, $9
	.set reorder
r2nlab:	mflo $2
	.set noreorder
L1:	addu $9, $9, $9
	mult $4, $5
	.set reorder
r2nslot: mflo $2
	.set noreorder
	bnez $4, r2nslot
L2:	mult $4, $5
	.set reorder
r2ndat:	mflo $2
	.set noreorder
	addu $9, $9, $9
	.word 0x22222222
	.set reorder
r2nok:	lw $2, 0($4)
	.set noreorder
	addu $9, $9, $9
	addu $3, $2, $2
	.set reorder
# A noreorder source reaching reorder code is padded there.
n2r:	.set noreorder
	lw $2, 0($4)
	.set reorder
	addu $3, $2, $2
n2rhl:	.set noreorder
	mflo $2
	addu $9, $9, $9
	.set reorder
	mult $4, $5
n2rlab:	.set noreorder
	lw $2, 0($4)
L3:	.set reorder
	addu $3, $2, $2
n2rok:	.set noreorder
	lw $2, 0($4)
	bnez $4, n2rok
	.set reorder
	addu $3, $2, $2
tail:	addu $9, $9, $9

# CHECK:      00000000 <old>:
# CHECK-NEXT:        0: 00 00 88 8c  	lw	$8, 0x0($4)
# CHECK-NEXT:        4: 21 48 00 01  	move	$9, $8
# CHECK-NEXT:        8: 12 50 00 00  	mflo	$10
# CHECK-NEXT:        c: 18 00 85 00  	mult	$4, $5
# CHECK-NEXT:       10: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       14: 00 50 03 48  	mfc2	$3, $10, 0x0
# CHECK-NEXT:       18: 00 00 8b 8c  	lw	$11, 0x0($4)
# CHECK-NEXT:       1c: 11 11 11 11  	beq	$8, $17, 0x4464
# CHECK-EMPTY:
# CHECK-NEXT: 00000020 <r2n>:
# CHECK-NEXT:       20: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       24: 00 00 00 00  	nop
# CHECK-NEXT:       28: 00 00 00 00  	nop
# CHECK-NEXT:       2c: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000030 <r2n1>:
# CHECK-NEXT:       30: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       34: 00 00 00 00  	nop
# CHECK-NEXT:       38: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       3c: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000040 <r2nbr>:
# CHECK-NEXT:       40: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       44: 00 00 00 00  	nop
# CHECK-NEXT:       48: fd ff 80 14  	bnez	$4, 0x40
# CHECK-NEXT:       4c: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000050 <r2nbr2>:
# CHECK-NEXT:       50: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       54: fa ff 80 14  	bnez	$4, 0x40
# CHECK-NEXT:       58: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       5c: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000060 <r2nld>:
# CHECK-NEXT:       60: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       64: 00 00 00 00  	nop
# CHECK-NEXT:       68: fd ff 40 14  	bnez	$2, 0x60
# CHECK-NEXT:       6c: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 00000070 <r2ncop>:
# CHECK-NEXT:       70: 00 48 82 48  	mtc2	$2, $9, 0x0
# CHECK-NEXT:       74: fe ff 80 14  	bnez	$4, 0x70
# CHECK-NEXT:       78: 00 48 03 48  	mfc2	$3, $9, 0x0
# CHECK-EMPTY:
# CHECK-NEXT: 0000007c <r2nlab>:
# CHECK-NEXT:       7c: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       80: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 00000084 <L1>:
# CHECK-NEXT:       84: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       88: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 0000008c <r2nslot>:
# CHECK-NEXT:       8c: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       90: 00 00 00 00  	nop
# CHECK-NEXT:       94: fd ff 80 14  	bnez	$4, 0x8c
# CHECK-EMPTY:
# CHECK-NEXT: 00000098 <L2>:
# CHECK-NEXT:       98: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 0000009c <r2ndat>:
# CHECK-NEXT:       9c: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       a0: 00 00 00 00  	nop
# CHECK-NEXT:       a4: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       a8: 22 22 22 22  	addi	$2, $17, 0x2222
# CHECK-EMPTY:
# CHECK-NEXT: 000000ac <r2nok>:
# CHECK-NEXT:       ac: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       b0: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       b4: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000b8 <n2r>:
# CHECK-NEXT:       b8: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       bc: 00 00 00 00  	nop
# CHECK-NEXT:       c0: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000c4 <n2rhl>:
# CHECK-NEXT:       c4: 12 10 00 00  	mflo	$2
# CHECK-NEXT:       c8: 21 48 29 01  	addu	$9, $9, $9
# CHECK-NEXT:       cc: 00 00 00 00  	nop
# CHECK-NEXT:       d0: 18 00 85 00  	mult	$4, $5
# CHECK-EMPTY:
# CHECK-NEXT: 000000d4 <n2rlab>:
# CHECK-NEXT:       d4: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       d8: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 000000dc <L3>:
# CHECK-NEXT:       dc: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000e0 <n2rok>:
# CHECK-NEXT:       e0: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       e4: fe ff 80 14  	bnez	$4, 0xe0
# CHECK-NEXT:       e8: 21 18 42 00  	addu	$3, $2, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000ec <tail>:
# CHECK-NEXT:       ec: 21 48 29 01  	addu	$9, $9, $9
