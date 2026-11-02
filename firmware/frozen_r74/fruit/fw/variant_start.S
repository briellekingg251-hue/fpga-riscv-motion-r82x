/* Small RAM entry copies the linked dispatcher to DDR before it replaces RAM.
 * Resident loader and both handoff records stay at their original addresses. */
    .section .text.stub,"ax",@progbits
    .globl _start
    .option norelax
_start:
    li t3,0x10004f00
    li t4,0x10002000
    lw t5,0(t4)
    li t6,315000000
1:  lw t0,0(t3)
    andi t0,t0,1
    bnez t0,2f
    lw t0,0(t4)
    sub t0,t0,t5
    bltu t0,t6,1b
    li t0,0x80018000
    jr t0
2:  la t0,__payload_load
    la t1,__payload_start
    la t2,__payload_end
3:  bgeu t1,t2,4f
    lw t3,0(t0)
    sw t3,0(t1)
    addi t0,t0,4
    addi t1,t1,4
    j 3b
4:  fence rw,rw
    .word 0x0000100f
    la t0,dispatcher_entry
    jr t0

    .section .text.dispatcher_entry,"ax",@progbits
    .globl dispatcher_entry
dispatcher_entry:
    la sp,__stack_top
    andi sp,sp,-16
    la t0,__bss_start
    la t1,__bss_end
5:  bgeu t0,t1,6f
    sw zero,0(t0)
    addi t0,t0,4
    j 5b
6:  call main
7:  j 7b
