/* Bus-error and MMIO exception test. Exit code 1 = pass, else 0x100 + test.
 * Run with the testbench error injection (o2_mem_shim):
 *   +ERR_LO=80010000 +ERR_HI=80010080    reads of these 4 lines fail
 *   +WERR_LO=80011000 +WERR_HI=80011020  write-back of this line fails
 * and check that uart.txt holds exactly the message below (no MMIO store may
 * be performed twice, even with a timer interrupt every TICK cycles).
 * Handler: exceptions record mcause/mtval/mepc in s9/s10/s4 and resume after
 * the faulting instruction (fetch faults return to ra); the timer interrupt
 * re-arms mtimecmp and counts in s7; the bus-error-unit interrupt records
 * status/address in s5/s6, clears the unit and counts in s8.
 */
    .equ EXIT, 0x20000000
    .equ UART, 0x10000000
    .equ GPIO, 0x10001000
    .equ MTIME, 0x10002000
    .equ MTIMECMP, 0x10002008
    .equ BEU, 0x10004000
    .equ ERR_BASE, 0x80010000
    .equ WERR_LINE, 0x80011000
    .equ WAY_STRIDE, 0x2000         /* D$: 256 sets x 32 B per way */
    .equ TICK, 97

    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la      sp, __stack_top
    la      t0, handler
    csrw    mtvec, t0
    li      s11, 0
    li      s8, 0
    li      s7, 0

.macro EXPECT num, cause
    li      s11, \num
    li      t6, \cause
    bne     s9, t6, fail
.endm

    /* 1: fetch from a line whose refill fails: precise, mepc = mtval = target */
    li      a1, ERR_BASE
    li      s9, -1
    jalr    ra, 0(a1)
    EXPECT  1, 1
    bne     s10, a1, fail
    bne     s4, a1, fail
    /* 2: the failed line was not installed: the same fetch faults again */
    li      s9, -1
    jalr    ra, 0(a1)
    EXPECT  2, 1
    /* 3: load from a failing line: precise, rd untouched, younger op once */
    li      a1, ERR_BASE + 0x20
    li      t0, 0x5a5a
    li      t1, 0
    li      s9, -1
    lw      t0, 0(a1)
    addi    t1, t1, 1
    EXPECT  3, 5
    bne     s10, a1, fail
    li      t2, 0x5a5a
    bne     t0, t2, fail
    li      t2, 1
    bne     t1, t2, fail
    /* 4: byte load at another offset of the same line */
    li      s9, -1
    lbu     t0, 7(a1)
    EXPECT  4, 5
    addi    t2, a1, 7
    bne     s10, t2, fail
    /* 5: halfword load from a third failing line */
    li      a1, ERR_BASE + 0x60
    li      s9, -1
    lh      t0, 2(a1)
    EXPECT  5, 5
    /* 6: good memory still works */
    li      s11, 6
    la      a0, data
    lw      t0, 0(a0)
    li      t2, 0x11223344
    bne     t0, t2, fail
    /* 7: MMIO store answered with an error (UART status is read-only):
     *    precise store fault; the younger MMIO store runs once, after it */
    li      a1, UART + 4
    li      a2, GPIO
    sw      zero, 0(a2)
    li      t1, 0
    li      t3, 0xa5
    li      s9, -1
    sw      t3, 0(a1)
    sw      t3, 0(a2)
    addi    t1, t1, 1
    EXPECT  7, 7
    bne     s10, a1, fail
    lw      t0, 0(a2)
    bne     t0, t3, fail
    li      t2, 1
    bne     t1, t2, fail
    /* 8-12: unmapped MMIO store / load, partial EXIT store, EXIT load,
     *       store outside every decoded window */
    li      a1, 0x10005000
    li      s9, -1
    sw      t3, 0(a1)
    EXPECT  8, 7
    bne     s10, a1, fail
    li      s9, -1
    lw      t0, 0(a1)
    EXPECT  9, 5
    li      a1, EXIT
    li      s9, -1
    sb      t3, 0(a1)
    EXPECT  10, 7
    li      s9, -1
    lw      t0, 0(a1)
    EXPECT  11, 5
    li      a1, 0x30000000
    li      s9, -1
    sw      t3, 0(a1)
    EXPECT  12, 7
    /* 13: GPIO write / read back */
    li      s11, 13
    li      a2, GPIO
    li      t3, 0x12345678
    sw      t3, 0(a2)
    lw      t0, 0(a2)
    bne     t0, t3, fail
    /* 14: committed store into a failing line: discarded and reported by
     *     the bus-error unit (machine external interrupt) */
    li      t0, 0x800
    csrw    mie, t0
    csrsi   mstatus, 8
    li      a1, ERR_BASE + 0x40
    li      t3, 0x77
    sw      t3, 4(a1)
    li      t2, 200000
