    .equ EXIT, 0x20000000
    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la   sp, __stack_top
    la   s0, buf
    li   s1, 6            /* outer iterations */
    li   t0, 0x12345678
    li   t1, 0x9abcdef1
    li   t2, 0x0f1e2d3c
    li   t3, 0x55aa33cc
outer:
    lh   a2, 2(s0)
    sw   t5, 0(s0)
    sw   a4, 0(s0)
    sh   t0, 0(s0)
    sb   t3, 1(s0)
    lw   a2, 0(s0)
    sb   t4, 21(s0)
    sh   a3, 20(s0)
    sw   t2, 20(s0)
    sb   a2, 22(s0)
    lw   t4, 20(s0)
    lw   t3, 20(s0)
    sw   t3, 0(s0)
    sb   t5, 2(s0)
    sh   t4, 2(s0)
    sb   a1, 2(s0)
    lw   t1, 0(s0)
    lw   a2, 0(s0)
    sw   t5, 8(s0)
    lhu   t1, 20(s0)
    srl  t3, t3, a3
    lh   a2, 8(s0)
    add  a2, a2, t5
    sub  a2, a2, t4
    sh   a4, 30(s0)
    sw   t5, 28(s0)
    sb   a3, 31(s0)
    lw   t0, 28(s0)
    lw   t4, 28(s0)
    sb   t4, 30(s0)
    sh   t0, 30(s0)
    sw   a4, 28(s0)
    lhu   a4, 30(s0)
    lw   t2, 28(s0)
    andi t6, t2, 16
    beqz t6, 11f
    sw   a2, 4(s0)
    lbu   t5, 25(s0)
    lbu   a2, 31(s0)
11:
    lhu   t2, 26(s0)
    sh   a4, 30(s0)
    sll  t2, t2, t1
    add  a3, a3, a3
    addi a3, a3, 1339
    sb   a4, 6(s0)
    xor  a3, a3, t5
    addi a3, a3, -1898
    sw   t5, 12(s0)
    sw   a2, 28(s0)
    sw   a3, 28(s0)
    sb   a3, 30(s0)
    sw   t3, 28(s0)
    lw   a1, 28(s0)
    lw   t3, 28(s0)
    sll  t0, t0, t3
    sll  t2, t2, t2
    andi t6, a3, 4
    beqz t6, 12f
    lw   t4, 16(s0)
    lw   t0, 28(s0)
12:
    lb   a4, 31(s0)
    lh   t0, 2(s0)
    srl  a2, a2, t0
    add  a2, a2, a2
    add  a4, a4, t5
    addi a4, a4, -1843
    sub  t3, t3, t0
    add  t2, t2, t5
    sll  t2, t2, a1
    sw   t2, 24(s0)
    lh   t0, 22(s0)
    add  a3, a3, t0
    andi t6, t1, 2
    beqz t6, 13f
    sh   t4, 10(s0)
    sh   t2, 0(s0)
13:
    add  a3, a3, t0
    sw   a3, 24(s0)
    andi t6, a3, 2
    beqz t6, 14f
    lbu   t2, 25(s0)
    sb   t1, 28(s0)
14:
    lh   t0, 20(s0)
    lh   a4, 6(s0)
    sll  t1, t1, t5
    addi t1, t1, 1984
    sb   a1, 13(s0)
    sll  t3, t3, a2
    addi t3, t3, -502
    sw   a4, 16(s0)
    andi t6, t4, 16
    beqz t6, 15f
    lw   t0, 4(s0)
    lbu   a4, 29(s0)
    sh   a3, 24(s0)
15:
    sw   a3, 12(s0)
    sll  t5, t5, a2
    andi t6, a2, 4
    beqz t6, 16f
    sh   t1, 2(s0)
    sw   t5, 20(s0)
16:
    sw   a1, 0(s0)
    sb   t4, 17(s0)
    xor  t5, t5, t5
    sh   t0, 2(s0)
    sh   a3, 12(s0)
    lw   t4, 28(s0)
    xor  t2, t2, t5
    sub  t5, t5, t0
    andi t6, a1, 1
    beqz t6, 17f
    sb   t0, 20(s0)
    lw   t2, 8(s0)
    sw   t4, 20(s0)
17:
    sw   t0, 28(s0)
    sw   t0, 28(s0)
    sw   t2, 28(s0)
    sb   a4, 31(s0)
    lhu   a1, 28(s0)
    sw   t2, 4(s0)
    lb   a2, 11(s0)
    lw   t5, 4(s0)
    lb   a1, 13(s0)
    lb   t0, 8(s0)
    lbu   a4, 16(s0)
    lb   a3, 27(s0)
    xor  a2, a2, t2
    sw   t0, 24(s0)
    or  t4, t4, t5
    lhu   a3, 6(s0)
    lhu   a4, 4(s0)
    lw   t5, 24(s0)
    lh   a2, 14(s0)
    sb   t4, 6(s0)
    sb   a3, 2(s0)
    sw   t3, 12(s0)
    sb   t0, 3(s0)
    lbu   t1, 31(s0)
    sw   t3, 4(s0)
    sh   a4, 6(s0)
    lb   a2, 5(s0)
    lhu   t1, 6(s0)
    lb   a3, 11(s0)
    srl  t1, t1, t5
    add  t0, t0, a4
    addi t0, t0, -1255
    lbu   a3, 0(s0)
    sb   a3, 18(s0)
    lw   t3, 4(s0)
    sw   t1, 28(s0)
    srl  t1, t1, a3
    addi t1, t1, -971
    lhu   a4, 6(s0)
    or  t0, t0, a2
    sw   t2, 24(s0)
    lw   a4, 20(s0)
    lh   a1, 12(s0)
    sll  a1, a1, t2
    sh   t1, 20(s0)
    sh   t3, 22(s0)
    sh   t5, 22(s0)
    lw   t0, 20(s0)
    lw   t0, 20(s0)
    or  a4, a4, a4
    sub  a3, a3, a3
    or  a1, a1, t4
    andi t6, a4, 1
    beqz t6, 18f
    lbu   t1, 6(s0)
    lbu   t5, 7(s0)
18:
    or  t1, t1, a3
    add  t4, t4, t3
    xor  t0, t0, a4
    sll  t0, t0, t2
    addi t0, t0, -1872
    add  a2, a2, t2
    srl  a1, a1, a2
    addi a1, a1, -400
    sb   a3, 15(s0)
    sll  a2, a2, t0
    sw   a3, 8(s0)
    sub  a3, a3, t0
    xor  a4, a4, t1
    addi a4, a4, -1104
    sw   t5, 20(s0)
    or  a4, a4, t5
    addi a4, a4, -983
    sb   a1, 4(s0)
    sb   t0, 6(s0)
    lw   t1, 4(s0)
    andi t6, t5, 1
    beqz t6, 19f
    lw   t1, 24(s0)
19:
    andi t6, t4, 8
    beqz t6, 110f
    sh   a3, 28(s0)
    sh   a3, 8(s0)
110:
    sb   a2, 9(s0)
    sh   a3, 24(s0)
    sb   t4, 2(s0)
    srl  a4, a4, t3
    sw   a4, 16(s0)
    srl  t4, t4, a4
    addi t4, t4, -385
    sb   t2, 24(s0)
    sub  a3, a3, a4
    addi a3, a3, 625
    sh   a2, 6(s0)
    sb   t2, 6(s0)
    sh   t2, 6(s0)
    sh   t1, 4(s0)
    lw   t4, 4(s0)
    lhu   a4, 6(s0)
    lb   a1, 17(s0)
    andi t6, t3, 8
    beqz t6, 111f
    lbu   t4, 0(s0)
111:
    lb   a1, 29(s0)
    sb   t3, 18(s0)
    sw   a1, 16(s0)
    sh   a3, 18(s0)
    lhu   t5, 16(s0)
    add  t1, t1, t2
    xor  t3, t3, a1
    addi t3, t3, -1337
    sw   t1, 28(s0)
    sub  a3, a3, a3
    addi a3, a3, -1655
    lb   t0, 14(s0)
    lbu   a1, 23(s0)
    sw   t4, 0(s0)
    sub  t0, t0, t0
    sh   t2, 6(s0)
    sb   a3, 4(s0)
    sw   t4, 4(s0)
    sh   t1, 4(s0)
    lhu   t4, 6(s0)
    sh   a4, 20(s0)
    lbu   t5, 6(s0)
    sw   t4, 20(s0)
    sb   t3, 22(s0)
    sh   a2, 20(s0)
    lw   t0, 20(s0)
    sb   t4, 5(s0)
    srl  t5, t5, a4
    sb   t4, 4(s0)
    sb   t3, 4(s0)
    sw   t0, 4(s0)
    sh   a4, 6(s0)
    lw   t3, 4(s0)
    lw   t4, 4(s0)
    lhu   a4, 16(s0)
    lh   a2, 18(s0)
    sw   t4, 24(s0)
    sb   t2, 0(s0)
    sh   a4, 18(s0)
    sw   a4, 16(s0)
    sh   t5, 18(s0)
    sb   t0, 19(s0)
    lhu   t5, 16(s0)
    lhu   t0, 18(s0)
    sh   a1, 22(s0)
    lw   a2, 4(s0)
    sll  t3, t3, a1
    sw   t5, 28(s0)
    or  a1, a1, t3
    lb   a2, 25(s0)
    lw   t4, 8(s0)
    andi t6, a1, 16
    beqz t6, 112f
    lbu   a3, 13(s0)
    lw   t0, 8(s0)
112:
    add  t2, t2, a3
    or  t4, t4, t5
    srl  t2, t2, t4
    andi t6, a1, 2
    beqz t6, 113f
    lbu   t4, 2(s0)
    sb   t5, 4(s0)
    lw   a1, 12(s0)
113:
    andi t6, a2, 4
    beqz t6, 114f
    lbu   t5, 9(s0)
    lbu   a4, 17(s0)
114:
    lh   t1, 26(s0)
    lb   a4, 2(s0)
    sw   a2, 12(s0)
    xor  t4, t4, a3
    addi t4, t4, 1002
    sub  t5, t5, t3
    addi t5, t5, 64
    add  t4, t4, a3
    sb   t3, 9(s0)
    lb   a1, 10(s0)
    xor  t0, t0, t2
    or  a3, a3, t0
    andi t6, t2, 16
    beqz t6, 115f
    sw   t1, 8(s0)
115:
    lbu   t2, 12(s0)
    add  t2, t2, t4
    addi t2, t2, 168
    sw   t0, 12(s0)
    add  a1, a1, a4
    lhu   t3, 2(s0)
    sw   t0, 20(s0)
    or  t1, t1, a4
    addi t1, t1, 1116
    sw   a4, 4(s0)
    sub  t0, t0, a3
    lb   a3, 1(s0)
    xor  t1, t1, a2
    lb   t5, 11(s0)
    lb   t2, 21(s0)
    sll  t5, t5, t2
    sw   t0, 12(s0)
    lh   a1, 14(s0)
    sw   a1, 4(s0)
    sb   t1, 6(s0)
    lb   a2, 4(s0)
    lw   a3, 4(s0)
    sb   t5, 14(s0)
    sll  t0, t0, a3
    sw   t3, 0(s0)
    add  t5, t5, a1
    addi t5, t5, -205
    sh   a4, 30(s0)
    sw   a3, 28(s0)
    sb   t4, 31(s0)
    sb   a2, 28(s0)
    lw   a3, 28(s0)
    lhu   t0, 30(s0)
    sw   a1, 28(s0)
    sb   t5, 31(s0)
    sb   a4, 29(s0)
    lw   a3, 28(s0)
    lb   a3, 30(s0)
    sub  t5, t5, t3
    srl  t2, t2, t3
    lw   t0, 16(s0)
    lhu   t2, 22(s0)
    xor  t3, t3, a3
    lh   a4, 18(s0)
    xor  t3, t3, t5
    addi t3, t3, 265
    sb   a1, 24(s0)
    sw   a3, 24(s0)
    sh   a1, 26(s0)
    lw   a2, 24(s0)
    lw   a4, 24(s0)
    add  t1, t1, t0
    xor  a1, a1, t5
    lw   t1, 24(s0)
    sw   t1, 28(s0)
    lw   a1, 12(s0)
    srl  a3, a3, t4
    add  t0, t0, t0
    addi t0, t0, -1743
    lbu   t2, 7(s0)
    lh   t0, 8(s0)
    andi t6, t1, 4
    beqz t6, 116f
    sw   a1, 4(s0)
    sw   t4, 28(s0)
116:
    lw   a4, 28(s0)
    lb   t4, 29(s0)
    xor  t0, t0, t0
    addi t0, t0, 381
    sll  a3, a3, t4
    addi a3, a3, -547
    andi t6, t3, 4
    beqz t6, 117f
    lw   t2, 20(s0)
    lbu   t0, 2(s0)
117:
    srl  a1, a1, t2
    addi a1, a1, 1044
    andi t6, t5, 8
    beqz t6, 118f
    sb   a1, 29(s0)
    sh   a3, 12(s0)
    sh   t1, 4(s0)
118:
    sw   t5, 4(s0)
    andi t6, t2, 8
    beqz t6, 119f
    sw   t4, 20(s0)
119:
    sb   t5, 18(s0)
    add  t1, t1, t4
    addi t1, t1, -620
    andi t6, t4, 1
    beqz t6, 120f
    sh   t2, 4(s0)
120:
    sh   t4, 2(s0)
    srl  t3, t3, t4
    lh   a1, 22(s0)
    srl  t5, t5, t1
    or  a3, a3, t4
    lhu   a3, 24(s0)
    lhu   t2, 28(s0)
    or  t2, t2, a2
    xor  a4, a4, t2
    addi a4, a4, 267
    lw   t5, 4(s0)
    andi t6, t0, 8
    beqz t6, 121f
    sw   t0, 16(s0)
    sw   t1, 12(s0)
121:
    lw   t0, 0(s0)
    xor  a4, a4, t4
    addi a4, a4, -1733
    sh   t5, 12(s0)
    sb   t1, 14(s0)
    sw   a4, 12(s0)
    lb   t3, 12(s0)
    sh   t2, 2(s0)
    srl  a1, a1, a3
    lw   t0, 4(s0)
    lw   t0, 4(s0)
    lw   t4, 12(s0)
    sw   t5, 4(s0)
    sh   t5, 6(s0)
    lb   a2, 4(s0)
    lhu   a4, 6(s0)
    sw   t5, 4(s0)
    srl  t2, t2, a2
    sw   a3, 28(s0)
    sb   t5, 18(s0)
    sll  t1, t1, t0
    sw   t1, 8(s0)
    add  a1, a1, a1
    lh   t2, 16(s0)
    sw   t4, 20(s0)
    sw   t5, 20(s0)
    lw   t4, 20(s0)
    sh   t4, 2(s0)
    sb   t0, 1(s0)
    sw   t2, 12(s0)
    sub  a2, a2, t5
    sh   a4, 4(s0)
    lhu   a1, 26(s0)
    sb   a1, 27(s0)
    sw   a1, 4(s0)
    add  t0, t0, t3
    sll  a4, a4, t2
    addi a4, a4, 1943
    lbu   t0, 16(s0)
    andi t6, a2, 2
    beqz t6, 122f
    lw   t4, 20(s0)
    sb   t2, 8(s0)
    sh   a1, 12(s0)
122:
    xor  t0, t0, t4
    addi t0, t0, -863
    sh   t5, 8(s0)
    sb   t1, 11(s0)
    sb   a1, 10(s0)
    sw   t5, 8(s0)
    lhu   t4, 10(s0)
    add  a4, a4, a2
    lh   t2, 18(s0)
    sw   t1, 12(s0)
    sh   a1, 20(s0)
    andi t6, t0, 4
    beqz t6, 123f
    sb   t1, 14(s0)
    sh   a4, 18(s0)
123:
    or  a3, a3, a1
    lw   t0, 4(s0)
    sw   a1, 24(s0)
    lb   a4, 28(s0)
    lw   a3, 24(s0)
    add  a2, a2, a4
    addi a2, a2, 1270
    sub  a3, a3, a2
    lw   a4, 28(s0)
    lb   a4, 24(s0)
    sw   t5, 28(s0)
    or  a2, a2, t1
    sb   a3, 15(s0)
    sb   t1, 16(s0)
    sw   t0, 0(s0)
    sb   a3, 21(s0)
    sw   t4, 16(s0)
    andi t6, a1, 1
    beqz t6, 124f
    sw   t3, 12(s0)
124:
    sll  a3, a3, t0
    add  a3, a3, t1
    sw   a2, 28(s0)
    sh   t0, 20(s0)
    add  t4, t4, t0
    addi t4, t4, 1080
    or  a2, a2, a2
    lbu   a1, 30(s0)
    lw   t0, 24(s0)
    sw   t2, 0(s0)
    andi t6, a3, 8
    beqz t6, 125f
    lbu   a4, 22(s0)
    lbu   t0, 19(s0)
    lbu   t1, 25(s0)
