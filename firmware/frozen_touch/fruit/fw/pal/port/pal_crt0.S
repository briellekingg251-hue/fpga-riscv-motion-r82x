/* SPDX-License-Identifier: GPL-3.0-or-later
 * PAL entry for the DDR-resident image (loader ABI 3).  The resident loader
 * has copied the whole binary (text, rodata, data) and executed FENCE.I.
 * This code clears .bss, installs the trap vector and calls main().
 */
    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function
    .option push
    .option norelax
_start:
    la      sp, __stack_top
    la      gp, __global_pointer$
    la      t0, pal_trap_entry
    csrw    mtvec, t0
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    pal_platform_main
3:  j       3b
    .option pop
    .size _start, .-_start

/* Trap frame: x1..x31 at 4*n(sp), 128 bytes.  Misaligned load/store traps are
 * emulated in C and return with mret; everything else reports and halts. */
    .section .text.pal_trap_entry, "ax", @progbits
    .globl pal_trap_entry
    .type pal_trap_entry, @function
    .balign 4
pal_trap_entry:
    addi    sp, sp, -128
    sw      x1, 4(sp)
    sw      x3, 12(sp)
    sw      x4, 16(sp)
    sw      x5, 20(sp)
    sw      x6, 24(sp)
    sw      x7, 28(sp)
    sw      x8, 32(sp)
    sw      x9, 36(sp)
    sw      x10, 40(sp)
    sw      x11, 44(sp)
    sw      x12, 48(sp)
    sw      x13, 52(sp)
    sw      x14, 56(sp)
    sw      x15, 60(sp)
    sw      x16, 64(sp)
    sw      x17, 68(sp)
    sw      x18, 72(sp)
    sw      x19, 76(sp)
    sw      x20, 80(sp)
    sw      x21, 84(sp)
    sw      x22, 88(sp)
    sw      x23, 92(sp)
    sw      x24, 96(sp)
    sw      x25, 100(sp)
    sw      x26, 104(sp)
    sw      x27, 108(sp)
    sw      x28, 112(sp)
    sw      x29, 116(sp)
    sw      x30, 120(sp)
    sw      x31, 124(sp)
    addi    t0, sp, 128
    sw      t0, 8(sp)          /* original sp */
    sw      zero, 0(sp)
    mv      a0, sp
    call    pal_trap_handler
    lw      x1, 4(sp)
    lw      x3, 12(sp)
    lw      x4, 16(sp)
    lw      x5, 20(sp)
    lw      x6, 24(sp)
    lw      x7, 28(sp)
    lw      x8, 32(sp)
    lw      x9, 36(sp)
    lw      x10, 40(sp)
    lw      x11, 44(sp)
    lw      x12, 48(sp)
    lw      x13, 52(sp)
    lw      x14, 56(sp)
    lw      x15, 60(sp)
    lw      x16, 64(sp)
    lw      x17, 68(sp)
    lw      x18, 72(sp)
    lw      x19, 76(sp)
    lw      x20, 80(sp)
    lw      x21, 84(sp)
    lw      x22, 88(sp)
    lw      x23, 92(sp)
    lw      x24, 96(sp)
    lw      x25, 100(sp)
    lw      x26, 104(sp)
    lw      x27, 108(sp)
    lw      x28, 112(sp)
    lw      x29, 116(sp)
    lw      x30, 120(sp)
    lw      x31, 124(sp)
    addi    sp, sp, 128
    mret
    .size pal_trap_entry, .-pal_trap_entry
