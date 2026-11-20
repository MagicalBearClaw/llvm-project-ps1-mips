# MIPS I load delays under `.set reorder`: the integrated assembler matches gas
# byte for byte, including the address of every label (MIC-19). See
# docs/ps1/hazards.md, H1.
#
# The CHECK lines are the gas output: this file assembled with GNU as 2.47
# (`mipsel-none-elf-as -march=r3000 -EL -O1`) and disassembled with
# llvm-objdump -d. -O1 pads the same as the default -O2 but does not move
# instructions into branch delay slots, which the integrated assembler never
# does either.
#
# Left out because other tickets cover them: mflo/mfhi then mult/div and
# mtc2 then mfc2 (MIC-20, MIC-44), cfc2 (MIC-42).
#
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=r3000a -filetype=obj \
# RUN:   | llvm-objdump -d - | FileCheck %s
# RUN: llvm-mc %s -triple=mipsel-unknown-none-elf -mcpu=mips1 -filetype=obj \
# RUN:   | llvm-objdump -d - | FileCheck %s

	.set reorder
# GPR loads: a nop only when the next instruction reads the register.
use:	lw $2, 0($4)
	addu $3, $2, $5
other:	lw $2, 0($4)
	addu $3, $6, $5
store:	lw $2, 0($4)
	sw $2, 0($5)
base:	lw $2, 0($4)
	lw $3, 0($2)
chain:	lb $2, 0($4)
	lbu $3, 0($4)
	lh $5, 0($3)
	lhu $6, 0($5)
	or $7, $6, $0
zero:	lw $0, 0($4)
	addu $3, $0, $0
# lwl/lwr pair to one register: no nop between them.
pair:	lwl $2, 3($4)
	lwr $2, 0($4)
	addu $3, $2, $0
pair2:	lw $2, 0($4)
	lwl $2, 3($4)
	lwr $3, 0($4)
	addu $3, $3, $0
# Coprocessor reads.
cop0:	mfc0 $2, $12
	addu $3, $2, 1
cop2:	mfc2 $2, $9
	mtc2 $2, $10
	addu $5, $5, 1
	mfc2 $2, $9
	mfc2 $3, $9
	addu $3, $3, 1
lwc2:	lwc2 $9, 0($4)
	mfc2 $2, $9
	addu $3, $2, $0
# Branches and jumps read their operands; the slot nop reads nothing.
br:	lw $2, 0($4)
	beq $2, $0, br
	addu $3, $3, 1
brother: lw $2, 0($4)
	beq $5, $0, br
	addu $3, $2, 1
jr:	lw $2, 0($4)
	jr $2
jal:	lw $4, 0($5)
	jal use
jalr:	lw $25, 0($5)
	jalr $25
# Macros expand to several instructions; each is checked.
mac:	lw $2, sym
	addu $3, $2, 1
li:	lw $2, 0($4)
	li $3, 0x12345678
	addu $3, $2, 1
# Labels: the nop goes before the label, if the next instruction needs it.
lab1:	lw $2, 0($4)
L1:	addu $3, $2, 1
lab2:	lw $2, 0($4)
L2:	addu $3, $6, 1
lab3:	lw $2, 0($4)
L3a:
L3b:	addu $3, $2, 1
# Directives that emit nothing do not end the load delay.
dir:	lw $2, 0($4)
	.globl dir
	.type dir, @function
	.set push
	.set at
	.set pop
	.insn
	addu $3, $2, 1
# The first instruction after .set noreorder is still checked.
nor:	lw $2, 0($4)
	.set noreorder
	addu $3, $2, 1
	lw $2, 0($4)
	addu $3, $2, 1
	.set reorder
# Emitting data or switching sections pads: the next instruction is unknown.
dat:	lw $2, 0($4)
	.word 0x11111111
	addu $3, $2, 1
datl:	lw $2, 0($4)
DL:	.word 0x22222222
	addu $3, $2, 1
sec:	lw $2, 0($4)
	.data
	.word 0x33333333
	.text
	addu $3, $6, 1
spc:	lw $2, 0($4)
	.space 4
	addu $3, $6, 1
# End of the file pads after a trailing load.
tail:	addu $3, $3, 1
	lw $2, 0($4)