125:
    lb   a1, 1(s0)
    lw   t0, 16(s0)
    sb   t3, 12(s0)
    sh   t1, 14(s0)
    sh   t0, 12(s0)
    sb   a1, 14(s0)
    lw   a1, 12(s0)
    sw   a1, 12(s0)
    sb   t1, 17(s0)
    sh   t2, 18(s0)
    lw   t2, 16(s0)
    lw   t1, 8(s0)
    add  a1, a1, t4
    sh   t4, 30(s0)
    or  a1, a1, a2
    lhu   t0, 10(s0)
    andi t6, a3, 8
    beqz t6, 126f
    sh   t2, 22(s0)
    sh   a2, 28(s0)
126:
    or  t5, t5, t3
    sw   a2, 0(s0)
    sw   a2, 12(s0)
    sub  t5, t5, a3
    sw   t2, 16(s0)
    xor  t2, t2, t4
    lw   t0, 24(s0)
    sub  t4, t4, a3
    sub  t5, t5, t1
    sw   t4, 0(s0)
    sb   t2, 20(s0)
    andi t6, t0, 16
    beqz t6, 127f
    lbu   a1, 20(s0)
127:
    lw   a1, 20(s0)
    xor  t1, t1, a3
    addi t1, t1, -1179
    lw   t3, 4(s0)
    sh   t0, 26(s0)
    sh   t3, 10(s0)
    sub  a1, a1, a4
    sh   t4, 14(s0)
    sll  a3, a3, t0
    sub  t0, t0, t2
    addi t0, t0, 1170
    andi t6, t2, 8
    beqz t6, 128f
    lbu   t3, 6(s0)
    sb   t4, 16(s0)
    lbu   t3, 18(s0)
128:
    xor  t1, t1, a4
    or  a2, a2, t3
    lw   t1, 12(s0)
    andi t6, t0, 1
    beqz t6, 129f
    sh   a2, 22(s0)
129:
    add  t5, t5, a2
    lhu   t3, 20(s0)
    lw   t4, 8(s0)
    sw   t0, 0(s0)
    sb   t4, 2(s0)
    sw   t2, 0(s0)
    lw   a1, 0(s0)
    lw   t4, 0(s0)
    sh   a2, 18(s0)
    sb   t1, 3(s0)
    sub  t0, t0, a2
    lh   t0, 12(s0)
    sb   t4, 25(s0)
    sw   t5, 24(s0)
    lb   a3, 24(s0)
    srl  a2, a2, a4
    sw   a4, 24(s0)
    srl  a4, a4, a2
    addi a4, a4, 18
    or  a3, a3, a1
    add  t3, t3, a3
    sw   t1, 8(s0)
    lw   t5, 16(s0)
    xor  t1, t1, t4
    addi t1, t1, 106
    sb   t3, 6(s0)
    sll  a2, a2, t2
    addi a2, a2, 551
    xor  t1, t1, a1
    sh   a4, 8(s0)
    sb   t3, 10(s0)
    sh   a3, 8(s0)
    sh   a2, 10(s0)
    lb   t0, 10(s0)
    sub  t4, t4, t3
    lw   a4, 16(s0)
    sll  t2, t2, t3
    sll  t1, t1, a1
    or  a4, a4, t3
    addi a4, a4, -1353
    andi t6, a4, 2
    beqz t6, 130f
    sh   a1, 14(s0)
130:
    lb   a1, 5(s0)
    add  a4, a4, a1
    sb   a4, 22(s0)
    xor  t3, t3, t4
    sub  a4, a4, t2
    add  t5, t5, t2
    addi t5, t5, -139
    sw   t1, 28(s0)
    sh   t3, 4(s0)
    sw   t0, 12(s0)
    andi t6, t4, 4
    beqz t6, 131f
    lbu   a4, 27(s0)
    lbu   t0, 9(s0)
131:
    sb   t5, 24(s0)
    or  a2, a2, t3
    xor  a2, a2, t4
    addi a2, a2, -2036
    andi t6, t1, 4
    beqz t6, 132f
    sw   a1, 20(s0)
132:
    lhu   a1, 22(s0)
    or  a3, a3, t3
    addi a3, a3, -1081
    xor  a2, a2, a4
    sub  t4, t4, a1
    lb   t2, 3(s0)
    sw   a2, 8(s0)
    sb   a3, 8(s0)
    sw   t2, 8(s0)
    lw   a3, 8(s0)
    lh   a4, 26(s0)
    sh   a1, 8(s0)
    sh   t2, 8(s0)
    sw   a4, 8(s0)
    sw   a2, 8(s0)
    lhu   t5, 10(s0)
    sw   t2, 12(s0)
    add  t1, t1, t3
    addi t1, t1, -201
    xor  t4, t4, a1
    andi t6, t3, 2
    beqz t6, 133f
    lw   a4, 28(s0)
133:
    sb   a3, 25(s0)
    lhu   t4, 20(s0)
    add  a2, a2, t4
    sll  a4, a4, t4
    addi a4, a4, 1477
    sw   t5, 16(s0)
    or  t2, t2, a4
    lbu   a1, 21(s0)
    add  a1, a1, t3
    sw   t5, 4(s0)
    lw   t2, 8(s0)
    lbu   t2, 3(s0)
    sub  t0, t0, t4
    sll  t0, t0, a1
    lh   t1, 16(s0)
    lw   t4, 16(s0)
    lbu   t3, 1(s0)
    sh   t2, 18(s0)
    lh   a3, 12(s0)
    lw   a2, 20(s0)
    sh   a4, 14(s0)
    lb   a2, 14(s0)
    srl  a2, a2, t3
    addi a2, a2, -748
    lhu   t4, 8(s0)
    sb   t2, 13(s0)
    add  t0, t0, a1
    sw   a4, 24(s0)
    andi t6, t5, 1
    beqz t6, 134f
    sb   t4, 11(s0)
134:
    andi t6, t1, 16
    beqz t6, 135f
    lw   t4, 0(s0)
    sw   t2, 28(s0)
135:
    lbu   a3, 4(s0)
    andi t6, t2, 1
    beqz t6, 136f
    lw   t5, 28(s0)
    sw   a1, 16(s0)
    sh   t1, 18(s0)
136:
    sw   a2, 16(s0)
    lw   a2, 0(s0)
    lhu   t5, 10(s0)
    lbu   a1, 15(s0)
    sh   t5, 24(s0)
    andi t6, t0, 2
    beqz t6, 137f
    sh   t5, 2(s0)
    sb   a1, 18(s0)
    lw   t0, 0(s0)
137:
    sll  t0, t0, t2
    addi t0, t0, -400
    sb   t5, 18(s0)
    sb   t2, 18(s0)
    sh   a3, 18(s0)
    sb   t1, 19(s0)
    lhu   a3, 18(s0)
    lw   t4, 20(s0)
    andi t6, t4, 1
    beqz t6, 138f
    lbu   t2, 7(s0)
138:
    sll  a3, a3, a3
    lh   a2, 14(s0)
    andi t6, a4, 8
    beqz t6, 139f
    sh   a4, 10(s0)
    lbu   a1, 9(s0)
    sh   a1, 26(s0)
139:
    or  t4, t4, t2
    add  t3, t3, a3
    sh   t5, 22(s0)
    andi t6, t1, 2
    beqz t6, 140f
    sw   a1, 28(s0)
    sh   t2, 18(s0)
140:
    sw   a4, 0(s0)
    lh   t4, 22(s0)
    sh   a2, 14(s0)
    lb   t5, 15(s0)
    sb   t0, 9(s0)
    sw   t4, 8(s0)
    lw   t5, 8(s0)
    add  a1, a1, a1
    sw   t1, 24(s0)
    sh   a1, 16(s0)
    or  t3, t3, a2
    addi t3, t3, 1561
    sw   t4, 8(s0)
    sh   t0, 22(s0)
    sw   t2, 8(s0)
    andi t6, t1, 2
    beqz t6, 141f
    sh   a3, 10(s0)
    sb   a4, 3(s0)
    sh   t1, 16(s0)
141:
    lw   a4, 24(s0)
    andi t6, a1, 16
    beqz t6, 142f
    sb   a3, 29(s0)
    sh   a1, 20(s0)
    sw   a1, 4(s0)
142:
    lb   t3, 29(s0)
    add  t4, t4, t2
    sw   a1, 12(s0)
    sh   t0, 14(s0)
    sb   t5, 13(s0)
    lb   a1, 13(s0)
    lw   t0, 16(s0)
    or  t5, t5, a2
    addi t5, t5, 752
    lhu   a1, 26(s0)
    andi t6, a3, 4
    beqz t6, 143f
    sh   t3, 20(s0)
143:
    lw   a4, 8(s0)
    sb   a2, 24(s0)
    sb   a1, 27(s0)
    lw   a1, 24(s0)
    lbu   t3, 14(s0)
    srl  a2, a2, t4
    addi a2, a2, 1501
    andi t6, t4, 8
    beqz t6, 144f
    lw   t4, 8(s0)
    lbu   a2, 9(s0)
    sb   t4, 10(s0)
144:
    andi t6, a1, 2
    beqz t6, 145f
    sh   t3, 24(s0)
    lbu   a4, 16(s0)
    sb   t3, 0(s0)
145:
    sw   a3, 16(s0)
    sll  t5, t5, a4
    sb   t5, 0(s0)
    add  t0, t0, a3
    andi t6, t1, 8
    beqz t6, 146f
    lbu   t3, 16(s0)
    sb   a4, 4(s0)
146:
    andi t6, t3, 1
    beqz t6, 147f
    lw   t0, 8(s0)
147:
    sb   a4, 5(s0)
    lb   t2, 11(s0)
    sb   t5, 0(s0)
    sb   t4, 27(s0)
    lw   a1, 20(s0)
    sw   t1, 28(s0)
    add  t0, t0, t3
    sb   a4, 6(s0)
    andi t6, a1, 8
    beqz t6, 148f
    sb   t0, 31(s0)
    sh   t3, 26(s0)
    sh   a3, 28(s0)
148:
    lb   a2, 20(s0)
    lb   t1, 7(s0)
    add  a4, a4, t4
    lb   a4, 1(s0)
    sw   t2, 0(s0)
    andi t6, t3, 8
    beqz t6, 149f
    sb   t0, 25(s0)
149:
    lw   t1, 0(s0)
    sb   t3, 14(s0)
    lb   t3, 30(s0)
    add  t4, t4, t5
    lw   t5, 24(s0)
    sh   t0, 18(s0)
    sb   t4, 19(s0)
    lhu   t5, 18(s0)
    andi t6, t1, 8
    beqz t6, 150f
    lbu   a2, 0(s0)
    sw   a2, 16(s0)
150:
    sb   t0, 12(s0)
    sh   t3, 24(s0)
    lw   a1, 28(s0)
    sll  t2, t2, t0
    addi t2, t2, -208
    sh   t4, 22(s0)
    sw   t3, 20(s0)
    sw   a3, 20(s0)
    lw   a1, 20(s0)
    srl  t0, t0, t1
    lw   t2, 8(s0)
    sh   a2, 2(s0)
    lh   t3, 28(s0)
    andi t6, t1, 8
    beqz t6, 151f
    sw   t1, 0(s0)
    lbu   t0, 4(s0)
    lw   a4, 12(s0)
151:
    andi t6, t4, 8
    beqz t6, 152f
    sw   t1, 8(s0)
    sw   t5, 8(s0)
    sb   t3, 5(s0)
152:
    srl  t4, t4, a3
    andi t6, t3, 1
    beqz t6, 153f
    sb   a1, 1(s0)
    lw   t4, 16(s0)
153:
    sw   t3, 8(s0)
    sb   t5, 11(s0)
    sh   a4, 10(s0)
    sh   t4, 10(s0)
    lw   t5, 8(s0)
    lhu   a2, 8(s0)
    xor  a4, a4, t5
    sll  a1, a1, a3
    sb   t4, 23(s0)
    or  t2, t2, t3
    addi t2, t2, 1608
    andi t6, a4, 8
    beqz t6, 154f
    sw   a3, 24(s0)
154:
    or  t3, t3, t4
    add  t5, t5, a4
    addi t5, t5, 489
    lhu   a3, 14(s0)
    lw   t1, 24(s0)
    add  t3, t3, t4
    lb   t5, 29(s0)
    sub  t1, t1, t4
    addi t1, t1, -1402
    or  t2, t2, a1
    addi t2, t2, -2048
    sw   a4, 12(s0)
    lw   t2, 4(s0)
    sll  t4, t4, a4
    addi t4, t4, 515
    andi t6, t3, 16
    beqz t6, 155f
    sw   a2, 24(s0)
    sw   t1, 0(s0)
    lw   t1, 16(s0)
155:
    lhu   t5, 4(s0)
    or  t3, t3, t0
    sw   a2, 0(s0)
    srl  t0, t0, a2
    addi t0, t0, -899
    lw   a1, 12(s0)
    sw   t2, 24(s0)
    sh   t3, 26(s0)
    sw   t5, 24(s0)
    lw   t5, 24(s0)
    andi t6, a1, 8
    beqz t6, 156f
    lbu   t4, 18(s0)
    sh   a2, 14(s0)
    sh   t0, 6(s0)
156:
    andi t6, t4, 1
    beqz t6, 157f
    lw   a4, 8(s0)
    sw   a2, 12(s0)
157:
    lb   t4, 23(s0)
    or  a4, a4, a1
    lb   a3, 2(s0)
    lw   t4, 4(s0)
    sw   a2, 24(s0)
    lhu   a3, 24(s0)
    sw   a3, 20(s0)
    sb   t2, 14(s0)
    sw   a3, 28(s0)
    andi t6, t0, 1
    beqz t6, 158f
    lw   a2, 20(s0)
    lbu   t1, 0(s0)
    sw   a1, 8(s0)
158:
    xor  t5, t5, t4
    addi t5, t5, 882
    sw   t4, 20(s0)
    lw   t0, 8(s0)
    lw   t2, 20(s0)
    lw   t0, 16(s0)
    sw   t1, 0(s0)
    or  t1, t1, t4
    sh   a3, 28(s0)
    lh   a3, 26(s0)
    sh   a4, 14(s0)
    lbu   t0, 30(s0)
    sub  t3, t3, t2
    addi t3, t3, -1669
    sb   a3, 2(s0)
    sw   a2, 0(s0)
    sw   t0, 0(s0)
    lw   t4, 0(s0)
    lb   t3, 29(s0)
    xor  t1, t1, a1
    addi t1, t1, -896
    add  t3, t3, a4
    or  a4, a4, t2
    sh   t0, 24(s0)
    sh   t4, 0(s0)
    sw   t3, 20(s0)
    xor  a2, a2, a2
    addi a2, a2, 135
    lw   t2, 0(s0)
    or  a2, a2, a3
    or  t3, t3, t1
    addi t3, t3, -1525
    lh   a3, 30(s0)
    lb   a4, 21(s0)
    sw   a4, 4(s0)
    sw   t4, 4(s0)
    lw   t1, 4(s0)
    lb   t1, 6(s0)
    lw   a4, 12(s0)
    lw   a3, 20(s0)
    lw   t5, 20(s0)
    sb   t3, 6(s0)
    andi t6, t2, 1
    beqz t6, 159f
    sb   a4, 25(s0)
159:
    sb   t3, 5(s0)
    sb   a4, 29(s0)
    lw   a4, 0(s0)
    sll  t0, t0, a4
    sw   a3, 24(s0)
    sub  a3, a3, t4
    addi a3, a3, 1648
    xor  t1, t1, t2
    lh   a4, 22(s0)
    andi t6, a2, 16
    beqz t6, 160f
    sb   t5, 2(s0)
    sh   t3, 14(s0)
    lw   a3, 24(s0)
160:
    srl  a2, a2, t3
    addi a2, a2, -593
    sb   t2, 3(s0)
    lbu   t2, 26(s0)
    lw   a3, 8(s0)
    sw   t3, 4(s0)
    sw   t0, 20(s0)
    sb   t1, 4(s0)
    sw   t4, 12(s0)
    sb   t5, 12(s0)
    sh   a2, 14(s0)
    sw   t3, 12(s0)
    lb   a2, 12(s0)
    sh   t5, 14(s0)
    lw   t4, 0(s0)
    lbu   t5, 2(s0)
    sub  t2, t2, t3
    sw   t2, 12(s0)
    sw   t5, 4(s0)
    add  a3, a3, t1
    xor  a3, a3, a1
    add  t0, t0, a2
    andi t6, t2, 8
    beqz t6, 161f
    sw   a4, 24(s0)
    lw   a3, 0(s0)
    sw   t0, 16(s0)