1:  bnez    s8, 2f
    addi    t2, t2, -1
    bnez    t2, 1b
    li      s11, 14
    j       fail
2:  li      s11, 14
    li      t2, 1
    bne     s8, t2, fail
    andi    t0, s5, 7
    li      t2, 1               /* pending, not a write-back, nothing dropped */
    bne     t0, t2, fail
    addi    t2, a1, 4
    bne     s6, t2, fail
    /* 15: dirty line whose write-back is answered with an error. The MMIO
     *     load waits until the store has drained; the conflicting loads
     *     depend on it, so they evict the dirty line afterwards. */
    li      a1, WERR_LINE
    sw      t3, 0(a1)
    li      a2, GPIO
    lw      t0, 0(a2)
    andi    t0, t0, 0
    add     a2, a1, t0
    li      t1, WAY_STRIDE
    add     a2, a2, t1
    lw      t0, 0(a2)
    add     a2, a2, t1
    lw      t0, 0(a2)
    add     a2, a2, t1
    lw      t0, 0(a2)
    li      t2, 200000
3:  li      t0, 2
    beq     s8, t0, 4f
    addi    t2, t2, -1
    bnez    t2, 3b
    li      s11, 15
    j       fail
4:  li      s11, 15
    andi    t0, s5, 7
    li      t2, 3               /* pending, write-back */
    bne     t0, t2, fail
    bne     s6, a1, fail
    csrci   mstatus, 8
    csrw    mie, zero
    /* 16: UART output during a timer-interrupt storm */
    li      a1, MTIMECMP
    sw      zero, 4(a1)
    li      a0, MTIME
    lw      t0, 0(a0)
    addi    t0, t0, TICK
    sw      t0, 0(a1)
    li      t0, 0x80
    csrw    mie, t0
    csrsi   mstatus, 8
    la      a0, msg
    li      a1, UART
5:  lbu     t0, 0(a0)
    beqz    t0, 7f
6:  lw      t1, 4(a1)
    andi    t1, t1, 1
    bnez    t1, 6b
    sw      t0, 0(a1)
    addi    a0, a0, 1
    j       5b
7:  csrci   mstatus, 8
    csrw    mie, zero
    li      a1, MTIMECMP
    li      t0, -1
    sw      t0, 4(a1)
    sw      t0, 0(a1)
    li      s11, 16
    li      t0, 8               /* the storm really happened */
    bltu    s7, t0, fail
pass:
    li      a0, EXIT
    li      t0, 1
    sw      t0, 0(a0)
8:  j       8b
fail:
    li      a0, EXIT
    addi    t0, s11, 0x100
    sw      t0, 0(a0)
9:  j       9b

    .align 2
handler:
    csrr    t5, mcause
    bltz    t5, irq
    mv      s9, t5
    csrr    s10, mtval
    csrr    s4, mepc
    li      t4, 1
    beq     s9, t4, 1f
    addi    t5, s4, 4
    csrw    mepc, t5
    mret
1:  csrw    mepc, ra            /* fetch fault: return to the caller */
    mret
irq:
    li      t4, 0x8000000b
    beq     t5, t4, 2f
    li      t5, MTIME           /* timer: next tick */
    lw      t4, 0(t5)
    addi    t4, t4, TICK
    sw      t4, 8(t5)
    addi    s7, s7, 1
    mret
2:  li      t5, BEU
    lw      s5, 0(t5)
    lw      s6, 4(t5)
    sw      zero, 0(t5)
    addi    s8, s8, 1
    mret

    .data
    .align 4
data:
    .word   0x11223344
msg:
    .asciz  "BUSERR uart under timer irq: 0123456789abcdefghijklmnopqrstuvwxyz\n"
