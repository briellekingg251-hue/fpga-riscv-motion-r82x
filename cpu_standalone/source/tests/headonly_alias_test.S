/* Head-only RAM load followed by younger loads. Exit code 1 = pass.
 * The head-only PC table uses 14-bit PC tags. mmio_load's GPIO read at
 * 0x80000104 is registered head-only after its first replay; ram_load's load
 * at 0x80010104 has the same tag, so it also issues head-only and takes the
 * LSU slow path, which borrows D$ data port A for its lookup. The younger
 * independent loads behind it must still read correct data.
 */
    .equ EXIT, 0x20000000
    .equ GPIO, 0x10001000
    .equ ITER, 300

    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la      sp, __stack_top
    la      s1, word_a
    la      s2, table
    li      s3, ITER
    j       loop

    .org    0x100
mmio_load:
    li      a0, GPIO
    lw      t0, 0(a0)               /* 0x80000104 */
    ret

loop:
    call    mmio_load
    call    ram_load
    li      t6, 0x5a5a5a5a
    bne     a0, t6, fail
    li      t6, 0x11111111
    bne     t1, t6, fail
    li      t6, 0x22222222
    bne     t2, t6, fail
    li      t6, 0x33333333
    bne     t3, t6, fail
    li      t6, 0x44444444
    bne     t4, t6, fail
    li      t6, 0x55555555
    bne     t5, t6, fail
    li      t6, 0x66666666
    bne     a1, t6, fail
    li      t6, 0x77777777
    bne     a2, t6, fail
    li      t6, 0x88888888
    bne     a3, t6, fail
    addi    s3, s3, -1
    bnez    s3, loop
    li      a0, EXIT
    li      t0, 1
    sw      t0, 0(a0)
1:  j       1b
fail:
    li      a0, EXIT
    li      t0, 0x101
    sw      t0, 0(a0)
2:  j       2b

    .org    0x10100
ram_load:
    nop
    lw      a0, 0(s1)               /* 0x80010104: same tag as the GPIO load */
    lw      t1, 0(s2)
    lw      t2, 32(s2)
    lw      t3, 64(s2)
    lw      t4, 96(s2)
    lw      t5, 128(s2)
    lw      a1, 160(s2)
    lw      a2, 192(s2)
    lw      a3, 224(s2)
    ret

    .data
    .align 5
word_a:
    .word   0x5a5a5a5a
    .align 5
table:                              /* one word per cache line */
    .word   0x11111111
    .align 5
    .word   0x22222222
    .align 5
    .word   0x33333333
    .align 5
    .word   0x44444444
    .align 5
    .word   0x55555555
    .align 5
    .word   0x66666666
    .align 5
    .word   0x77777777
    .align 5
    .word   0x88888888