161:
    lhu   t0, 30(s0)
    sll  t5, t5, t4
    lh   t0, 22(s0)
    lw   t0, 12(s0)
    lhu   t4, 2(s0)
    andi t6, a4, 1
    beqz t6, 162f
    sh   t0, 20(s0)
162:
    or  a2, a2, t2
    andi t6, t3, 2
    beqz t6, 163f
    sw   t2, 28(s0)
    sb   t3, 28(s0)
163:
    sub  t5, t5, a2
    or  a2, a2, a3
    sw   t0, 4(s0)
    lw   t3, 0(s0)
    sh   t2, 4(s0)
    sb   a2, 5(s0)
    sb   a3, 7(s0)
    lw   a2, 4(s0)
    lhu   t0, 4(s0)
    sb   t0, 22(s0)
    sb   a4, 21(s0)
    lb   t5, 23(s0)
    lhu   t5, 20(s0)
    sll  t3, t3, t2
    lbu   t2, 31(s0)
    lw   t4, 28(s0)
    srl  a1, a1, a3
    sb   t4, 16(s0)
    sw   t5, 16(s0)
    sh   t1, 18(s0)
    lw   t3, 16(s0)
    lw   t4, 16(s0)
    lbu   t3, 29(s0)
    lw   a1, 20(s0)
    lw   a4, 16(s0)
    lb   a1, 31(s0)
    srl  a4, a4, t4
    lw   a1, 24(s0)
    andi t6, a2, 8
    beqz t6, 164f
    lw   t3, 4(s0)
    sb   t5, 24(s0)
164:
    srl  t3, t3, a2
    lh   t0, 2(s0)
    lhu   a3, 28(s0)
    sw   a4, 12(s0)
    sub  t2, t2, t0
    xor  a1, a1, t3
    or  t0, t0, a3
    andi t6, t4, 1
    beqz t6, 165f
    sw   t1, 16(s0)
165:
    sw   t1, 28(s0)
    lhu   a2, 8(s0)
    lw   t0, 24(s0)
    lhu   t4, 14(s0)
    sll  t1, t1, t2
    addi t1, t1, 1447
    lw   t5, 12(s0)
    lbu   t5, 5(s0)
    lh   a4, 20(s0)
    sub  t5, t5, a4
    addi t5, t5, 1286
    lb   a3, 11(s0)
    andi t6, t0, 1
    beqz t6, 166f
    sb   a1, 23(s0)
166:
    lw   t2, 4(s0)
    xor  a3, a3, t0
    lb   a3, 25(s0)
    add  t1, t1, a3
    addi t1, t1, -360
    lb   t5, 4(s0)
    lb   t1, 10(s0)
    sll  a3, a3, a4
    addi a3, a3, -74
    andi t6, a3, 2
    beqz t6, 167f
    sw   t3, 28(s0)
    sb   a4, 5(s0)
167:
    sb   t2, 12(s0)
    andi t6, t2, 16
    beqz t6, 168f
    sh   t0, 22(s0)
    sb   t5, 1(s0)
168:
    andi t6, a1, 4
    beqz t6, 169f
    sh   t0, 12(s0)
169:
    sb   t1, 10(s0)
    sb   t2, 8(s0)
    andi t6, a4, 16
    beqz t6, 170f
    lw   a4, 16(s0)
170:
    sll  t3, t3, a2
    srl  t3, t3, t2
    xor  a1, a1, t0
    add  t3, t3, a3
    lw   t2, 4(s0)
    sb   t5, 3(s0)
    sb   t1, 0(s0)
    sw   a3, 0(s0)
    lb   t1, 2(s0)
    sw   t4, 16(s0)
    sb   t4, 8(s0)
    sb   a3, 10(s0)
    sb   t4, 10(s0)
    lw   t1, 8(s0)
    lhu   t0, 10(s0)
    lb   t1, 29(s0)
    add  a4, a4, t5
    sw   t3, 12(s0)
    add  t5, t5, t3
    sh   t3, 6(s0)
    andi t6, t1, 2
    beqz t6, 171f
    sw   t0, 24(s0)
    sw   t3, 4(s0)
171:
    sub  t0, t0, a1
    addi t0, t0, 294
    add  a1, a1, t4
    andi t6, t0, 1
    beqz t6, 172f
    sh   a2, 12(s0)
    sb   a1, 7(s0)
172:
    sw   a2, 16(s0)
    sw   a2, 16(s0)
    sh   t4, 16(s0)
    sw   t0, 16(s0)
    lhu   t2, 16(s0)
    lw   a1, 16(s0)
    add  a1, a1, a1
    sll  t2, t2, t2
    addi t2, t2, 1658
    lbu   a3, 13(s0)
    lw   a4, 0(s0)
    or  t4, t4, a3
    lw   t0, 4(s0)
    xor  a4, a4, a1
    sb   a1, 29(s0)
    or  t3, t3, a3
    addi t3, t3, -1953
    or  t5, t5, a2
    sh   a1, 8(s0)
    lb   t1, 7(s0)
    lh   t2, 16(s0)
    lb   t2, 28(s0)
    andi t6, a2, 2
    beqz t6, 173f
    lw   t2, 0(s0)
173:
    lb   a3, 7(s0)
    lhu   a3, 4(s0)
    sll  a3, a3, t3
    lhu   t4, 18(s0)
    sh   t5, 24(s0)
    lw   t5, 16(s0)
    lh   t2, 20(s0)
    srl  t4, t4, a2
    lhu   t3, 2(s0)
    sll  t5, t5, t2
    sw   t3, 20(s0)
    sh   t2, 10(s0)
    sw   t5, 8(s0)
    lw   t2, 8(s0)
    lw   t2, 8(s0)
    srl  t0, t0, t2
    lw   a3, 16(s0)
    lb   a2, 17(s0)
    sw   a2, 28(s0)
    or  a2, a2, a2
    addi a2, a2, -155
    sh   a1, 20(s0)
    sb   t1, 15(s0)
    sh   t5, 12(s0)
    sb   a4, 13(s0)
    lw   t2, 12(s0)
    lw   t5, 12(s0)
    lw   t0, 0(s0)
    or  a3, a3, a4
    lh   t0, 26(s0)
    lhu   t3, 30(s0)
    sw   a4, 12(s0)
    srl  a4, a4, t1
    lw   t0, 8(s0)
    lbu   a2, 1(s0)
    xor  t3, t3, a1
    srl  a1, a1, t5
    lw   t1, 12(s0)
    lw   a1, 28(s0)
    add  a4, a4, t1
    sb   t2, 5(s0)
    lbu   a3, 19(s0)
    sw   t3, 24(s0)
    lhu   a1, 18(s0)
    lh   a1, 22(s0)
    lhu   t2, 26(s0)
    andi t6, t0, 8
    beqz t6, 174f
    sh   t0, 2(s0)
    sb   a1, 18(s0)
    sw   t2, 8(s0)
174:
    xor  t5, t5, a2
    sw   t1, 20(s0)
    lb   t5, 20(s0)
    lbu   t3, 11(s0)
    sw   t1, 16(s0)
    sw   t0, 20(s0)
    sub  t1, t1, t4
    srl  a4, a4, t2
    addi a4, a4, 644
    andi t6, t5, 16
    beqz t6, 175f
    sh   a1, 4(s0)
    lw   t4, 4(s0)
175:
    add  t2, t2, a1
    sb   t4, 31(s0)
    srl  t4, t4, a3
    sw   a1, 20(s0)
    lbu   t2, 10(s0)
    lb   t0, 12(s0)
    srl  a3, a3, t3
    lw   t1, 16(s0)
    sw   t2, 0(s0)
    lb   a1, 23(s0)
    sll  t3, t3, t1
    lw   a1, 20(s0)
    lw   a1, 8(s0)
    sh   t0, 4(s0)
    sw   t0, 0(s0)
    lw   t1, 8(s0)
    lh   a1, 6(s0)
    lhu   a2, 18(s0)
    add  t5, t5, a4
    sub  t1, t1, t5
    lb   t5, 18(s0)
    sb   t0, 24(s0)
    sw   t3, 24(s0)
    sb   t2, 27(s0)
    lw   t5, 24(s0)
    or  a4, a4, t3
    lw   t3, 24(s0)
    lw   t5, 16(s0)
    lw   t2, 24(s0)
    andi t6, a2, 16
    beqz t6, 176f
    sh   t0, 28(s0)
    lbu   t4, 7(s0)
    sw   a3, 12(s0)
176:
    or  a4, a4, a2
    lw   t4, 0(s0)
    sll  a3, a3, t2
    addi a3, a3, 991
    sw   a4, 16(s0)
    lb   t3, 29(s0)
    sub  a2, a2, t2
    lw   t1, 0(s0)
    sh   t3, 20(s0)
    lbu   a4, 24(s0)
    lhu   t5, 14(s0)
    or  t4, t4, a1
    addi t4, t4, 1966
    sll  a1, a1, a2
    xor  a1, a1, t2
    lh   t1, 28(s0)
    or  t0, t0, t2
    add  t5, t5, t2
    srl  t5, t5, t4
    sh   a4, 4(s0)
    lbu   a3, 28(s0)
    lbu   a2, 9(s0)
    sub  t4, t4, t3
    sb   t1, 12(s0)
    or  t5, t5, t4
    lh   a4, 28(s0)
    xor  a1, a1, a1
    addi a1, a1, -1729
    xor  t2, t2, a3
    sw   t2, 4(s0)
    lw   a3, 16(s0)
    lhu   a1, 0(s0)
    sub  a2, a2, t1
    addi a2, a2, -1937
    lw   a4, 24(s0)
    sw   a1, 0(s0)
    xor  a1, a1, t1
    lw   t0, 16(s0)
    lw   a1, 20(s0)
    lb   t5, 31(s0)
    lw   t3, 28(s0)
    lhu   a3, 6(s0)
    lhu   t4, 12(s0)
    sll  a2, a2, a4
    add  a1, a1, a1
    addi a1, a1, -1792
    lb   a2, 23(s0)
    lhu   a3, 28(s0)
    andi t6, t1, 8
    beqz t6, 177f
    sh   t3, 18(s0)
    lbu   t2, 16(s0)
177:
    andi t6, a4, 1
    beqz t6, 178f
    lw   a2, 4(s0)
    sw   t2, 28(s0)
178:
    sw   t3, 12(s0)
    lb   t5, 22(s0)
    srl  a3, a3, a4
    lw   a4, 20(s0)
    sll  t5, t5, t2
    srl  t2, t2, t4
    addi t2, t2, 1868
    sll  a2, a2, a1
    andi t6, a2, 1
    beqz t6, 179f
    sb   t5, 13(s0)
    sh   t0, 28(s0)
    sw   t3, 28(s0)
179:
    or  t1, t1, t0
    addi t1, t1, -675
    lhu   t1, 8(s0)
    lw   a2, 16(s0)
    lhu   a4, 0(s0)
    lbu   a2, 8(s0)
    sh   t3, 12(s0)
    sll  a4, a4, t2
    sw   t2, 8(s0)
    lhu   t1, 4(s0)
    xor  t1, t1, a3
    lh   t3, 0(s0)
    andi t6, t2, 1
    beqz t6, 180f
    lw   a4, 28(s0)
180:
    sh   t3, 18(s0)
    sw   a2, 4(s0)
    add  t5, t5, t0
    lw   t1, 16(s0)
    sw   a3, 16(s0)
    lw   t1, 12(s0)
    srl  t4, t4, t2
    addi t4, t4, -644
    sll  t1, t1, a3
    lw   t1, 12(s0)
    sh   t2, 6(s0)
    srl  t5, t5, t5
    srl  t2, t2, t2
    xor  a3, a3, a3
    sw   t0, 16(s0)
    sb   t2, 20(s0)
    sb   t0, 19(s0)
    sub  a2, a2, a2
    lhu   a3, 6(s0)
    sh   a1, 6(s0)
    sh   t2, 2(s0)
    lw   a2, 12(s0)
    andi t6, t1, 8
    beqz t6, 181f
    lw   t2, 28(s0)
181:
    sub  t4, t4, t3
    addi t4, t4, 737
    sh   a1, 30(s0)
    sw   t5, 12(s0)
    sb   t1, 8(s0)
    lh   t1, 6(s0)
    lbu   t2, 10(s0)
    andi t6, t0, 16
    beqz t6, 182f
    sb   a4, 28(s0)
    sw   t1, 8(s0)
    lbu   a3, 24(s0)
182:
    andi t6, t5, 4
    beqz t6, 183f
    sb   t1, 18(s0)
    lw   t3, 28(s0)
    sh   t1, 6(s0)
183:
    or  t4, t4, a2
    lw   t5, 8(s0)
    sw   a2, 24(s0)
    sll  t4, t4, t3
    addi t4, t4, 2025
    sll  t4, t4, a3
    addi t4, t4, -1084
    lhu   t3, 28(s0)
    srl  t1, t1, t1
    sb   t1, 21(s0)
    sw   a2, 20(s0)
    sw   t0, 20(s0)
    lw   t3, 20(s0)
    sw   a4, 16(s0)
    srl  t0, t0, t4
    addi t0, t0, -1218
    sh   t1, 6(s0)
    sh   t3, 6(s0)
    sh   t5, 8(s0)
    sb   t5, 9(s0)
    sh   t5, 10(s0)
    sh   a2, 10(s0)
    lb   a3, 10(s0)
    lhu   t2, 10(s0)
    sw   t5, 8(s0)
    lw   t4, 16(s0)
    sub  t3, t3, t3
    srl  t4, t4, t4
    sub  a2, a2, t0
    lb   t2, 13(s0)
    xor  a3, a3, a3
    addi a3, a3, 699
    sw   t1, 24(s0)
    add  a4, a4, t0
    addi a4, a4, 440
    sb   a3, 2(s0)
    xor  a3, a3, t4
    sw   t3, 28(s0)
    sw   a3, 28(s0)
    sw   t4, 28(s0)
    sb   t5, 30(s0)
    lw   a2, 28(s0)
    lw   t4, 28(s0)
    lhu   a4, 28(s0)
    sub  t2, t2, t5
    add  t4, t4, t0
    addi t4, t4, -767
    lw   t4, 4(s0)
    sh   t0, 4(s0)
    sw   t1, 4(s0)
    sw   t5, 4(s0)
    lhu   a2, 6(s0)
    sw   t3, 0(s0)
    add  t3, t3, t2
    addi t3, t3, 1428
    srl  a4, a4, t3
    addi a4, a4, 1623
    sw   a1, 8(s0)
    sub  t2, t2, t4
    sh   t2, 20(s0)
    xor  t2, t2, t2
    sb   a2, 3(s0)
    sb   a4, 12(s0)
    lhu   a2, 6(s0)
    add  t2, t2, a3
    sb   t1, 2(s0)
    andi t6, t2, 4
    beqz t6, 184f
    sh   t1, 6(s0)
    sb   a2, 1(s0)
184:
    andi t6, t1, 16
    beqz t6, 185f
    sw   a1, 12(s0)
    sb   t1, 29(s0)
    lbu   t2, 19(s0)
185:
    add  t3, t3, a2
    sb   t0, 0(s0)
    sw   t1, 4(s0)
    sb   t4, 18(s0)
    sub  a2, a2, a3
    sb   t0, 12(s0)
    sb   t5, 14(s0)
    sh   a4, 12(s0)
    sw   t5, 12(s0)
    lw   t2, 12(s0)
    lb   a3, 12(s0)
    xor  a4, a4, a1
    sw   a2, 24(s0)
    lbu   t1, 28(s0)
    lh   t1, 16(s0)
    lhu   a1, 16(s0)
    sw   a3, 4(s0)
    sb   t0, 4(s0)
    sw   a2, 4(s0)
    sw   a3, 4(s0)
    lw   a2, 4(s0)
    lw   a1, 4(s0)
    andi t6, a2, 4
    beqz t6, 186f
    sh   t2, 6(s0)
    sb   t5, 26(s0)
186:
    xor  t1, t1, t4
    addi t1, t1, 1778
    lbu   a1, 27(s0)
    lbu   t4, 24(s0)
    sll  t3, t3, t3
    lbu   t2, 17(s0)
    sb   t5, 8(s0)
    sw   a1, 8(s0)
    sb   t1, 10(s0)
    lb   t5, 10(s0)
    or  t2, t2, a2
    lb   a4, 21(s0)
    or  a1, a1, t3
    sw   a1, 20(s0)
    xor  t2, t2, t3
    sh   t5, 0(s0)
    lw   a4, 8(s0)
    sh   a2, 24(s0)
    lhu   t1, 0(s0)
    andi t6, t3, 2
    beqz t6, 187f
    lw   a4, 16(s0)
    lbu   a4, 4(s0)
    sw   t5, 24(s0)