# CHECK:      00000000 <use>:
# CHECK-NEXT:        0: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:        4: 00 00 00 00  	nop
# CHECK-NEXT:        8: 21 18 45 00  	addu	$3, $2, $5
# CHECK-EMPTY:
# CHECK-NEXT: 0000000c <other>:
# CHECK-NEXT:        c: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       10: 21 18 c5 00  	addu	$3, $6, $5
# CHECK-EMPTY:
# CHECK-NEXT: 00000014 <store>:
# CHECK-NEXT:       14: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       18: 00 00 00 00  	nop
# CHECK-NEXT:       1c: 00 00 a2 ac  	sw	$2, 0x0($5)
# CHECK-EMPTY:
# CHECK-NEXT: 00000020 <base>:
# CHECK-NEXT:       20: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       24: 00 00 00 00  	nop
# CHECK-NEXT:       28: 00 00 43 8c  	lw	$3, 0x0($2)
# CHECK-EMPTY:
# CHECK-NEXT: 0000002c <chain>:
# CHECK-NEXT:       2c: 00 00 82 80  	lb	$2, 0x0($4)
# CHECK-NEXT:       30: 00 00 83 90  	lbu	$3, 0x0($4)
# CHECK-NEXT:       34: 00 00 00 00  	nop
# CHECK-NEXT:       38: 00 00 65 84  	lh	$5, 0x0($3)
# CHECK-NEXT:       3c: 00 00 00 00  	nop
# CHECK-NEXT:       40: 00 00 a6 94  	lhu	$6, 0x0($5)
# CHECK-NEXT:       44: 00 00 00 00  	nop
# CHECK-NEXT:       48: 25 38 c0 00  	move	$7, $6
# CHECK-EMPTY:
# CHECK-NEXT: 0000004c <zero>:
# CHECK-NEXT:       4c: 00 00 80 8c  	lw	$zero, 0x0($4)
# CHECK-NEXT:       50: 21 18 00 00  	move	$3, $zero
# CHECK-EMPTY:
# CHECK-NEXT: 00000054 <pair>:
# CHECK-NEXT:       54: 03 00 82 88  	lwl	$2, 0x3($4)
# CHECK-NEXT:       58: 00 00 82 98  	lwr	$2, 0x0($4)
# CHECK-NEXT:       5c: 00 00 00 00  	nop
# CHECK-NEXT:       60: 21 18 40 00  	move	$3, $2
# CHECK-EMPTY:
# CHECK-NEXT: 00000064 <pair2>:
# CHECK-NEXT:       64: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       68: 03 00 82 88  	lwl	$2, 0x3($4)
# CHECK-NEXT:       6c: 00 00 83 98  	lwr	$3, 0x0($4)
# CHECK-NEXT:       70: 00 00 00 00  	nop
# CHECK-NEXT:       74: 21 18 60 00  	move	$3, $3
# CHECK-EMPTY:
# CHECK-NEXT: 00000078 <cop0>:
# CHECK-NEXT:       78: 00 60 02 40  	mfc0	$2, $12, 0x0
# CHECK-NEXT:       7c: 00 00 00 00  	nop
# CHECK-NEXT:       80: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000084 <cop2>:
# CHECK-NEXT:       84: 00 48 02 48  	mfc2	$2, $9, 0x0
# CHECK-NEXT:       88: 00 00 00 00  	nop
# CHECK-NEXT:       8c: 00 50 82 48  	mtc2	$2, $10, 0x0
# CHECK-NEXT:       90: 01 00 a5 24  	addiu	$5, $5, 0x1
# CHECK-NEXT:       94: 00 48 02 48  	mfc2	$2, $9, 0x0
# CHECK-NEXT:       98: 00 48 03 48  	mfc2	$3, $9, 0x0
# CHECK-NEXT:       9c: 00 00 00 00  	nop
# CHECK-NEXT:       a0: 01 00 63 24  	addiu	$3, $3, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 000000a4 <lwc2>:
# CHECK-NEXT:       a4: 00 00 89 c8  	lwc2	$9, 0x0($4)
# CHECK-NEXT:       a8: 00 48 02 48  	mfc2	$2, $9, 0x0
# CHECK-NEXT:       ac: 00 00 00 00  	nop
# CHECK-NEXT:       b0: 21 18 40 00  	move	$3, $2
# CHECK-EMPTY:
# CHECK-NEXT: 000000b4 <br>:
# CHECK-NEXT:       b4: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       b8: 00 00 00 00  	nop
# CHECK-NEXT:       bc: fd ff 40 10  	beqz	$2, 0xb4
# CHECK-NEXT:       c0: 00 00 00 00  	nop
# CHECK-NEXT:       c4: 01 00 63 24  	addiu	$3, $3, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 000000c8 <brother>:
# CHECK-NEXT:       c8: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       cc: f9 ff a0 10  	beqz	$5, 0xb4
# CHECK-NEXT:       d0: 00 00 00 00  	nop
# CHECK-NEXT:       d4: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 000000d8 <jr>:
# CHECK-NEXT:       d8: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:       dc: 00 00 00 00  	nop
# CHECK-NEXT:       e0: 08 00 40 00  	jr	$2
# CHECK-NEXT:       e4: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 000000e8 <jal>:
# CHECK-NEXT:       e8: 00 00 a4 8c  	lw	$4, 0x0($5)
# CHECK-NEXT:       ec: 00 00 00 0c  	jal	0x0
# CHECK-NEXT:       f0: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 000000f4 <jalr>:
# CHECK-NEXT:       f4: 00 00 b9 8c  	lw	$25, 0x0($5)
# CHECK-NEXT:       f8: 00 00 00 00  	nop
# CHECK-NEXT:       fc: 09 f8 20 03  	jalr	$25
# CHECK-NEXT:      100: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 00000104 <mac>:
# CHECK-NEXT:      104: 00 00 02 3c  	lui	$2, 0x0
# CHECK-NEXT:      108: 00 00 42 8c  	lw	$2, 0x0($2)
# CHECK-NEXT:      10c: 00 00 00 00  	nop
# CHECK-NEXT:      110: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000114 <li>:
# CHECK-NEXT:      114: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      118: 34 12 03 3c  	lui	$3, 0x1234
# CHECK-NEXT:      11c: 78 56 63 34  	ori	$3, $3, 0x5678
# CHECK-NEXT:      120: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000124 <lab1>:
# CHECK-NEXT:      124: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      128: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 0000012c <L1>:
# CHECK-NEXT:      12c: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000130 <lab2>:
# CHECK-NEXT:      130: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-EMPTY:
# CHECK-NEXT: 00000134 <L2>:
# CHECK-NEXT:      134: 01 00 c3 24  	addiu	$3, $6, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000138 <lab3>:
# CHECK-NEXT:      138: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      13c: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 00000140 <L3b>:
# CHECK-NEXT:      140: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000144 <dir>:
# CHECK-NEXT:      144: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      148: 00 00 00 00  	nop
# CHECK-NEXT:      14c: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000150 <nor>:
# CHECK-NEXT:      150: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      154: 00 00 00 00  	nop
# CHECK-NEXT:      158: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-NEXT:      15c: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      160: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000164 <dat>:
# CHECK-NEXT:      164: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      168: 00 00 00 00  	nop
# CHECK-NEXT:      16c: 11 11 11 11  	beq	$8, $17, 0x45b4
# CHECK-NEXT:      170: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000174 <datl>:
# CHECK-NEXT:      174: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      178: 00 00 00 00  	nop
# CHECK-EMPTY:
# CHECK-NEXT: 0000017c <DL>:
# CHECK-NEXT:      17c: 22 22 22 22  	addi	$2, $17, 0x2222
# CHECK-NEXT:      180: 01 00 43 24  	addiu	$3, $2, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000184 <sec>:
# CHECK-NEXT:      184: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      188: 00 00 00 00  	nop
# CHECK-NEXT:      18c: 01 00 c3 24  	addiu	$3, $6, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 00000190 <spc>:
# CHECK-NEXT:      190: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT: 		...
# CHECK-NEXT:      19c: 01 00 c3 24  	addiu	$3, $6, 0x1
# CHECK-EMPTY:
# CHECK-NEXT: 000001a0 <tail>:
# CHECK-NEXT:      1a0: 01 00 63 24  	addiu	$3, $3, 0x1
# CHECK-NEXT:      1a4: 00 00 82 8c  	lw	$2, 0x0($4)
# CHECK-NEXT:      1a8: 00 00 00 00  	nop
