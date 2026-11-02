/* SPDX-License-Identifier: GPL-2.0-or-later
 * Entry of the DDR-resident NES image (loader ABI 3).  The resident loader has
 * copied GAME.BIN to 0x80100000, verified its CRC and executed FENCE.I.
 * Clear .bss, install the trap vector, run nes_main (which never returns). */
    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function
    .option push
    .option norelax
_start:
    la      sp, __stack_top
    la      gp, __global_pointer$
    la      t0, nes_trap_entry
    csrw    mtvec, t0
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    nes_main
3:  j       3b
    .option pop
    .size _start, .-_start

/* Save all integer registers in a 128-byte frame (x[n] at 4*n, x2 = old sp)
 * so the C handler can emulate a misaligned access and resume with mret. */
    .section .text.nes_trap_entry, "ax", @progbits
    .globl nes_trap_entry
    .type nes_trap_entry, @function
    .balign 4
nes_trap_entry:
    addi    sp, sp, -128
    .irp    n, 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    sw      x\n, 4*\n(sp)
    .endr
    addi    t0, sp, 128
    sw      t0, 8(sp)
    sw      zero, 0(sp)
    mv      a0, sp
    call    nes_trap_handler
    .irp    n, 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    lw      x\n, 4*\n(sp)
    .endr
    lw      sp, 8(sp)
    mret
    .size nes_trap_entry, .-nes_trap_entry