187:
    sub  a2, a2, a1
    addi a2, a2, 1057
    lh   t2, 26(s0)
    sh   t3, 20(s0)
    xor  a3, a3, t2
    lb   a1, 8(s0)
    lhu   t5, 12(s0)
    sb   a4, 30(s0)
    lh   a1, 20(s0)
    sll  t2, t2, t2
    sb   t5, 10(s0)
    lhu   t3, 4(s0)
    lh   a1, 16(s0)
    xor  a1, a1, t5
    xor  a3, a3, t1
    addi a3, a3, -661
    sb   a4, 17(s0)
    lb   a3, 4(s0)
    sh   t1, 22(s0)
    sh   t0, 12(s0)
    lbu   a1, 20(s0)
    or  a3, a3, a4
    sw   t5, 8(s0)
    lhu   a4, 30(s0)
    andi t6, a3, 8
    beqz t6, 188f
    lw   a4, 24(s0)
    lw   t4, 0(s0)
    sb   a4, 11(s0)
188:
    lhu   t2, 16(s0)
    or  a1, a1, t4
    sh   t0, 10(s0)
    sll  t1, t1, t1
    lw   t5, 24(s0)
    or  a2, a2, t2
    addi a2, a2, 422
    lhu   a3, 30(s0)
    sw   t1, 16(s0)
    sb   a2, 26(s0)
    andi t6, a2, 8
    beqz t6, 189f
    lbu   t5, 12(s0)
    sw   t0, 12(s0)
189:
    lhu   a2, 22(s0)
    sll  t2, t2, a2
    lbu   t5, 5(s0)
    sb   t2, 23(s0)
    lbu   t4, 24(s0)
    lw   t2, 20(s0)
    sb   t4, 24(s0)
    lhu   t1, 26(s0)
    sll  t0, t0, t0
    sw   t5, 0(s0)
    lbu   t3, 2(s0)
    lb   t3, 21(s0)
    sub  a2, a2, t4
    lb   t5, 29(s0)
    sh   t3, 10(s0)
    sw   a3, 4(s0)
    xor  t2, t2, a1
    addi t2, t2, -1286
    lbu   t5, 25(s0)
    lw   a2, 16(s0)
    sw   t2, 24(s0)
    sb   t0, 6(s0)
    lw   a4, 28(s0)
    lh   t0, 18(s0)
    srl  t5, t5, a4
    or  t4, t4, a1
    addi t4, t4, -809
    sw   t0, 8(s0)
    lh   t0, 10(s0)
    lw   t1, 20(s0)
    sh   t5, 18(s0)
    sb   t3, 16(s0)
    sh   t5, 16(s0)
    sb   a4, 17(s0)
    lw   t2, 16(s0)
    lhu   t5, 16(s0)
    or  t0, t0, t2
    sub  t0, t0, a3
    sb   a3, 18(s0)
    or  t5, t5, a1
    addi t5, t5, -1
    andi t6, t1, 4
    beqz t6, 190f
    lbu   t4, 9(s0)
190:
    sb   t0, 28(s0)
    sw   a4, 28(s0)
    sh   t4, 28(s0)
    sb   t4, 28(s0)
    lb   t1, 29(s0)
    lw   t3, 28(s0)
    lbu   t1, 27(s0)
    add  a2, a2, a1
    sw   t2, 4(s0)
    lw   a3, 20(s0)
    sh   t4, 2(s0)
    sh   a2, 0(s0)
    sw   a4, 0(s0)
    sw   a4, 0(s0)
    lhu   a1, 2(s0)
    lb   t0, 30(s0)
    andi t6, t4, 16
    beqz t6, 191f
    lw   a1, 8(s0)
191:
    lh   a2, 6(s0)
    lw   a1, 0(s0)
    or  a1, a1, t4
    lhu   t5, 4(s0)
    sll  t2, t2, a4
    andi t6, a2, 2
    beqz t6, 192f
    sh   t5, 2(s0)
    lbu   a3, 20(s0)
    lw   a3, 16(s0)
192:
    sh   a1, 6(s0)
    sh   a4, 22(s0)
    sh   t2, 22(s0)
    sw   t2, 20(s0)
    sw   a2, 20(s0)
    lw   t2, 20(s0)
    xor  a2, a2, t5
    addi a2, a2, 476
    lbu   t5, 9(s0)
    lb   t2, 16(s0)
    sub  t0, t0, t2
    lw   t0, 28(s0)
    sb   t2, 11(s0)
    lh   a1, 2(s0)
    sub  t4, t4, t5
    addi t4, t4, 1329
    sw   a2, 4(s0)
    andi t6, a2, 8
    beqz t6, 193f
    lbu   a2, 24(s0)
193:
    sub  t5, t5, t0
    lw   a1, 4(s0)
    sb   t0, 29(s0)
    sub  t5, t5, t4
    addi t5, t5, 11
    sll  t0, t0, t3
    lbu   t5, 8(s0)
    sb   a1, 22(s0)
    lw   a1, 20(s0)
    sw   t4, 12(s0)
    andi t6, a1, 16
    beqz t6, 194f
    lw   a3, 16(s0)
    lw   a2, 4(s0)
    lbu   t2, 30(s0)
194:
    or  a1, a1, a2
    addi a1, a1, 196
    sub  a1, a1, a3
    srl  t4, t4, a1
    xor  t5, t5, a2
    sw   a1, 24(s0)
    add  a4, a4, a1
    addi a4, a4, -1916
    sub  t1, t1, t5
    andi t6, t2, 2
    beqz t6, 195f
    lbu   t5, 8(s0)
    sw   t0, 20(s0)
    lbu   t0, 9(s0)
195:
    lhu   t0, 6(s0)
    sb   t5, 29(s0)
    sh   t4, 28(s0)
    lhu   t5, 20(s0)
    sw   t2, 20(s0)
    andi t6, a3, 1
    beqz t6, 196f
    lbu   a4, 5(s0)
196:
    srl  t5, t5, a4
    addi t5, t5, -245
    sb   a3, 4(s0)
    sw   t4, 4(s0)
    sh   a1, 6(s0)
    sw   a2, 4(s0)
    lhu   t0, 6(s0)
    lbu   t0, 25(s0)
    lhu   a4, 20(s0)
    andi t6, t0, 4
    beqz t6, 197f
    lbu   t3, 23(s0)
197:
    sh   t3, 22(s0)
    lh   t3, 6(s0)
    or  t3, t3, a2
    addi t3, t3, 553
    andi t6, a3, 1
    beqz t6, 198f
    lbu   t3, 2(s0)
198:
    lbu   t3, 6(s0)
    sh   a4, 12(s0)
    sll  t0, t0, a2
    lw   t5, 8(s0)
    sb   t3, 30(s0)
    sh   t3, 30(s0)
    sb   a1, 28(s0)
    sw   t3, 28(s0)
    lw   t0, 28(s0)
    xor  t3, t3, a4
    sw   a1, 12(s0)
    lh   t0, 10(s0)
    lh   t5, 20(s0)
    sw   a2, 24(s0)
    or  a2, a2, a3
    andi t6, t1, 4
    beqz t6, 199f
    sb   a4, 30(s0)
    lw   a3, 4(s0)
199:
    sw   a1, 0(s0)
    sh   a2, 0(s0)
    lhu   t4, 0(s0)
    sub  a4, a4, t3
    sub  t5, t5, t0
    addi t5, t5, 1982
    lh   t5, 10(s0)
    andi t6, a3, 2
    beqz t6, 1100f
    lw   a2, 4(s0)
    lbu   t4, 24(s0)
    sh   t1, 14(s0)
1100:
    or  t3, t3, t4
    lw   t2, 0(s0)
    sw   t4, 28(s0)
    add  t2, t2, a4
    lb   t4, 18(s0)
    sw   t3, 20(s0)
    sll  a1, a1, a4
    xor  a2, a2, t1
    sb   a3, 11(s0)
    lb   t3, 4(s0)
    sh   t4, 28(s0)
    xor  t4, t4, a2
    sub  a4, a4, t3
    or  t5, t5, t4
    lw   a3, 4(s0)
    add  t0, t0, t5
    addi t0, t0, 23
    sll  t5, t5, a1
    lw   a1, 24(s0)
    sw   a1, 24(s0)
    lw   t1, 12(s0)
    lw   a1, 28(s0)
    lw   a1, 4(s0)
    sw   t5, 28(s0)
    sw   a1, 28(s0)
    lhu   t2, 30(s0)
    lhu   t0, 28(s0)
    lbu   t1, 24(s0)
    lw   t5, 4(s0)
    srl  t2, t2, t0
    lhu   t2, 30(s0)
    lw   a3, 4(s0)
    or  t1, t1, t1
    xor  a1, a1, a1
    sub  t3, t3, t4
    addi t3, t3, -171
    lh   t1, 26(s0)
    andi t6, t1, 4
    beqz t6, 1101f
    lw   t2, 28(s0)
    sw   t4, 0(s0)
1101:
    xor  a1, a1, a2
    sub  t5, t5, t1
    addi t5, t5, -1822
    sub  t5, t5, a1
    sw   a4, 28(s0)
    sb   a3, 18(s0)
    sub  a4, a4, t1
    sw   a3, 12(s0)
    sh   a3, 14(s0)
    sb   t3, 12(s0)
    lw   t1, 12(s0)
    lhu   t1, 14(s0)
    sub  a3, a3, a2
    addi a3, a3, 860
    add  t3, t3, a3
    sh   t2, 4(s0)
    sw   t1, 20(s0)
    lhu   t4, 28(s0)
    srl  t5, t5, t0
    sb   t2, 15(s0)
    lw   t4, 28(s0)
    sll  t5, t5, a3
    andi t6, t0, 2
    beqz t6, 1102f
    lbu   t0, 25(s0)
    sb   a4, 11(s0)
    sb   t1, 19(s0)
1102:
    lw   a1, 20(s0)
    xor  t5, t5, t0
    lb   t1, 12(s0)
    sw   t2, 8(s0)
    sh   t5, 10(s0)
    sw   t2, 8(s0)
    lw   a4, 8(s0)
    lw   a3, 8(s0)
    andi t6, t3, 8
    beqz t6, 1103f
    sh   a3, 2(s0)
    lbu   t3, 27(s0)
    lw   a2, 24(s0)
1103:
    sw   a4, 4(s0)
    sub  a3, a3, t1
    andi t6, a2, 2
    beqz t6, 1104f
    sw   t2, 4(s0)
    lw   a2, 4(s0)
1104:
    lh   t1, 30(s0)
    or  t3, t3, t1
    sll  t2, t2, t0
    lhu   t5, 22(s0)
    lhu   a2, 12(s0)
    sw   t2, 24(s0)
    lh   t5, 20(s0)
    lw   t4, 4(s0)
    sw   a3, 0(s0)
    lw   t0, 4(s0)
    add  a1, a1, t2
    sh   t5, 14(s0)
    sh   t5, 16(s0)
    sub  t3, t3, t2
    sw   t2, 8(s0)
    sb   t5, 14(s0)
    sll  t2, t2, a3
    or  t4, t4, t3
    lhu   a1, 18(s0)
    lb   t0, 25(s0)
    xor  t4, t4, t1
    lb   t0, 7(s0)
    sll  t0, t0, t4
    lh   a4, 14(s0)
    lb   t4, 14(s0)
    xor  t0, t0, a4
    lbu   a2, 23(s0)
    sw   t0, 20(s0)
    lhu   t3, 22(s0)
    or  a4, a4, a2
    add  a4, a4, t4
    lb   t2, 0(s0)
    srl  t5, t5, a2
    lb   t2, 5(s0)
    lbu   t4, 3(s0)
    lbu   a3, 3(s0)
    sw   a1, 4(s0)
    lw   a4, 4(s0)
    lbu   t1, 3(s0)
    lw   t3, 12(s0)
    lb   a1, 15(s0)
    andi t6, t2, 1
    beqz t6, 1105f
    sb   t3, 18(s0)
    lw   a1, 16(s0)
1105:
    sb   t3, 20(s0)
    lbu   t0, 5(s0)
    add  a1, a1, t2
    sh   t2, 18(s0)
    sw   t4, 28(s0)
    srl  t5, t5, a2
    addi t5, t5, 1448
    sw   t4, 20(s0)
    xor  t4, t4, t3
    addi t4, t4, 290
    sll  t3, t3, t4
    andi t6, a2, 8
    beqz t6, 1106f
    sb   a2, 5(s0)
    sb   a1, 4(s0)
    sb   t1, 27(s0)
1106:
    andi t6, a4, 1
    beqz t6, 1107f
    sw   t1, 0(s0)
1107:
    lbu   a2, 0(s0)
    srl  a4, a4, t1
    addi a4, a4, -1834
    lw   t1, 4(s0)
    andi t6, a4, 16
    beqz t6, 1108f
    sh   t3, 18(s0)
    sw   a3, 28(s0)
    sh   t5, 16(s0)
1108:
    andi t6, t2, 4
    beqz t6, 1109f
    lw   a3, 8(s0)
    sb   a2, 27(s0)
    lbu   a4, 31(s0)
1109:
    lhu   t1, 20(s0)
    lw   a1, 12(s0)
    lhu   a2, 2(s0)
    add  a2, a2, a3
    addi a2, a2, -371
    sb   a4, 14(s0)
    lbu   t5, 21(s0)
    sb   t4, 4(s0)
    lw   t5, 24(s0)
    sw   t2, 12(s0)
    lb   a2, 29(s0)
    lbu   a3, 2(s0)
    sll  t3, t3, t3
    lbu   t3, 3(s0)
    sh   a3, 14(s0)
    add  a2, a2, t1
    addi a2, a2, 604
    sw   t5, 12(s0)
    sw   a3, 0(s0)
    andi t6, t1, 2
    beqz t6, 1110f
    sb   t5, 23(s0)
    sw   t0, 20(s0)
1110:
    andi t6, t5, 8
    beqz t6, 1111f
    sb   t4, 4(s0)
    lbu   a3, 21(s0)
1111:
    lw   a3, 16(s0)
    andi t6, a4, 1
    beqz t6, 1112f
    sw   a2, 24(s0)
1112:
    lw   a2, 0(s0)
    andi t6, a1, 1
    beqz t6, 1113f
    lw   t5, 8(s0)
    sw   t3, 0(s0)
    sh   t3, 6(s0)
1113:
    sb   a3, 6(s0)
    andi t6, a4, 16
    beqz t6, 1114f
    sb   a1, 6(s0)
1114:
    lb   a2, 10(s0)
    sh   t5, 6(s0)
    add  t3, t3, t1
    sw   a4, 20(s0)
    lh   a4, 16(s0)
    andi t6, t2, 8
    beqz t6, 1115f
    sh   a1, 16(s0)
1115:
    or  t2, t2, t5
    lb   a2, 20(s0)
    sh   t1, 20(s0)
    sub  a3, a3, a3
    addi a3, a3, 531
    lbu   a1, 20(s0)
    sw   a2, 0(s0)
    lw   a3, 20(s0)
    sub  a4, a4, a2
    sb   a3, 2(s0)
    lbu   t4, 5(s0)
    sh   t2, 10(s0)
    lh   t1, 0(s0)
    sh   a1, 16(s0)
    srl  t2, t2, t5
    lw   t4, 20(s0)
    add  t2, t2, a3
    lb   t1, 28(s0)
    sw   t4, 8(s0)
    lw   t2, 12(s0)
    sw   a2, 8(s0)
    lw   a2, 16(s0)
    sh   a4, 20(s0)
    sb   t2, 23(s0)
    sw   a1, 20(s0)
    lw   t5, 20(s0)
    lhu   a1, 22(s0)
    sh   t0, 4(s0)
    sb   a4, 5(s0)
    sw   t4, 4(s0)
    lw   a2, 4(s0)
    lhu   a4, 4(s0)
    lhu   a3, 0(s0)
    or  t1, t1, a4
    addi t1, t1, 788
    lw   t2, 4(s0)
    sb   t0, 20(s0)
    sh   a2, 8(s0)
    sw   a4, 12(s0)
    lbu   t2, 0(s0)
    sw   a4, 12(s0)
    sll  t0, t0, t1
    lbu   t1, 19(s0)
    sh   t2, 30(s0)
    sw   t3, 28(s0)
    sh   t4, 28(s0)
    lw   a1, 28(s0)
    lhu   a3, 30(s0)
    lhu   a1, 24(s0)
    sll  a2, a2, t0
    lw   a3, 8(s0)
    sh   a2, 0(s0)
    or  t3, t3, a1
    sw   t4, 8(s0)
    lhu   a3, 6(s0)
    sb   a2, 15(s0)
    sh   a4, 12(s0)
    sw   a4, 12(s0)
    lb   t3, 13(s0)
    xor  t5, t5, t4
    addi t5, t5, 546
    lbu   t3, 1(s0)
    srl  a1, a1, a4
    sw   t5, 28(s0)
    lbu   t5, 3(s0)
    sll  t5, t5, t5
    lh   t2, 2(s0)
    sh   t2, 30(s0)
    sw   a2, 28(s0)
    sh   a3, 28(s0)
    lb   t4, 30(s0)
    sw   t2, 4(s0)
    sh   a1, 10(s0)
    lw   t2, 28(s0)
    sb   t0, 15(s0)
    sb   t3, 13(s0)
    sb   a3, 14(s0)
    lhu   t4, 12(s0)
    sw   t3, 20(s0)
    lw   t4, 8(s0)
    srl  t3, t3, a1
    sw   t3, 0(s0)
    sw   t4, 8(s0)
    sub  a4, a4, t3
    sh   t4, 16(s0)
    sw   t5, 16(s0)
    lw   a3, 16(s0)
    lw   t1, 16(s0)
    add  a4, a4, a4
    lh   t3, 30(s0)
    xor  t3, t3, t5
    sll  t1, t1, a3
    lhu   t2, 10(s0)
    lbu   a2, 12(s0)
    sh   t2, 20(s0)
    lw   a2, 4(s0)
    lb   t1, 26(s0)
    srl  a2, a2, t3
    lh   t1, 26(s0)
    sb   t1, 25(s0)
    or  t5, t5, t2
    lw   t3, 4(s0)
    srl  t1, t1, t3
    srl  t0, t0, t1
    sw   t3, 28(s0)
    sw   t0, 28(s0)
    sh   a4, 28(s0)
    lw   t4, 28(s0)
    lw   a2, 28(s0)
    sw   a4, 20(s0)
    lb   a4, 30(s0)
    lw   t5, 8(s0)
    andi t6, t3, 1
    beqz t6, 1116f
    lbu   a3, 10(s0)
    lw   a1, 28(s0)
