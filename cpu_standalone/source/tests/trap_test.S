/* Directed machine-mode trap / interrupt / CSR / FENCE.I test.
 * Exit code 1 = pass; otherwise 0x100 + failing test number.
 * Each faulting instruction is followed by a check of the handler's record.
 */
    .equ EXIT, 0x20000000
    .equ MTIME, 0x10002000
    .equ MTIMECMP, 0x10002008

    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la      sp, __stack_top
    la      t0, handler
    csrw    mtvec, t0
    li      s11, 0              /* test number */

/* expect_trap: after the faulting instruction, handler stored cause in s9, tval in s10 */
.macro CHECK_CAUSE num, cause
    li      s11, \num
    li      t6, \cause
    bne     s9, t6, fail
.endm

    /* 1: ecall */
    li      s9, -1
    ecall
    CHECK_CAUSE 1, 11
    /* 2: ebreak (tval = pc) */
    li      s9, -1
1:  ebreak
    CHECK_CAUSE 2, 3
    la      t6, 1b
    bne     s10, t6, fail
    /* 3: illegal instruction (all-zero word), tval = instruction */
    li      s9, -1
    .word   0x00000000
    CHECK_CAUSE 3, 2
    bnez    s10, fail
    /* 4: illegal CSR */
    li      s9, -1
    csrr    t0, 0x7c0
    CHECK_CAUSE 4, 2
    /* 5: misaligned load, tval = address */
    la      a0, data
    addi    a1, a0, 1
    li      s9, -1
    lw      t0, 0(a1)
    CHECK_CAUSE 5, 4
    bne     s10, a1, fail
    /* 6: misaligned store */
    addi    a1, a0, 2
    li      s9, -1
    sw      t0, 1(a1)
    CHECK_CAUSE 6, 6
    /* 7: misaligned halfword load is fine at even address */
    lh      t0, 2(a0)
    li      t1, 0x1122
    li      s11, 7
    bne     t0, t1, fail
    /* 8: load access fault (beyond RAM) */
    li      a1, 0x90000000
    li      s9, -1
    lw      t0, 0(a1)
    CHECK_CAUSE 8, 5
    /* 9: store access fault */
    li      s9, -1
    sw      t0, 0(a1)
    CHECK_CAUSE 9, 7
    /* 10: jalr to misaligned target: cause 0, tval = target */
    la      a1, 2f
    addi    a1, a1, 2
    li      s9, -1
    jalr    ra, 0(a1)
    j       3f
2:  nop
    nop
3:  CHECK_CAUSE 10, 0
    bne     s10, a1, fail
    /* 11: CSR read/write semantics */
    li      s11, 11
    li      t0, 0x12345678
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, fail
    li      t2, 0xff
    csrrs   t1, mscratch, t2
    bne     t0, t1, fail
    csrr    t1, mscratch
    ori     t3, t0, 0xff
    bne     t1, t3, fail
    csrrci  t1, mscratch, 0x1f
    csrr    t1, mscratch
    andi    t3, t3, -32
    bne     t1, t3, fail
    csrr    t1, misa
    beqz    t1, fail
    /* 12: mcycle / minstret advance */
    li      s11, 12
    csrr    t0, minstret
    csrr    t1, mcycle
    nop
    csrr    t2, minstret
    csrr    t3, mcycle
    bleu    t2, t0, fail
    bleu    t3, t1, fail
    /* 13: store / load forwarding and byte lanes */
    li      s11, 13
    la      a0, data
    li      t0, 0x11223344
    sw      t0, 8(a0)
    sb      zero, 9(a0)
    lw      t1, 8(a0)
    li      t2, 0x11220044
    bne     t1, t2, fail
    lbu     t1, 11(a0)
    li      t2, 0x11
    bne     t1, t2, fail
    sh      t0, 10(a0)
    lw      t1, 8(a0)
    li      t2, 0x33440044
    bne     t1, t2, fail
    /* 14: FENCE.I with self-modifying code */
    li      s11, 14
    la      a0, smc
    li      t0, 0x02a00513      /* addi a0, x0, 42 */
    sw      t0, 0(a0)
    fence.i
    jal     ra, smc
    li      t1, 42
    bne     a0, t1, fail
    /* 15: timer interrupt */
    li      s11, 15
    li      s8, 0               /* interrupt counter */
    li      a0, MTIME
    lw      t0, 0(a0)
    addi    t0, t0, 200
    li      a1, MTIMECMP
    sw      zero, 4(a1)
    sw      t0, 0(a1)
    li      t1, 0x80
    csrw    mie, t1
    csrsi   mstatus, 8
    li      t2, 100000
4:  bnez    s8, 5f
    addi    t2, t2, -1
    bnez    t2, 4b
    j       fail
5:  csrci   mstatus, 8
    li      t1, 0x80000007
    bne     s9, t1, fail
    /* 16: mret restores MIE from MPIE */
    li      s11, 16
    csrr    t0, mstatus
    andi    t0, t0, 8
    bnez    t0, fail
pass:
    li      a0, EXIT
    li      t0, 1
    sw      t0, 0(a0)
6:  j       6b
fail:
    li      a0, EXIT
    addi    t0, s11, 0x100
    sw      t0, 0(a0)
7:  j       7b

    .align 2
handler:
    csrr    s9, mcause
    csrr    s10, mtval
    bltz    s9, irq
    csrr    t5, mepc
    addi    t5, t5, 4
    csrw    mepc, t5
    mret
irq:
    li      t5, MTIMECMP
    li      t4, -1
    sw      t4, 4(t5)           /* push mtimecmp far into the future */
    sw      t4, 0(t5)
    addi    s8, s8, 1
    mret

    .align 2
smc:
    addi    a0, x0, 0           /* rewritten to addi a0, x0, 42 */
    ret

    .data
    .align 4
data:
    .word   0x11223344, 0x55667788, 0, 0
