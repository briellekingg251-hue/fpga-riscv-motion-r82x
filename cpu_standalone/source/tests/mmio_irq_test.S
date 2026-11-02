/* MMIO accesses under timer interrupts with a pseudo-random period.
 * Writes 1..N to GPIO and reads each value back while the timer interrupt
 * fires every 40..295 cycles (xorshift). Exit code 1 = pass, else 0x100 + test.
 * The testbench must count exactly N GPIO writes on the bus (O2_MMIO
 * gpio_writes=N): an MMIO store interrupted after it was performed and then
 * re-executed would add a write that co-simulation cannot see.
 */
    .equ EXIT, 0x20000000
    .equ GPIO, 0x10001000
    .equ MTIME, 0x10002000
    .equ N, 6000

    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la      sp, __stack_top
    la      t0, handler
    csrw    mtvec, t0
    li      s11, 0
    li      s7, 0
    li      s0, 0x2545f491          /* xorshift state */
    li      a0, MTIME
    sw      zero, 12(a0)            /* mtimecmp hi = 0 */
    lw      t0, 0(a0)
    addi    t0, t0, 100
    sw      t0, 8(a0)
    li      t0, 0x80
    csrw    mie, t0
    csrsi   mstatus, 8
    /* 1: every written value reads back */
    li      s11, 1
    li      a1, GPIO
    li      s1, 1
    li      s2, N + 1
1:  sw      s1, 0(a1)
    lw      t0, 0(a1)
    bne     t0, s1, fail
    addi    s1, s1, 1
    bne     s1, s2, 1b
    csrci   mstatus, 8
    csrw    mie, zero
    /* 2: the interrupts really interleaved with the loop */
    li      s11, 2
    li      t0, 100
    bltu    s7, t0, fail
pass:
    li      a0, EXIT
    li      t0, 1
    sw      t0, 0(a0)
2:  j       2b
fail:
    li      a0, EXIT
    addi    t0, s11, 0x100
    sw      t0, 0(a0)
3:  j       3b

    .align 2
handler:                            /* timer only; uses t3-t5, s0, s7 */
    slli    t3, s0, 13
    xor     s0, s0, t3
    srli    t3, s0, 17
    xor     s0, s0, t3
    slli    t3, s0, 5
    xor     s0, s0, t3
    andi    t3, s0, 255
    li      t5, MTIME
    lw      t4, 0(t5)
    add     t4, t4, t3
    addi    t4, t4, 40
    sw      t4, 8(t5)
    addi    s7, s7, 1
    mret