1116:
    sh   a2, 4(s0)
    lh   t5, 22(s0)
    lb   t3, 15(s0)
    sb   t5, 18(s0)
    xor  a4, a4, t1
    sub  a4, a4, t0
    sh   t2, 30(s0)
    sh   a1, 16(s0)
    sll  t0, t0, a2
    sll  t0, t0, t3
    lbu   t2, 3(s0)
    lw   a3, 24(s0)
    sw   t3, 0(s0)
    sw   a1, 0(s0)
    lhu   a2, 2(s0)
    lw   t3, 0(s0)
    andi t6, t5, 4
    beqz t6, 1117f
    lw   t5, 28(s0)
    lbu   a3, 30(s0)
    lbu   a2, 22(s0)
1117:
    add  t0, t0, a1
    addi t0, t0, -328
    xor  t2, t2, t0
    sub  a4, a4, t1
    addi a4, a4, -722
    sw   t1, 16(s0)
    lbu   t0, 4(s0)
    sh   t3, 30(s0)
    sh   a1, 30(s0)
    lhu   t3, 30(s0)
    sw   a1, 28(s0)
    or  t2, t2, t4
    addi t2, t2, 1759
    lbu   t0, 12(s0)
    lw   t2, 20(s0)
    sh   a4, 22(s0)
    sll  t5, t5, t2
    sll  t2, t2, a2
    sh   t4, 16(s0)
    lb   a4, 29(s0)
    add  t3, t3, t1
    xor  t2, t2, a3
    addi t2, t2, 947
    lb   t0, 0(s0)
    sw   a2, 24(s0)
    sub  t0, t0, t2
    addi t0, t0, -303
    srl  a1, a1, a1
    srl  a2, a2, t3
    sw   t2, 0(s0)
    sb   t0, 29(s0)
    sh   t1, 0(s0)
    srl  t0, t0, a1
    lhu   t4, 24(s0)
    add  t4, t4, t2
    sb   t0, 20(s0)
    sh   a4, 20(s0)
    lhu   t0, 22(s0)
    srl  t1, t1, t4
    lw   a2, 0(s0)
    sub  t3, t3, a4
    addi t3, t3, 698
    sw   t2, 24(s0)
    lbu   t1, 10(s0)
    sw   t5, 0(s0)
    sb   t2, 13(s0)
    lw   a3, 8(s0)
    or  a1, a1, t3
    addi a1, a1, 2041
    sh   t5, 28(s0)
    sll  a1, a1, a2
    addi a1, a1, 178
    sw   t3, 8(s0)
    add  t4, t4, t2
    lh   t1, 16(s0)
    sw   t5, 0(s0)
    andi t6, a3, 1
    beqz t6, 1118f
    lw   a3, 0(s0)
    sb   t4, 11(s0)
1118:
    sw   t4, 8(s0)
    sw   t3, 28(s0)
    sb   a3, 25(s0)
    sw   t1, 24(s0)
    lw   t4, 24(s0)
    sub  a1, a1, t5
    lbu   a4, 2(s0)
    sw   t5, 24(s0)
    andi t6, t0, 8
    beqz t6, 1119f
    lw   t4, 24(s0)
    lw   a4, 8(s0)
    sw   t4, 28(s0)
1119:
    lhu   t4, 24(s0)
    sll  t1, t1, a1
    addi t1, t1, -7
    srl  t4, t4, a2
    addi t4, t4, -1868
    srl  t0, t0, t0
    lb   t1, 26(s0)
    sb   a1, 19(s0)
    sh   t3, 18(s0)
    sh   t5, 16(s0)
    sh   t2, 16(s0)
    lb   t0, 18(s0)
    lw   t4, 16(s0)
    lw   t5, 12(s0)
    lw   t2, 12(s0)
    sh   t3, 10(s0)
    lw   a2, 24(s0)
    sub  a2, a2, a1
    lhu   t1, 20(s0)
    sb   t1, 22(s0)
    andi t6, t4, 4
    beqz t6, 1120f
    sw   a1, 28(s0)
    sh   t1, 0(s0)
    lbu   a1, 0(s0)
1120:
    sw   t3, 12(s0)
    or  a3, a3, t5
    sub  t3, t3, t2
    lw   a3, 28(s0)
    lh   t1, 30(s0)
    lw   t0, 0(s0)
    sub  t4, t4, t5
    sh   t0, 2(s0)
    sb   t0, 3(s0)
    lhu   t4, 2(s0)
    lhu   a2, 2(s0)
    lbu   t3, 3(s0)
    lbu   a1, 18(s0)
    andi t6, a3, 1
    beqz t6, 1121f
    lw   t1, 20(s0)
    sw   a2, 24(s0)
1121:
    or  t1, t1, a2
    addi t1, t1, -941
    lw   t5, 28(s0)
    xor  t5, t5, a4
    sub  t5, t5, t5
    lh   a2, 18(s0)
    lw   t2, 4(s0)
    lw   t0, 4(s0)
    lw   t1, 4(s0)
    sh   a2, 2(s0)
    sb   t4, 0(s0)
    sw   t2, 0(s0)
    sh   a3, 0(s0)
    lhu   t0, 2(s0)
    sub  t4, t4, t1
    lbu   a3, 21(s0)
    sw   t3, 4(s0)
    sh   a4, 4(s0)
    sh   t4, 6(s0)
    lhu   a1, 6(s0)
    lhu   a4, 4(s0)
    lbu   t1, 0(s0)
    sll  t4, t4, t5
    lw   a3, 8(s0)
    sub  a3, a3, t2
    sll  a1, a1, a1
    sll  t4, t4, t1
    sb   a2, 2(s0)
    sh   a3, 8(s0)
    sh   t5, 10(s0)
    sb   a1, 11(s0)
    sw   a3, 8(s0)
    lb   t5, 8(s0)
    lb   t2, 31(s0)
    add  t4, t4, t5
    or  t2, t2, a2
    addi t2, t2, -1655
    sub  t4, t4, a4
    xor  a2, a2, a2
    addi a2, a2, 784
    lbu   t5, 0(s0)
    srl  a3, a3, t0
    lhu   t5, 8(s0)
    lw   a3, 0(s0)
    add  t1, t1, a2
    sh   t0, 0(s0)
    andi t6, a4, 1
    beqz t6, 1122f
    lw   a1, 0(s0)
    lbu   a1, 17(s0)
1122:
    lhu   a3, 0(s0)
    sw   a4, 12(s0)
    sw   a2, 20(s0)
    sll  t4, t4, t4
    andi t6, t4, 2
    beqz t6, 1123f
    lbu   a3, 24(s0)
    sb   t0, 23(s0)
    sb   a3, 0(s0)
1123:
    sll  t2, t2, a3
    sh   t2, 16(s0)
    or  t4, t4, t1
    add  a2, a2, a2
    andi t6, t5, 16
    beqz t6, 1124f
    sw   a3, 20(s0)
    sh   t5, 6(s0)
    sw   a1, 28(s0)
1124:
    sw   a4, 24(s0)
    sw   a1, 16(s0)
    sw   t3, 4(s0)
    sw   a2, 8(s0)
    add  a2, a2, t5
    addi a2, a2, 1187
    andi t6, t0, 2
    beqz t6, 1125f
    sw   a3, 4(s0)
1125:
    lhu   t1, 8(s0)
    andi t6, t5, 1
    beqz t6, 1126f
    sw   t1, 0(s0)
1126:
    lb   t3, 28(s0)
    xor  a3, a3, a4
    lw   a1, 12(s0)
    lh   t3, 14(s0)
    sw   t4, 8(s0)
    or  a3, a3, t0
    lw   a1, 28(s0)
    lw   a3, 12(s0)
    sw   t1, 16(s0)
    lbu   a2, 5(s0)
    or  a4, a4, t2
    sw   a1, 0(s0)
    sh   t2, 2(s0)
    lw   t4, 0(s0)
    xor  t1, t1, a3
    lw   t0, 4(s0)
    sub  t4, t4, t0
    add  a2, a2, t4
    addi a2, a2, 1897
    xor  t2, t2, a3
    sb   t3, 21(s0)
    sw   a4, 12(s0)
    sb   t3, 5(s0)
    lhu   a1, 18(s0)
    srl  t4, t4, t0
    sw   a2, 4(s0)
    sll  a3, a3, t5
    sw   t0, 24(s0)
    lhu   a1, 14(s0)
    sw   t3, 4(s0)
    sh   t5, 4(s0)
    lw   a3, 4(s0)
    andi t6, t5, 2
    beqz t6, 1127f
    sh   t4, 18(s0)
    sw   t3, 12(s0)
    sb   t1, 6(s0)
1127:
    lhu   t5, 30(s0)
    add  a1, a1, t0
    sw   t5, 0(s0)
    sll  t1, t1, t4
    add  a3, a3, t4
    sh   t0, 8(s0)
    or  a4, a4, t2
    lw   t0, 24(s0)
    sb   a4, 26(s0)
    lb   t0, 1(s0)
    add  t4, t4, a2
    addi t4, t4, -549
    sw   a3, 0(s0)
    xor  a2, a2, t3
    or  a4, a4, t2
    sll  t2, t2, t5
    addi t2, t2, 51
    sb   a3, 5(s0)
    xor  a1, a1, t1
    andi t6, a2, 16
    beqz t6, 1128f
    lbu   t3, 27(s0)
    sb   t4, 16(s0)
1128:
    sb   a4, 27(s0)
    lw   a1, 24(s0)
    lbu   t3, 21(s0)
    lb   t2, 28(s0)
    lw   t0, 4(s0)
    lb   a4, 30(s0)
    sh   a1, 26(s0)
    sw   a3, 24(s0)
    lw   a4, 24(s0)
    srl  t5, t5, t2
    addi t5, t5, 1969
    xor  t3, t3, t4
    lbu   t0, 16(s0)
    sll  t3, t3, t2
    lw   t3, 4(s0)
    sw   a3, 20(s0)
    sh   t5, 20(s0)
    sw   t4, 20(s0)
    sb   a4, 20(s0)
    sh   a2, 22(s0)
    lw   t1, 20(s0)
    lhu   t4, 20(s0)
    xor  t2, t2, t5
    addi t2, t2, 1528
    lw   t4, 28(s0)
    or  a2, a2, t2
    andi t6, a2, 2
    beqz t6, 1129f
    sb   a4, 2(s0)
    sh   t4, 16(s0)
1129:
    add  a4, a4, t5
    addi a4, a4, -1680
    andi t6, a3, 1
    beqz t6, 1130f
    lw   t3, 28(s0)
1130:
    or  t3, t3, a1
    andi t6, t3, 2
    beqz t6, 1131f
    sw   a3, 16(s0)
    lw   t3, 4(s0)
1131:
    lh   t3, 26(s0)
    sw   a4, 0(s0)
    andi t6, t3, 1
    beqz t6, 1132f
    lw   a4, 8(s0)
    sw   t1, 0(s0)
    sb   t0, 6(s0)
1132:
    lh   t0, 22(s0)
    lb   a4, 5(s0)
    andi t6, t3, 2
    beqz t6, 1133f
    sb   t4, 14(s0)
1133:
    sb   a2, 12(s0)
    sb   t3, 15(s0)
    lhu   a1, 12(s0)
    sb   a2, 27(s0)
    andi t6, t3, 8
    beqz t6, 1134f
    sw   a2, 0(s0)
    lw   t5, 20(s0)
1134:
    add  a2, a2, a1
    addi a2, a2, -1834
    sh   t5, 12(s0)
    sb   a3, 14(s0)
    sh   t4, 12(s0)
    lb   t1, 15(s0)
    lb   a1, 21(s0)
    lb   t3, 19(s0)
    add  t0, t0, t2
    sw   t4, 0(s0)
    sll  t2, t2, t1
    andi t6, t4, 4
    beqz t6, 1135f
    sw   a3, 0(s0)
1135:
    sll  t5, t5, t0
    lh   t2, 14(s0)
    lbu   t4, 5(s0)
    sw   t1, 20(s0)
    sw   t4, 20(s0)
    lhu   a2, 20(s0)
    andi t6, t3, 16
    beqz t6, 1136f
    lw   t2, 4(s0)
1136:
    sll  t3, t3, t1
    andi t6, t3, 8
    beqz t6, 1137f
    lbu   t0, 13(s0)
    lbu   a3, 27(s0)
    sh   a2, 22(s0)
1137:
    add  a4, a4, t3
    lw   a3, 28(s0)
    andi t6, a1, 1
    beqz t6, 1138f
    lbu   t3, 28(s0)
    sw   t3, 24(s0)
1138:
    xor  a1, a1, t0
    lb   t2, 29(s0)
    sll  t2, t2, a3
    sw   t0, 28(s0)
    add  t3, t3, t0
    addi t3, t3, -588
    lhu   a3, 20(s0)
    lh   t4, 24(s0)
    sw   a2, 16(s0)
    andi t6, a4, 16
    beqz t6, 1139f
    lw   a3, 28(s0)
    sb   t4, 6(s0)
1139:
    lw   t4, 8(s0)
    andi t6, a1, 1
    beqz t6, 1140f
    lw   t1, 12(s0)
1140:
    lw   t4, 20(s0)
    srl  a1, a1, a4
    sb   t1, 7(s0)
    lw   t3, 20(s0)
    lb   t2, 16(s0)
    sh   a3, 20(s0)
    sb   t2, 12(s0)
    sb   t4, 7(s0)
    sb   a2, 6(s0)
    sb   t0, 6(s0)
    sw   t3, 4(s0)
    lhu   t4, 6(s0)
    sw   t2, 20(s0)
    sh   t1, 8(s0)
    lb   t2, 0(s0)
    andi t6, a3, 2
    beqz t6, 1141f
    sh   t1, 10(s0)
    sh   a2, 2(s0)
    lw   t3, 8(s0)
1141:
    sll  t1, t1, a3
    lh   t4, 10(s0)
    sw   a1, 28(s0)
    or  t3, t3, t1
    sb   t4, 21(s0)
    or  a2, a2, a2
    addi a2, a2, 492
    lh   t4, 24(s0)
    lhu   t4, 8(s0)
    andi t6, t0, 4
    beqz t6, 1142f
    lw   t2, 8(s0)
