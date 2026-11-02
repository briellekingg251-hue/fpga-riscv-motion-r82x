    .section .text.storage_jump,"ax",@progbits
    .globl storage_jump
    .type storage_jump,@function
storage_jump:
    fence rw,rw
    .word 0x0000100f
    jr a0
    .size storage_jump,.-storage_jump
