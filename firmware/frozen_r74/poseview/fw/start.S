/* P1 RV32I bare-metal entry.  RAM is preloaded from ELF PT_LOAD segments,
 * so .data needs no ROM-to-RAM copy.  The reset/testbench may deliberately
 * leave RAM dirty; this routine owns .bss initialization.
 */
    .section .text.start, "ax", @progbits
    .globl _start
    .type _start, @function
    .option push
    .option norelax

_start:
    la      sp, __stack_top
    andi    sp, sp, -16

    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sb      zero, 0(t0)
    addi    t0, t0, 1
    j       1b
2:
    call    main
3:
    j       3b

    .option pop
    .size _start, .-_start