1142:
    lw   t5, 4(s0)
    sh   t0, 28(s0)
    lbu   t3, 13(s0)
    sh   t0, 0(s0)
    sw   t5, 0(s0)
    sh   a1, 0(s0)
    sh   a1, 0(s0)
    lw   t4, 0(s0)
    lb   t0, 3(s0)
    sb   a2, 30(s0)
    sh   t4, 20(s0)
    sw   t3, 24(s0)
    sh   t5, 16(s0)
    sw   a3, 8(s0)
    xor  t2, t2, t2
    add  a2, a2, t3
    add  a4, a4, a3
    lb   a3, 13(s0)
    lw   a3, 4(s0)
    lw   t3, 24(s0)
    lw   t1, 8(s0)
    sw   a3, 0(s0)
    sub  a4, a4, a1
    sub  t4, t4, t5
    lhu   t4, 26(s0)
    sw   a1, 8(s0)
    sb   t0, 9(s0)
    lhu   t2, 8(s0)
    lhu   t4, 10(s0)
    lw   t3, 20(s0)
    sw   t5, 20(s0)
    lb   t0, 31(s0)
    lw   a1, 16(s0)
    add  t0, t0, a4
    addi t0, t0, -1089
    sw   a2, 12(s0)
    sh   a1, 4(s0)
    sb   a1, 9(s0)
    sb   a1, 8(s0)
    sb   a1, 9(s0)
    sw   a3, 8(s0)
    lb   t4, 11(s0)
    lbu   a2, 3(s0)
    srl  a2, a2, t1
    addi a2, a2, -1843
    lw   t2, 20(s0)
    sb   t5, 22(s0)
    sw   a2, 0(s0)
    lhu   t1, 18(s0)
    lw   a4, 8(s0)
    lbu   a3, 23(s0)
    srl  t0, t0, t2
    srl  a2, a2, t3
    addi a2, a2, 303
    andi t6, a2, 8
    beqz t6, 1143f
    sb   t1, 12(s0)
    lw   t3, 4(s0)
1143:
    lbu   a1, 0(s0)
    lhu   t1, 22(s0)
    add  a1, a1, a3
    lb   a1, 24(s0)
    sh   t0, 16(s0)
    sw   a4, 16(s0)
    lw   t1, 16(s0)
    sw   a3, 16(s0)
    sh   t0, 18(s0)
    sb   t1, 18(s0)
    lb   a2, 17(s0)
    lhu   t4, 16(s0)
    sh   t1, 8(s0)
    andi t6, t0, 8
    beqz t6, 1144f
    sb   t3, 5(s0)
    lbu   t3, 9(s0)
1144:
    sh   t2, 26(s0)
    sh   a2, 16(s0)
    sb   a3, 27(s0)
    xor  t1, t1, a4
    addi t1, t1, -928
    lhu   a4, 6(s0)
    sh   a3, 20(s0)
    sh   t0, 20(s0)
    lb   a1, 21(s0)
    sw   t1, 16(s0)
    or  t1, t1, t2
    addi t1, t1, 1617
    add  t3, t3, t1
    sll  t0, t0, t0
    addi t0, t0, -693
    lh   t1, 8(s0)
    sw   a4, 12(s0)
    or  t5, t5, t2
    lb   t5, 5(s0)
    sw   t5, 20(s0)
    lw   t2, 8(s0)
    add  a2, a2, t3
    lhu   t3, 26(s0)
    or  t2, t2, t5
    sw   t3, 12(s0)
    lw   t3, 16(s0)
    sw   t3, 16(s0)
    lh   t3, 8(s0)
    sw   a4, 12(s0)
    sb   a1, 12(s0)
    sb   a3, 15(s0)
    sh   a1, 12(s0)
    lhu   a2, 12(s0)
    lhu   a2, 12(s0)
    or  a3, a3, t2
    sh   a3, 12(s0)
    lw   a4, 16(s0)
    sh   t4, 22(s0)
    lbu   t0, 26(s0)
    lhu   a1, 0(s0)
    lb   t2, 0(s0)
    lhu   t3, 24(s0)
    or  t3, t3, t4
    lb   t3, 29(s0)
    sll  a3, a3, a3
    sw   t1, 0(s0)
    add  t4, t4, t2
    lbu   t2, 29(s0)
    andi t6, a4, 16
    beqz t6, 1145f
    sh   t4, 8(s0)
    sw   t3, 20(s0)
1145:
    sh   t3, 2(s0)
    sub  a2, a2, a1
    lbu   t5, 23(s0)
    lhu   t2, 20(s0)
    sub  t3, t3, a3
    sll  t0, t0, a2
    sh   t5, 26(s0)
    or  t3, t3, t0
    add  a4, a4, a2
    addi a4, a4, 1717
    lb   t5, 24(s0)
    xor  t3, t3, t5
    andi t6, a4, 4
    beqz t6, 1146f
    sw   t4, 0(s0)
    sw   a2, 4(s0)
1146:
    lhu   a2, 14(s0)
    xor  t0, t0, t5
    addi t0, t0, 806
    srl  a3, a3, t2
    sw   a4, 8(s0)
    sw   a3, 28(s0)
    sh   t5, 30(s0)
    lb   t3, 29(s0)
    lw   a4, 28(s0)
    andi t6, t5, 1
    beqz t6, 1147f
    sb   a4, 23(s0)
    sb   t5, 29(s0)
    sh   t4, 26(s0)
1147:
    lbu   t2, 3(s0)
    andi t6, t2, 2
    beqz t6, 1148f
    sb   t5, 22(s0)
    lbu   t0, 15(s0)
1148:
    lhu   a1, 10(s0)
    sll  a3, a3, t4
    sb   a3, 2(s0)
    sw   t4, 0(s0)
    sh   a4, 0(s0)
    lhu   t1, 2(s0)
    lw   a4, 0(s0)
    sw   t3, 4(s0)
    andi t6, t5, 4
    beqz t6, 1149f
    sh   t1, 12(s0)
    sw   a1, 16(s0)
1149:
    srl  a4, a4, t0
    sub  a2, a2, a4
    xor  a3, a3, t0
    addi a3, a3, 1067
    sw   a1, 4(s0)
    sb   a3, 4(s0)
    sb   a1, 6(s0)
    sh   a2, 6(s0)
    lw   t5, 4(s0)
    sw   a3, 24(s0)
    lhu   t1, 16(s0)
    or  t2, t2, a3
    lbu   t1, 8(s0)
    lhu   a4, 16(s0)
    add  t1, t1, t4
    sll  a4, a4, t1
    addi a4, a4, 202
    sh   t0, 8(s0)
    lb   a3, 19(s0)
    lw   a3, 12(s0)
    add  t3, t3, t2
    lbu   t4, 27(s0)
    sw   t4, 8(s0)
    sb   t4, 29(s0)
    lhu   t4, 10(s0)
    andi t6, a1, 4
    beqz t6, 1150f
    lbu   a3, 10(s0)
    sb   t5, 1(s0)
1150:
    andi t6, t3, 16
    beqz t6, 1151f
    sh   a1, 8(s0)
    sh   a3, 10(s0)
    lw   t4, 4(s0)
1151:
    lh   a3, 24(s0)
    lh   a2, 4(s0)
    lh   t5, 22(s0)
    sb   a2, 7(s0)
    xor  t1, t1, t2
    lhu   t4, 28(s0)
    andi t6, a4, 1
    beqz t6, 1152f
    lw   a1, 24(s0)
    lw   a4, 4(s0)
    sw   t4, 16(s0)
1152:
    srl  a2, a2, t5
    xor  a3, a3, t5
    addi a3, a3, -1168
    sw   t4, 8(s0)
    add  t4, t4, a1
    sh   t3, 14(s0)
    srl  a2, a2, a4
    lbu   a3, 22(s0)
    lw   t4, 24(s0)
    sw   t2, 20(s0)
    or  a1, a1, t5
    andi t6, t3, 4
    beqz t6, 1153f
    lbu   a3, 25(s0)
1153:
    sw   t2, 4(s0)
    sw   t3, 4(s0)
    sw   t0, 4(s0)
    lhu   a2, 6(s0)
    lw   t0, 4(s0)
    lb   t2, 13(s0)
    andi t6, a1, 1
    beqz t6, 1154f
    lbu   a2, 5(s0)
1154:
    sub  t2, t2, t5
    sh   a1, 10(s0)
    lw   a2, 16(s0)
    lw   t5, 4(s0)
    srl  t1, t1, t3
    andi t6, t0, 16
    beqz t6, 1155f
    lbu   a2, 4(s0)
1155:
    sll  a2, a2, t5
    sh   a2, 22(s0)
    sw   t5, 20(s0)
    sh   a4, 20(s0)
    sw   t0, 20(s0)
    lw   a4, 20(s0)
    sw   t2, 0(s0)
    lb   t3, 24(s0)
    andi t6, a1, 1
    beqz t6, 1156f
    sb   t4, 11(s0)
    sw   a1, 16(s0)
1156:
    sw   t4, 8(s0)
    lbu   a1, 20(s0)
    sw   t0, 20(s0)
    or  a2, a2, t5
    sh   t2, 20(s0)
    srl  t1, t1, a4
    srl  a4, a4, a3
    lh   a3, 2(s0)
    sb   t4, 20(s0)
    srl  t2, t2, a1
    sub  a4, a4, t1
    srl  a1, a1, t5
    addi a1, a1, -1826
    lbu   t1, 31(s0)
    sw   a1, 20(s0)
    sw   t0, 12(s0)
    sb   a4, 13(s0)
    sb   t5, 13(s0)
    sb   t5, 12(s0)
    lw   t5, 12(s0)
    lh   t2, 14(s0)
    sw   a3, 4(s0)
    andi t6, t2, 16
    beqz t6, 1157f
    lbu   t5, 3(s0)
    sw   a4, 8(s0)
1157:
    sb   t0, 30(s0)
    or  a2, a2, t5
    sw   t2, 4(s0)
    lw   a4, 0(s0)
    sb   a1, 0(s0)
    andi t6, a1, 4
    beqz t6, 1158f
    sb   t2, 22(s0)
    lbu   a1, 20(s0)
    lw   t4, 12(s0)
1158:
    lh   a2, 14(s0)
    lh   t4, 6(s0)
    sll  a4, a4, t0
    addi a4, a4, 1964
    sw   t5, 12(s0)
    lhu   a2, 24(s0)
    sh   t1, 28(s0)
    sw   a4, 24(s0)
    srl  a3, a3, a3
    sw   t1, 16(s0)
    sb   t4, 17(s0)
    lhu   a1, 16(s0)
    lhu   a1, 18(s0)
    sw   t3, 4(s0)
    lh   t2, 4(s0)
    srl  t3, t3, t0
    sb   t0, 0(s0)
    xor  t2, t2, a3
    add  a4, a4, t3
    sw   t5, 20(s0)
    sb   t4, 21(s0)
    sw   t4, 20(s0)
    sb   t1, 22(s0)
    lw   t4, 20(s0)
    lw   t2, 4(s0)
    sub  t5, t5, t4
    xor  t2, t2, a4
    addi t2, t2, 1464
    lhu   a2, 8(s0)
    or  t2, t2, t0
    sw   a3, 24(s0)
    sb   a3, 24(s0)
    lb   t2, 9(s0)
    sb   a4, 26(s0)
    sw   t2, 0(s0)
    sh   a1, 2(s0)
    lw   a3, 0(s0)
    lw   a2, 0(s0)
    lw   t1, 28(s0)
    sll  t4, t4, a3
    addi t4, t4, -1168
    andi t6, a2, 4
    beqz t6, 1159f
    sh   a1, 24(s0)
    lw   t1, 0(s0)
1159:
    lhu   a1, 20(s0)
    lh   t0, 18(s0)
    or  t1, t1, a3
    lw   t2, 8(s0)
    lhu   t0, 30(s0)
    sw   a3, 12(s0)
    sw   a4, 12(s0)
    lhu   a4, 12(s0)
    lhu   t2, 14(s0)
    lh   a2, 10(s0)
    andi t6, t1, 16
    beqz t6, 1160f
    lw   t2, 0(s0)
    sb   a2, 16(s0)
1160:
    sb   t0, 22(s0)
    sw   t3, 12(s0)
    xor  a3, a3, t1
    sll  a4, a4, t5
    addi a4, a4, 1509
    lw   t1, 28(s0)
    lw   t5, 24(s0)
    or  t5, t5, a1
    sll  a4, a4, t4
    xor  a4, a4, a3
    sll  t3, t3, t4
    lh   a4, 8(s0)
    sb   t4, 16(s0)
    sw   t4, 16(s0)
    sh   t4, 18(s0)
    sh   t0, 18(s0)
    lb   a1, 16(s0)
    lhu   t3, 12(s0)
    sw   t3, 8(s0)
    sw   t2, 8(s0)
    sh   t0, 8(s0)
    lhu   t0, 8(s0)
    lhu   a1, 10(s0)
    sh   t1, 4(s0)
    sh   t2, 6(s0)
    lb   t2, 6(s0)
    lhu   t0, 28(s0)
    sw   a4, 28(s0)
    lhu   t0, 0(s0)
    andi t6, a3, 8
    beqz t6, 1161f
    lw   a2, 20(s0)
    sb   t5, 0(s0)
1161:
    lb   t0, 19(s0)
    sb   t4, 11(s0)
    add  t4, t4, a1
    sw   t0, 4(s0)
    lw   t3, 0(s0)
    or  t2, t2, t2
    lw   a4, 16(s0)
    or  t4, t4, t4
    addi t4, t4, 1758
    lw   a3, 4(s0)
    sub  a1, a1, a2
    lbu   t3, 1(s0)
    sh   t4, 20(s0)
    lw   t0, 0(s0)
    lw   t2, 20(s0)
    sw   a4, 12(s0)
    srl  t0, t0, a3
    addi t0, t0, -1321
    sb   t3, 16(s0)
    srl  t1, t1, a4
    srl  t5, t5, t1
    srl  t4, t4, t0
    andi t6, t0, 4
    beqz t6, 1162f
    lw   t1, 16(s0)
    sh   t2, 22(s0)
    lbu   t2, 23(s0)
1162:
    add  a4, a4, t2
    sll  a4, a4, a4
    lw   t1, 16(s0)
    lh   a1, 12(s0)
    sw   t2, 20(s0)
    add  t1, t1, t0
    lh   a1, 8(s0)
    andi t6, a1, 2
    beqz t6, 1163f
    lbu   t0, 21(s0)
1163:
    lw   t4, 0(s0)
    lw   t2, 8(s0)
    lb   t4, 4(s0)
    sw   a3, 16(s0)
    sb   a4, 19(s0)
    sh   a4, 16(s0)
    lw   a3, 16(s0)
    lhu   a4, 18(s0)
    xor  a3, a3, a2
    sw   t3, 24(s0)
    sb   t3, 25(s0)
    sw   a1, 24(s0)
    lw   t3, 24(s0)
    sh   t1, 12(s0)
    sw   t0, 12(s0)
    sw   t3, 12(s0)
    lw   t3, 12(s0)
    sh   t3, 30(s0)
    lb   t5, 18(s0)
    sh   t2, 22(s0)
    andi t6, a4, 8
    beqz t6, 1164f
    sh   a2, 14(s0)
    sb   t2, 10(s0)
    lw   a2, 16(s0)
1164:
    lhu   a4, 12(s0)
    or  t5, t5, t2
    sw   t4, 8(s0)
    add  t0, t0, a3
    sh   t3, 4(s0)
    andi t6, t4, 8
    beqz t6, 1165f
    lw   t3, 8(s0)
    lw   a1, 28(s0)
    sb   a2, 16(s0)
1165:
    sh   a4, 30(s0)
    lh   t1, 0(s0)
    andi t6, a4, 1
    beqz t6, 1166f
    sw   t3, 16(s0)
    lbu   t4, 19(s0)
    lbu   t3, 14(s0)
1166:
    add  t2, t2, t5
    lb   t1, 23(s0)
    sw   t0, 12(s0)
    sb   t2, 30(s0)
    sll  a3, a3, t5
    sw   t0, 24(s0)
    lh   a4, 20(s0)
    sh   a2, 10(s0)
    xor  t2, t2, t5
    addi t2, t2, -840
    andi t6, t1, 1
    beqz t6, 1167f
    sw   t3, 0(s0)
1167:
    lh   t3, 6(s0)
    sh   t2, 0(s0)
    sll  t0, t0, t4
    addi t0, t0, 595
    lb   a2, 16(s0)
    sw   t4, 12(s0)
    sb   t2, 13(s0)
    sh   t2, 12(s0)
    lb   a2, 13(s0)
    lb   a4, 13(s0)
    lhu   t0, 10(s0)
    andi t6, t2, 8
    beqz t6, 1168f
    sw   t2, 20(s0)
1168:
    sll  a3, a3, t3
    addi a3, a3, 893
    add  t4, t4, a4
    srl  a1, a1, a3
    sb   t0, 11(s0)
    lhu   t0, 24(s0)
    sw   t1, 28(s0)
    sh   t1, 26(s0)
    sw   t2, 24(s0)
    sw   a4, 24(s0)
    sh   t2, 24(s0)
    lb   t3, 26(s0)
    lw   t0, 0(s0)
    or  a2, a2, t3
    lb   a2, 15(s0)
    lw   t1, 12(s0)
    lw   t0, 20(s0)
    lw   t3, 20(s0)
    lw   a3, 28(s0)
    lw   a4, 16(s0)
    andi t6, t1, 1
    beqz t6, 1169f
    lw   a1, 8(s0)
1169:
    sub  t4, t4, t3
    addi t4, t4, -280
    sb   t3, 16(s0)
    srl  a3, a3, a3
    lhu   t2, 14(s0)
    andi t6, t4, 4
    beqz t6, 1170f
    sh   a4, 24(s0)
1170:
    srl  t2, t2, a4
    lh   t5, 2(s0)
    sll  t5, t5, t1
    sb   a3, 6(s0)
    sll  a3, a3, a2
    sw   t4, 0(s0)
    sh   a3, 2(s0)
    sh   t1, 0(s0)
    sw   t0, 0(s0)
    lhu   a3, 2(s0)
    lhu   t4, 0(s0)
    lb   t0, 1(s0)
    srl  t0, t0, a1
    add  t2, t2, a1
    xor  t3, t3, a2
    sw   t0, 8(s0)
    sub  t5, t5, a2
    xor  a4, a4, a2
    addi a4, a4, 1119
    andi t6, t0, 16
    beqz t6, 1171f
    lw   t3, 12(s0)
    lw   t3, 16(s0)
1171:
    andi t6, a3, 16
    beqz t6, 1172f
    sb   a1, 12(s0)
    sw   a4, 8(s0)
1172:
    add  t3, t3, a4
    or  a1, a1, a1
    lh   a1, 20(s0)
    add  a4, a4, t5
    sh   a4, 0(s0)
    lbu   t3, 8(s0)
    srl  t5, t5, a4
    sh   t3, 28(s0)
    andi t6, t0, 8
    beqz t6, 1173f
    sb   t2, 22(s0)
1173:
    sh   t3, 30(s0)
    lbu   t4, 18(s0)
    sub  t1, t1, t0
    sw   t3, 12(s0)
    add  a4, a4, t3
    add  t1, t1, t5
    addi t1, t1, 716
    lw   t4, 20(s0)
    sb   t0, 12(s0)
    sb   t4, 29(s0)
    sb   t2, 23(s0)
    sb   t4, 20(s0)
    sb   a1, 21(s0)
    sw   t1, 20(s0)
    lw   a4, 20(s0)
    lb   t5, 19(s0)
    sh   t4, 20(s0)
    lb   t0, 8(s0)
    sub  t3, t3, a1
    srl  t0, t0, t2
    srl  t1, t1, a3
    lbu   a4, 24(s0)
    lh   a1, 18(s0)
    sub  t1, t1, t4
    addi t1, t1, 1763
    xor  t1, t1, t0
    lbu   a4, 15(s0)
    srl  t5, t5, a4
    addi t5, t5, -238
    xor  t5, t5, a3
    sh   t3, 26(s0)
    sh   t5, 24(s0)
    sh   t0, 24(s0)
    sw   t1, 24(s0)
    lb   a2, 25(s0)
    xor  t0, t0, a3
    addi t0, t0, 1513
    sub  t1, t1, a4
    addi t1, t1, -145
    lb   t5, 26(s0)
    lb   t4, 0(s0)
    andi t6, a4, 4
    beqz t6, 1174f
    sw   a3, 8(s0)
    sb   a4, 6(s0)
    lbu   a3, 8(s0)
1174:
    sll  a2, a2, t3
    lw   t4, 16(s0)
    srl  t0, t0, a4
    lb   a1, 15(s0)
    sll  t2, t2, a3
    sb   a2, 20(s0)
    sw   t3, 16(s0)
    lw   a4, 16(s0)
    andi t6, t4, 4
    beqz t6, 1175f
    sh   t1, 10(s0)
    sb   t1, 11(s0)
1175:
    lw   t2, 4(s0)
    lw   a1, 12(s0)
    or  t4, t4, t5
    add  t4, t4, a1
    addi t4, t4, 197
    sll  a1, a1, t0
    sw   a1, 8(s0)
    sh   a1, 8(s0)
    lhu   t4, 8(s0)
    lb   t4, 25(s0)
    sw   t4, 24(s0)
    add  t2, t2, t5
    addi t2, t2, -481
    or  t3, t3, t2
    sw   t2, 24(s0)
    sw   t1, 4(s0)
    or  a1, a1, t2
    andi t6, t1, 16
    beqz t6, 1176f
    sh   a4, 6(s0)
    sb   t4, 17(s0)
1176:
    add  a4, a4, a3
    andi t6, t5, 8
    beqz t6, 1177f
    lw   a4, 20(s0)
    lw   t1, 24(s0)
    sh   t4, 6(s0)
1177:
    sll  t4, t4, t0
    add  t5, t5, t2
    lb   a3, 29(s0)
    add  t0, t0, t0
    lw   t5, 4(s0)
    andi t6, a2, 8
    beqz t6, 1178f
    sw   t5, 28(s0)
1178:
    sll  a2, a2, a3
    or  t1, t1, t3
    sll  t4, t4, t2
    sll  a3, a3, t3
    addi a3, a3, 1714
    xor  t3, t3, t4
    andi t6, t2, 2
    beqz t6, 1179f
    sb   a2, 2(s0)
    sw   a1, 28(s0)
    sb   t2, 30(s0)
1179:
    xor  a3, a3, a3
    addi a3, a3, -854
    andi t6, a2, 8
    beqz t6, 1180f
    lbu   t5, 11(s0)
    sh   t2, 2(s0)
1180:
    lw   a1, 4(s0)
    sw   t2, 8(s0)
    lw   a3, 4(s0)
    lw   a4, 0(s0)
    xor  t1, t1, t5
    andi t6, t5, 16
    beqz t6, 1181f
    sb   a3, 27(s0)
    sb   t2, 8(s0)
    sw   a4, 28(s0)
1181:
    andi t6, t1, 1
    beqz t6, 1182f
    lbu   a1, 23(s0)
    sb   t5, 5(s0)
1182:
    xor  a1, a1, t5
    lw   t0, 20(s0)
    sb   t4, 24(s0)
    sub  a4, a4, t3
    sb   t1, 8(s0)
    sb   a2, 2(s0)
    lbu   t1, 26(s0)
    lw   a1, 16(s0)
    lb   a1, 13(s0)
    or  t5, t5, a2
    sw   t0, 28(s0)
    sh   a2, 6(s0)
    sw   a2, 4(s0)
    sh   t4, 4(s0)
    sb   t5, 6(s0)
    lhu   t3, 4(s0)
    xor  t5, t5, a1
    lbu   a2, 28(s0)
    xor  t4, t4, a4
    sw   a2, 12(s0)
    xor  t3, t3, t0
    addi t3, t3, -17
    add  t1, t1, t3
    add  t1, t1, a3
    addi t1, t1, 1313
    sw   t5, 4(s0)
    sll  a2, a2, a3
    addi a2, a2, 1794
    lhu   t0, 2(s0)
    sh   a3, 14(s0)
    srl  a3, a3, a2
    sb   t4, 8(s0)
    sw   t2, 8(s0)
    sw   t2, 8(s0)
    sb   a2, 9(s0)
    lw   a3, 8(s0)
    sb   a2, 5(s0)
    xor  a2, a2, t4
    sh   a1, 16(s0)
    lb   t1, 2(s0)
    sh   a2, 6(s0)
    sb   t4, 7(s0)
    lhu   a2, 6(s0)
    lw   a1, 4(s0)
    lw   t1, 4(s0)
    sw   t2, 4(s0)
    sh   a4, 6(s0)
    sw   t2, 4(s0)
    lw   a3, 4(s0)
    lb   a3, 4(s0)
    sub  t4, t4, a3
    sw   t4, 4(s0)
    sw   a2, 4(s0)
    lw   a2, 0(s0)
    sh   a3, 20(s0)
    lw   a2, 28(s0)
    add  a3, a3, a3
    lb   t4, 10(s0)
    sb   a3, 12(s0)
    andi t6, t4, 2
    beqz t6, 1183f
    sh   a1, 18(s0)
1183:
    andi t6, t5, 1
    beqz t6, 1184f
    sw   t2, 12(s0)
    sb   a1, 28(s0)
    lbu   t5, 0(s0)
1184:
    sub  t0, t0, t2
    or  a1, a1, a2
    addi a1, a1, 684
    sb   t2, 30(s0)
    lhu   t1, 18(s0)
    lh   a2, 22(s0)
    sw   a4, 12(s0)
    or  t4, t4, a1
    addi t4, t4, -2031
    sb   a4, 24(s0)
    sw   t3, 8(s0)
    sw   t3, 8(s0)
    lb   t1, 16(s0)
    lb   t5, 0(s0)
    lh   t4, 20(s0)
    lw   a1, 4(s0)
    lw   t0, 12(s0)
    lhu   a3, 14(s0)
    srl  a1, a1, a4
    xor  t2, t2, t1
    addi t2, t2, -1285
    lb   a1, 22(s0)
    sub  t5, t5, t0
    xor  t1, t1, t5
    lhu   a3, 12(s0)
    lb   a2, 10(s0)
    lhu   t3, 6(s0)
    lbu   t2, 19(s0)
    lw   a1, 8(s0)
    lw   t4, 8(s0)
    andi t6, t0, 1
    beqz t6, 1185f
    sh   a4, 10(s0)
    lbu   a4, 6(s0)
    sb   a1, 6(s0)
1185:
    sll  t3, t3, t2
    addi t3, t3, 832
    or  t0, t0, a1
    addi t0, t0, -1077
    lh   a3, 16(s0)
    sub  t5, t5, t5
    sw   t0, 16(s0)
    lw   a2, 12(s0)
    sh   t1, 26(s0)
    or  t0, t0, a4
    sh   t4, 6(s0)
    lhu   t4, 10(s0)
    or  t2, t2, t0
    addi t2, t2, -1647
    lbu   a2, 0(s0)
    sw   a3, 12(s0)
    sb   t3, 14(s0)
    lw   a2, 12(s0)
    sb   t0, 12(s0)
    add  a1, a1, a3
    sh   t0, 4(s0)
    sub  t3, t3, t0
    addi t3, t3, -963
    sw   a1, 12(s0)
    sh   t2, 14(s0)
    sw   a3, 12(s0)
    lw   t1, 12(s0)
    lw   a4, 12(s0)
    andi t6, t0, 1
    beqz t6, 1186f
    sh   t4, 16(s0)
1186:
    xor  t4, t4, t1
    lw   a3, 24(s0)
    sw   t4, 0(s0)
    lh   t3, 20(s0)
    xor  t4, t4, a4
    sb   t4, 14(s0)
    sb   t3, 12(s0)
    lw   t5, 12(s0)
    sll  t5, t5, t4
    addi t5, t5, -350
    andi t6, t5, 8
    beqz t6, 1187f
    sh   t1, 8(s0)
    sb   t5, 26(s0)
    lw   t0, 8(s0)
1187:
    lw   t1, 24(s0)
    lb   a1, 1(s0)
    sw   a3, 20(s0)
    or  a3, a3, t3
    andi t6, t3, 16
    beqz t6, 1188f
    sh   t2, 26(s0)
1188:
    sb   t4, 21(s0)
    sh   a1, 20(s0)
    sw   a2, 20(s0)
    sw   t2, 20(s0)
    lw   t5, 20(s0)
    sw   t5, 0(s0)
    sb   t4, 2(s0)
    lhu   a2, 0(s0)
    lw   a1, 0(s0)
    or  t1, t1, t2
    andi t6, t1, 8
    beqz t6, 1189f
    sb   t4, 0(s0)
    sw   a4, 8(s0)
    lbu   t2, 29(s0)
1189:
    sb   a3, 26(s0)
    lhu   t2, 2(s0)
    add  t1, t1, a4
    andi t6, a2, 1
    beqz t6, 1190f
    sb   t0, 19(s0)
1190:
    sh   a3, 8(s0)
    lw   t1, 24(s0)
    sw   t4, 28(s0)
    sh   t5, 8(s0)
    sb   a2, 10(s0)
    lb   t0, 10(s0)
    lhu   t3, 8(s0)
    lh   t0, 18(s0)
    sw   t5, 16(s0)
    lw   a4, 0(s0)
    srl  t4, t4, t4
    srl  t1, t1, t4
    lbu   t3, 27(s0)
    lw   a4, 24(s0)
    sub  t2, t2, t2
    sub  a3, a3, t4
    addi a3, a3, 2026
    andi t6, t2, 1
    beqz t6, 1191f
    lw   t4, 12(s0)
    lw   t1, 28(s0)
    sb   a2, 25(s0)
1191:
    andi t6, a2, 8
    beqz t6, 1192f
    lw   a4, 0(s0)
    sb   a2, 10(s0)
    lw   a1, 20(s0)
1192:
    add  t5, t5, t4
    lb   t4, 20(s0)
    lhu   t2, 18(s0)
    andi t6, a3, 1
    beqz t6, 1193f
    sb   t4, 16(s0)
1193:
    sw   a4, 8(s0)
    lw   a1, 28(s0)
    sll  t4, t4, t2
    addi t4, t4, -373
    andi t6, a1, 4
    beqz t6, 1194f
    lbu   a1, 26(s0)
    lw   a1, 16(s0)
1194:
    sb   t0, 19(s0)
    sb   a1, 17(s0)
    lw   t1, 16(s0)
    lhu   a2, 18(s0)
    sw   t4, 12(s0)
    andi t6, t3, 2
    beqz t6, 1195f
    lw   t0, 4(s0)
    sw   t1, 12(s0)
    sw   t4, 16(s0)
1195:
    sw   t1, 16(s0)
    sw   a1, 12(s0)
    lw   t1, 8(s0)
    lb   t5, 20(s0)
    srl  t0, t0, t4
    srl  t3, t3, t3
    addi t3, t3, 968
    sh   a2, 14(s0)
    sb   a2, 12(s0)
    sw   t4, 12(s0)
    lw   t2, 12(s0)
    sw   t4, 20(s0)
    sll  a1, a1, t2
    lbu   a4, 5(s0)
    sw   t0, 24(s0)
    sh   a1, 26(s0)
    lw   a2, 24(s0)
    lw   a1, 24(s0)
    srl  t2, t2, a3
    addi t2, t2, 378
    lbu   t2, 28(s0)
    lb   t4, 26(s0)
    sh   t1, 28(s0)
    andi t6, t2, 16
    beqz t6, 1196f
    lbu   t0, 13(s0)
1196:
    sw   t5, 0(s0)
    andi t6, t4, 8
    beqz t6, 1197f
    sw   a2, 20(s0)
    lw   t5, 28(s0)
1197:
    andi t6, a2, 8
    beqz t6, 1198f
    sb   t3, 29(s0)
    sw   a2, 8(s0)
1198:
    xor  t4, t4, t0
    sw   t3, 0(s0)
    sw   t3, 8(s0)
    sw   a3, 8(s0)
    lh   a2, 16(s0)
    sh   t1, 18(s0)
    lh   t2, 8(s0)
    lh   t0, 30(s0)
    sw   a1, 8(s0)
    sh   a2, 24(s0)
    sh   a3, 18(s0)
    sw   t0, 16(s0)
    lb   a3, 19(s0)
    sll  a4, a4, a3
    sub  t4, t4, a3
    lbu   t4, 28(s0)
    sw   t1, 20(s0)
    sub  t4, t4, a1
    addi t4, t4, -667
    lw   t4, 20(s0)
    or  a3, a3, t2
    andi t6, t3, 1
    beqz t6, 1199f
    sw   t2, 12(s0)
    lbu   a1, 0(s0)
    sb   t3, 23(s0)
1199:
    sll  t2, t2, t5
    lb   t1, 27(s0)
    andi t6, t1, 16
    beqz t6, 1200f
    sw   t1, 16(s0)
    sh   t4, 16(s0)
    sb   t5, 7(s0)
1200:
    xor  a3, a3, t1
    addi a3, a3, 1318
    sw   t5, 8(s0)
    lhu   a4, 14(s0)
    sb   t4, 8(s0)
    sh   a3, 18(s0)
    sw   a4, 16(s0)
    lw   a2, 16(s0)
    lw   t3, 4(s0)
    sh   t5, 4(s0)
    sb   t0, 7(s0)
    lb   a4, 5(s0)
    lhu   t1, 26(s0)
    sub  a2, a2, t0
    lhu   t2, 12(s0)
    lw   t4, 4(s0)
    lh   t5, 18(s0)
    sll  t1, t1, t1
    lw   a3, 0(s0)
    sw   t1, 20(s0)
    sb   t1, 30(s0)
    sb   t1, 26(s0)
    sh   t3, 26(s0)
    sb   a2, 27(s0)
    sw   t5, 24(s0)
    lhu   t5, 26(s0)
    or  a1, a1, t0
    xor  a1, a1, t2
    or  a4, a4, t4
    lbu   t2, 24(s0)
    sb   t1, 1(s0)
    lh   a3, 12(s0)
    lw   t5, 20(s0)
    andi t6, a4, 8
    beqz t6, 1201f
    lbu   t1, 0(s0)
1201:
    lhu   a2, 26(s0)
    xor  a2, a2, t0
    or  a2, a2, t2
    sb   t4, 5(s0)
    lw   t0, 12(s0)
    lw   a4, 16(s0)
    lh   t4, 6(s0)
    andi t6, t0, 8
    beqz t6, 1202f
    sb   t1, 16(s0)
    sh   t4, 18(s0)
1202:
    lw   t3, 24(s0)
    srl  t0, t0, t4
    sh   t0, 10(s0)
    sh   a3, 8(s0)
    lhu   t0, 8(s0)
    xor  a3, a3, t5
    addi a3, a3, 1722
    lhu   a2, 10(s0)
    lw   a3, 4(s0)
    srl  t5, t5, a2
    addi t5, t5, -676
    sh   t3, 10(s0)
    sw   a1, 8(s0)
    sll  t2, t2, t3
    sw   t0, 0(s0)
    andi t6, a3, 16
    beqz t6, 1203f
    sw   t0, 24(s0)
1203:
    lw   a4, 16(s0)
    sw   t5, 28(s0)
    sh   a1, 24(s0)
    sb   a1, 10(s0)
    sh   t1, 8(s0)
    sh   t3, 10(s0)
    lhu   a1, 10(s0)
    sh   a3, 12(s0)
    andi t6, t5, 1
    beqz t6, 1204f
    sb   t0, 14(s0)
    sh   t2, 2(s0)
    lbu   t2, 4(s0)
1204:
    xor  t0, t0, t3
    sh   a4, 0(s0)
    sb   t5, 17(s0)
    sw   a1, 16(s0)
    sh   t3, 16(s0)
    sb   t1, 16(s0)
    lw   t0, 16(s0)
    srl  t5, t5, a4
    addi t5, t5, -1896
    andi t6, a1, 4
    beqz t6, 1205f
    lw   a4, 24(s0)
    sw   t2, 12(s0)
1205:
    sh   a3, 2(s0)
    sb   t0, 5(s0)
    sb   t4, 14(s0)
    lb   a4, 30(s0)
    add  a3, a3, t2
    addi a3, a3, 578
    or  t3, t3, t2
    lw   t3, 24(s0)
    or  t0, t0, a2
    addi t0, t0, -1586
    sw   t0, 12(s0)
    lh   t4, 30(s0)
    sw   a4, 28(s0)
    lhu   a4, 26(s0)
    andi t6, t0, 1
    beqz t6, 1206f
    lw   a3, 16(s0)
    lbu   t5, 0(s0)
    sh   a4, 8(s0)
1206:
    sw   t4, 28(s0)
    add  t5, t5, t0
    andi t6, t2, 1
    beqz t6, 1207f
    sb   t4, 2(s0)
1207:
    lh   a3, 20(s0)
    sw   t1, 28(s0)
    sh   t3, 10(s0)
    sb   t2, 19(s0)
    sb   t2, 16(s0)
    sh   a2, 16(s0)
    sw   a4, 16(s0)
    lw   t3, 16(s0)
    andi t6, a1, 2
    beqz t6, 1208f
    sh   t3, 22(s0)
1208:
    sw   t0, 28(s0)
    srl  a4, a4, t2
    add  a1, a1, t0
    addi a1, a1, -1361
    sb   t2, 10(s0)
    sh   t1, 10(s0)
    sw   a2, 8(s0)
    sb   a1, 11(s0)
    lw   t5, 8(s0)
    lb   t4, 10(s0)
    or  a1, a1, a2
    addi a1, a1, -873
    sh   t1, 14(s0)
    lb   t0, 22(s0)
    sw   t5, 16(s0)
    sw   a3, 8(s0)
    lbu   t2, 1(s0)
    add  a1, a1, a3
    lbu   t4, 9(s0)
    lbu   t3, 24(s0)
    sw   t2, 0(s0)
    lh   t3, 22(s0)
    sw   a1, 8(s0)
    add  t1, t1, a3
    addi t1, t1, -1048
    lhu   a2, 12(s0)
    sh   a1, 16(s0)
    lh   t3, 12(s0)
    lbu   t2, 17(s0)
    xor  t0, t0, t1
    add  t4, t4, t3
    addi t4, t4, 1870
    sh   a3, 12(s0)
    sh   a2, 14(s0)
    andi t6, t2, 1
    beqz t6, 1209f
    lbu   t1, 7(s0)
    sh   a3, 16(s0)
1209:
    lh   t4, 14(s0)
    sll  t2, t2, t5
    addi t2, t2, 1224
    lbu   a1, 9(s0)
    sb   a4, 29(s0)
    lw   a4, 0(s0)
    lhu   t5, 0(s0)
    sll  t2, t2, t4
    sub  t1, t1, t1
    lh   a1, 28(s0)
    lw   t3, 16(s0)
    sw   a4, 8(s0)
    lh   t1, 14(s0)
    sw   t3, 24(s0)
    sw   t0, 0(s0)
    sb   t1, 23(s0)
    lw   a3, 20(s0)
    sh   t0, 18(s0)
    sh   t3, 18(s0)
    sb   a2, 16(s0)
    lw   t2, 16(s0)
    lw   t4, 16(s0)
    sb   a1, 13(s0)
    sb   t1, 15(s0)
    lb   t3, 15(s0)
    lb   t3, 14(s0)
    xor  t4, t4, a2
    xor  t2, t2, a4
    addi t2, t2, 955
    sll  t1, t1, a2
    sw   t4, 24(s0)
    sw   a2, 24(s0)
    lb   a1, 25(s0)
    lb   a2, 24(s0)
    andi t6, t4, 16
    beqz t6, 1210f
    sh   t4, 0(s0)
    lw   t4, 0(s0)
    sb   a2, 22(s0)
1210:
    sw   t4, 28(s0)
    sb   t4, 14(s0)
    sw   a4, 12(s0)
    sw   t3, 12(s0)
    lb   a4, 13(s0)
    lhu   t0, 12(s0)
    sb   a1, 6(s0)
    lh   t2, 28(s0)
    lh   t0, 12(s0)
    lhu   t1, 30(s0)
    lw   a2, 0(s0)
    sll  t0, t0, t0
    addi t0, t0, -1714
    sw   t5, 20(s0)
    lbu   t4, 31(s0)
    andi t6, t2, 1
    beqz t6, 1211f
    sh   t2, 18(s0)
1211:
    lb   t0, 9(s0)
    or  t5, t5, a1
    lw   t1, 28(s0)
    lw   t4, 0(s0)
    lhu   t5, 28(s0)
    xor  a1, a1, t2
    lw   t2, 8(s0)
    lh   a2, 8(s0)
    or  a4, a4, a2
    sll  t3, t3, a1
    addi t3, t3, 1145
    sh   t5, 6(s0)
    sb   t2, 7(s0)
    sb   t5, 5(s0)
    lb   a3, 5(s0)
    sw   t2, 8(s0)
    srl  t2, t2, a4
    andi t6, a4, 16
    beqz t6, 1212f
    sw   a2, 4(s0)
    sb   t3, 6(s0)
    sb   t4, 12(s0)
1212:
    sb   t4, 29(s0)
    sh   a4, 30(s0)
    sb   t5, 29(s0)
    sh   a1, 30(s0)
    lhu   t2, 30(s0)
    lw   t4, 28(s0)
    sub  t1, t1, a2
    addi t1, t1, 2010
    sw   a4, 12(s0)
    sw   t2, 20(s0)
    sb   a1, 23(s0)
    sh   a3, 22(s0)
    lw   t2, 20(s0)
    lw   a1, 20(s0)
    lb   a3, 7(s0)
    xor  t2, t2, t3
    lw   t2, 0(s0)
    andi t6, t5, 1
    beqz t6, 1213f
    lbu   t3, 6(s0)
1213:
    andi t6, a4, 4
    beqz t6, 1214f
    sw   a3, 4(s0)
1214:
    sb   a1, 2(s0)
    or  a4, a4, t3
    lw   t3, 20(s0)
    sw   t3, 24(s0)
    sw   a1, 24(s0)
    sh   t4, 26(s0)
    sh   t1, 26(s0)
    lb   t5, 24(s0)
    lw   t5, 28(s0)
    lhu   t2, 20(s0)
    lb   a4, 11(s0)
    add  t5, t5, t5
    srl  t1, t1, t4
    addi t1, t1, -1494
    lw   a2, 16(s0)
    lhu   a2, 0(s0)
    lbu   t1, 28(s0)
    andi t6, t4, 8
    beqz t6, 1215f
    sh   t0, 20(s0)
1215:
    srl  a3, a3, t2
    or  t5, t5, a3
    lh   a1, 24(s0)
    lbu   t0, 16(s0)
    lb   a3, 20(s0)
    lbu   a2, 10(s0)
    srl  t2, t2, t5
    add  t1, t1, t3
    sll  t0, t0, a3
    xor  t4, t4, t4
    lh   a3, 4(s0)
    sh   t3, 16(s0)
    lbu   a3, 28(s0)
    sll  a1, a1, t4
    lh   t5, 28(s0)
    sw   t4, 28(s0)
    sb   t0, 28(s0)
    sb   t5, 30(s0)
    sw   t5, 28(s0)
    lw   t1, 28(s0)
    lhu   a1, 20(s0)
    add  t2, t2, t4
    addi t2, t2, -1605
    sb   a3, 3(s0)
    sb   t0, 31(s0)
    lw   a2, 20(s0)
    lhu   t1, 28(s0)
    sub  t0, t0, a1
    addi t0, t0, -591
    lb   t5, 9(s0)
    sw   t4, 16(s0)
    sb   t5, 31(s0)
    sh   t1, 28(s0)
    sb   t5, 31(s0)
    sh   t1, 28(s0)
    lw   t2, 28(s0)
    andi t6, t3, 16
    beqz t6, 1216f
    sh   a1, 0(s0)
    lbu   a3, 0(s0)
1216:
    sb   t3, 14(s0)
    srl  t3, t3, t4
    andi t6, a4, 16
    beqz t6, 1217f
    sh   t2, 0(s0)
    sh   t0, 30(s0)
1217:
    sb   t2, 10(s0)
    lhu   t3, 2(s0)
    add  t1, t1, t0
    xor  a2, a2, t2
    addi a2, a2, 1514
    sh   t0, 16(s0)
    srl  t3, t3, a4
    lw   t4, 4(s0)
    sw   t2, 12(s0)
    lw   t1, 0(s0)
    lw   t3, 16(s0)
    add  t4, t4, a1
    add  a2, a2, a1
    addi a2, a2, -1669
    lw   t3, 16(s0)
    lhu   a1, 6(s0)
    sw   a3, 12(s0)
    sw   a2, 20(s0)
    or  a1, a1, t2
    sb   t2, 21(s0)
    sh   a4, 20(s0)
    sb   a3, 20(s0)
    lw   t5, 20(s0)
    sb   t1, 15(s0)
    sll  a4, a4, t0
    sw   a2, 16(s0)
    lw   a3, 28(s0)
    xor  t3, t3, a4
    lw   t5, 4(s0)
    lw   t3, 16(s0)
    sw   a4, 28(s0)
    lhu   a1, 24(s0)
    lb   a1, 2(s0)
    lw   a1, 28(s0)
    andi t6, t4, 4
    beqz t6, 1218f
    sb   t1, 22(s0)
1218:
    sh   t2, 8(s0)
    or  t3, t3, t0
    addi t3, t3, 384
    lh   a3, 18(s0)
    sb   t1, 6(s0)
    sb   a3, 6(s0)
    lhu   a4, 4(s0)
    sw   a1, 28(s0)
    sh   t0, 18(s0)
    xor  a1, a1, t3
    add  t2, t2, t3
    andi t6, t3, 8
    beqz t6, 1219f
    lbu   t4, 20(s0)
    sh   a4, 24(s0)
    sh   t3, 30(s0)
1219:
    lb   a4, 1(s0)
    lw   a3, 16(s0)
    sb   t1, 21(s0)
    sb   t4, 31(s0)
    sw   a3, 28(s0)
    sw   t3, 28(s0)
    lw   t1, 28(s0)
    lhu   a2, 30(s0)
    lb   a3, 18(s0)
    andi t6, a2, 8
    beqz t6, 1220f
    sb   a3, 12(s0)
    sw   t4, 16(s0)
    sb   a3, 11(s0)
1220:
    sh   a2, 26(s0)
    lhu   t3, 6(s0)
    sh   t4, 30(s0)
    sw   a2, 28(s0)
    sw   a4, 28(s0)
    lw   t5, 28(s0)
    lhu   a3, 0(s0)
    sw   a4, 4(s0)
    sw   t5, 24(s0)
    srl  t5, t5, t2
    addi t5, t5, -1180
    or  a3, a3, t3
    or  t4, t4, a4
    or  a2, a2, t3
    addi a2, a2, -1617
    andi t6, t1, 8
    beqz t6, 1221f
    sh   a3, 0(s0)
    sw   a1, 20(s0)
    lw   t4, 0(s0)
1221:
    sb   t3, 13(s0)
    sh   t2, 18(s0)
    sw   a3, 16(s0)
    sb   t2, 18(s0)
    sh   t0, 18(s0)
    lhu   a4, 18(s0)
    srl  a3, a3, a3
    andi t6, t0, 16
    beqz t6, 1222f
    sh   t0, 14(s0)
    lw   t2, 8(s0)
    lbu   t0, 10(s0)
1222:
    add  t3, t3, t3
    xor  t0, t0, a3
    addi t0, t0, 1182
    srl  a4, a4, t3
    addi a4, a4, -1429
    lh   t1, 24(s0)
    sb   t2, 15(s0)
    sb   t4, 1(s0)
    lb   t4, 6(s0)
    sw   t2, 4(s0)
    sw   t3, 24(s0)
    sb   t4, 24(s0)
    sw   t3, 24(s0)
    sh   t3, 26(s0)
    lhu   t1, 24(s0)
    lw   a1, 24(s0)
    andi t6, t2, 2
    beqz t6, 1223f
    sw   t5, 4(s0)
    sh   t5, 18(s0)
1223:
    andi t6, t0, 2
    beqz t6, 1224f
    sb   a2, 12(s0)
    lbu   t2, 23(s0)
1224:
    lh   a4, 10(s0)
    andi t6, t0, 16
    beqz t6, 1225f
    lbu   a3, 1(s0)
    lbu   t2, 7(s0)
    sh   t3, 30(s0)
1225:
    sw   t5, 20(s0)
    lw   a4, 24(s0)
    sw   a3, 8(s0)
    sw   t5, 4(s0)
    lb   a2, 18(s0)
    sb   a2, 25(s0)
    sw   t2, 24(s0)
    lw   t0, 24(s0)
    lw   t0, 24(s0)
    sh   a2, 24(s0)
    sw   a1, 24(s0)
    sb   t0, 25(s0)
    lw   t0, 24(s0)
    lb   a4, 27(s0)
    lb   t2, 11(s0)
    sw   a2, 20(s0)
    add  t1, t1, t4
    sw   t4, 8(s0)
    lb   a3, 23(s0)
    lhu   t0, 18(s0)
    sw   t2, 24(s0)
    sw   t2, 24(s0)
    sb   t1, 26(s0)
    sw   a4, 24(s0)
    lb   t1, 24(s0)
    lw   a2, 24(s0)
    add  t3, t3, t0
    sb   t3, 11(s0)
    lw   t4, 16(s0)
    lbu   a1, 4(s0)
    sub  t4, t4, t3
    sb   t3, 8(s0)
    sb   t4, 11(s0)
    sh   t4, 10(s0)
    lb   t5, 9(s0)
    lw   a1, 8(s0)
    sw   t5, 12(s0)
    lh   t2, 28(s0)
    sw   a2, 0(s0)
    or  t4, t4, a4
    lh   a2, 0(s0)
    lw   a2, 8(s0)
    andi t6, t4, 1
    beqz t6, 1226f
    sh   a2, 0(s0)
    sb   a2, 17(s0)
    sb   a3, 31(s0)
1226:
    or  a3, a3, t0
    lb   t2, 18(s0)
    sw   t2, 0(s0)
    sw   t5, 0(s0)
    sw   a4, 0(s0)
    lw   t3, 0(s0)
    lw   a1, 0(s0)
    sh   a2, 24(s0)
    sw   t3, 24(s0)
    lhu   a2, 26(s0)
    lw   a4, 24(s0)
    andi t6, t4, 2
    beqz t6, 1227f
    sw   t0, 28(s0)
    lw   t0, 16(s0)
1227:
    sw   t0, 24(s0)
    addi s1, s1, -1
    bnez s1, outer
    li   a0, EXIT
    li   t0, 1
    sw   t0, 0(a0)
9:  j    9b
    .data
    .align 5
buf: .space 64
