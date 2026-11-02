    .equ EXIT, 0x20000000
    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la   sp, __stack_top
    la   s0, buf
    li   s1, 4
    li   t0, 128
    li   t1, 31
    li   t2, -1
    li   t3, 32767
    li   t4, 65535
    li   t5, 255
    li   a1, 1419578049
    li   a2, 2
    li   a3, 863983394
    li   a4, 1765911161
    li   a5, 699917290
    li   s2, -2048
    li   s3, 32768
    li   s4, -1898142484
    li   s5, 1
outer:
    slli a5, a3, 9
    lbu   a3, 18(s0)
    call sub3
    mulhu t5, s4, s5
    mul s3, a4, t1
    sw   s4, 24(s0)
    ori t5, a3, -1463
    sw   a3, 28(s0)
    sltiu s5, t0, -248
    and a1, t4, a1
    bgeu  a1, t2, L1
    add s5, a5, s4
    slt s3, t2, t4
    xor s3, a1, t5
    lhu   s5, 56(s0)
L1:
    sltiu t1, a4, -1269
    clmulh a5, t1, s3
    lui  t2, 1023911
    sb   t1, 17(s0)
    andi a5, a4, 404
    xori t5, t0, -328
    xor a4, t0, s5
    sll a1, a2, t1
    clmulr t3, a2, s3
    sw   t1, 56(s0)
    lb   s2, 60(s0)
    lbu   s4, 6(s0)
    srl a2, t1, t1
    sb   a4, 46(s0)
    bltu  t1, s2, L2
    lui  t5, 411409
    sll a4, t4, s5
L2:
    sb   s5, 37(s0)
    mul a1, s2, t5
    lui  a5, 620394
    lh   t1, 48(s0)
    call sub1
    clmulh a4, a1, s4
    li   s6, 5
L3:
    ori a1, t3, -1377
    or t1, a2, s2
    csrw mscratch, t1
    bltu  t4, t4, L4
    sra s5, a5, a1
    andi t3, s3, 1703
    clmulh s4, s3, a4
L4:
    beq  a2, s3, L5
    ori a5, t2, 1454
L5:
    csrr s3, mscratch
    addi s6, s6, -1
    bnez s6, L3
    lb   a5, 59(s0)
    srai a5, s5, 5
    sll t5, s4, a5
    addi t0, s4, -924
    lbu   t5, 4(s0)
    lh   t5, 40(s0)
    mulh s5, t1, s5
    xori t2, t4, -830
    ori s3, t1, -225
    srl s5, t2, t5
    xor t0, t0, a3
    blt  a5, t5, L6
    sw   t1, 8(s0)
    csrw mscratch, s2
L6:
    xor t3, a1, t2
    clmul a2, t0, s2
    lhu   a4, 46(s0)
    lh   s2, 22(s0)
    slti a5, a2, 220
    srai a3, a3, 18
    sb   a3, 62(s0)
    lb   t1, 4(s0)
    bge  t4, t5, L7
    lb   t2, 10(s0)
L7:
    bge  a4, t2, L8
    andi a3, t0, 972
L8:
    csrw mscratch, t1
    lbu   a2, 61(s0)
    xori t5, s5, 1023
    sb   t0, 40(s0)
    clmulr t3, a3, t5
    slti a3, t2, 134
    sh   a2, 32(s0)
    srli t4, t4, 28
    lhu   t1, 42(s0)
    clmul s2, t1, t5
    ori a4, a1, -625
    sb   s4, 39(s0)
    srl a5, a1, t4
    call sub1
    addi t0, t0, -999
    lb   a5, 27(s0)
    slti s4, t1, -2045
    bltu  t1, a3, L9
    srli s3, s2, 7
    andi t2, t1, 788
L9:
    li   s6, 3
L10:
    lb   t3, 62(s0)
    xori t2, t3, 485
    add a3, t4, a4
    andi t3, s2, -320
    clmulr s3, s3, a5
    addi s6, s6, -1
    bnez s6, L10
    sll s4, t5, t3
    ori s5, a3, 2033
    li   s6, 5
L11:
    lw   a2, 40(s0)
    lbu   t2, 54(s0)
    sh   s5, 16(s0)
    addi s6, s6, -1
    bnez s6, L11
    lh   t4, 18(s0)
    lb   s2, 40(s0)
    addi s3, t4, 1115
    lhu   s5, 52(s0)
    lbu   a2, 2(s0)
    sw   a4, 40(s0)
    addi a2, s5, -613
    add a2, t4, t1
    sub a5, s5, t1
    xori a1, s2, -752
    call sub0
    slli a2, a4, 3
    lui  a3, 941137
    lui  s5, 335124
    csrr a4, minstret
    li   s6, 5
L12:
    lh   a2, 20(s0)
    sh   s5, 6(s0)
    lbu   a4, 60(s0)
    ori s2, t3, -1507
    lb   a5, 23(s0)
    addi s6, s6, -1
    bnez s6, L12
    slti a3, t1, 1928
    xori t3, s2, -1
    sh   a3, 14(s0)
    lui  a2, 198101
    addi t5, t4, -1186
    clmul a2, a1, a4
    mulh s4, t2, t0
    clmulh a2, s5, t5
    li   s6, 4
L13:
    csrr a5, minstret
    sh   t2, 24(s0)
    sltu a3, s4, a5
    mul a3, t0, s4
    csrr t5, minstret
    addi s6, s6, -1
    bnez s6, L13
    lui  a3, 873939
    call sub3
    li   s6, 2
L14:
    sltu s3, t2, a5
    srli s4, s5, 5
    xori t4, t1, 2022
    addi s6, s6, -1
    bnez s6, L14
    sltiu a2, s2, -1687
    li   s6, 1
L15:
    csrr t5, mstatus
    sub t4, s2, t5
    lw   t2, 60(s0)
    csrr t0, mscratch
    sb   t5, 46(s0)
    bgeu  s3, a3, L16
    csrr t3, minstret
    lui  t4, 879163
    mulhu t0, t1, s3
L16:
    addi s6, s6, -1
    bnez s6, L15
    addi a3, t4, 637
    bltu  a1, s3, L17
    bgeu  s5, s3, L18
    add s2, t4, s2
    lui  a4, 619484
    lw   t4, 24(s0)
L18:
    clmulh s2, t0, s2
L17:
    sh   t5, 32(s0)
    andi s2, t4, -938
    slti a2, a4, 570
    bgeu  t4, a4, L19
    beq  s5, a3, L20
    mulhsu a4, a2, s2
    csrr a5, minstret
    csrr s2, mscratch
L20:
L19:
    bgeu  t5, a3, L21
    sh   a4, 58(s0)
    sw   s2, 52(s0)
L21:
    srli s2, s3, 20
    xori s4, a2, -1540
    call sub1
    sh   t2, 40(s0)
    clmulh a3, t5, s3
    mulhsu t4, t3, a1
    li   s4, 0
    slli t3, s4, 22
    call sub1
    mulhsu t0, a5, a5
    lb   t3, 16(s0)
    lhu   t4, 10(s0)
    ori t1, a4, 142
    sw   t1, 16(s0)
    lh   t0, 36(s0)
    andi t4, t2, -1552
    bge  s2, t2, L22
    mulhsu a2, a2, t5
L22:
    clmul t0, t5, a4
    slti s5, a3, 156
    call sub2
    clmul a3, a1, t0
    or t4, s4, t5
    addi t0, t0, -472
    sll t1, s3, s5
    slli a4, a4, 28
    slli s2, a5, 16
    sll a3, s5, t5
    clmul a3, s4, t4
    li   t3, 2
    xori t0, s4, 104
    beq  s5, a5, L23
    sw   s4, 44(s0)
    sh   a2, 8(s0)
L23:
    bge  a1, t5, L24
    sra a2, t0, s2
    sub t1, a5, a3
    sb   s5, 27(s0)
L24:
    lui  a2, 182921
    clmulr s4, t5, t4
    or a4, a2, t5
    and t2, a1, s3
    sra s2, t1, t0
    lbu   a3, 17(s0)
    blt  t1, t2, L25
    ori s4, t2, -21
    lhu   t4, 2(s0)
    clmul t0, s3, s2
    clmul t2, t5, s2
L25:
    sll t4, t1, t0
    xor s3, s5, s5
    sh   t5, 42(s0)
    clmulr t0, a4, t2
    lhu   t2, 16(s0)
    mulhsu a3, s2, s5
    and s4, t5, a4
    xori t3, s2, 419
    xor t4, t4, t0
    srai a4, t2, 28
    ori t2, a5, 1329
    ori t0, s2, -407
    lw   s2, 20(s0)
    sb   a4, 1(s0)
    srl t4, a3, a5
    lh   a1, 38(s0)
    xori t0, a1, 413
    or t3, t5, a2
    clmul s5, t1, t0
    sb   t2, 42(s0)
    blt  t2, t5, L26
    clmul a3, t5, s3
    sub s4, a4, s2
L26:
    slti t0, t2, -1014
    sw   t2, 44(s0)
    sw   t5, 40(s0)
    mul a4, a2, a2
    lui  s2, 809368
    srli a3, s2, 0
    lh   t5, 18(s0)
    slt a3, s4, s5
    sb   s2, 5(s0)
    lh   t2, 14(s0)
    lw   t0, 4(s0)
    sw   t2, 0(s0)
    lbu   t1, 53(s0)
    csrr t4, mstatus
    beq  t5, t5, L27
    mulhsu s5, s4, s4
    addi t2, t0, 1544
    sltiu t3, a1, -542
    sw   t2, 12(s0)
L27:
    clmulh a4, t5, t1
    blt  a2, t3, L28
    lbu   s3, 28(s0)
L28:
    lh   a3, 30(s0)
    sb   t1, 44(s0)
    mulhu a1, t3, t0
    csrr t3, mcycle
    call sub1
    andi t1, t1, 36
    bgeu  a1, a2, L29
    mulh a4, s4, s4
    add s5, t4, t4
L29:
    beq  a2, a1, L30
    sb   t2, 51(s0)
    sb   t4, 19(s0)
    lb   t1, 3(s0)
L30:
    srli a2, a3, 10
    srai t5, t3, 27
    srai a5, s5, 0
    blt  t2, t4, L31
    lui  s2, 612834
    sb   a3, 29(s0)
    sh   t2, 32(s0)
L31:
    sw   a5, 60(s0)
    addi t2, a1, -120
    sltu a3, a1, t2
    addi s3, t3, 745
    clmulr s5, t0, t5
    xor a5, t4, t5
    and a3, t4, t3
    sll t5, s2, s5
    call sub2
    sw   s4, 0(s0)
    lui  a5, 816091
    mulh s2, t3, t2
    bgeu  s2, t1, L32
    srli s2, t1, 2
L32:
    add t1, s4, a1
    blt  a2, a3, L33
    csrr a2, minstret
    lw   s2, 28(s0)
    sltiu t2, s3, -476
L33:
    lhu   a5, 54(s0)
    clmulh t1, t3, t2
    lw   t3, 60(s0)
    sra t0, a4, t4
    sltiu a4, s3, 671
    sw   a1, 32(s0)
    sb   t1, 8(s0)
    add t0, a3, a3
    lw   t2, 24(s0)
    clmulh a1, a1, t1
    lw   s5, 4(s0)
    call sub3
    sltu t4, s3, a1
    lui  t4, 970916
    sra s4, t4, s2
    lb   t1, 31(s0)
    srai t0, s3, 29
    srl a3, s3, t0
    call sub0
    sb   t5, 45(s0)
    srl s4, s4, s3
    ori t2, t5, 1543
    xor t1, t4, a1
    sltu a1, t3, t2
    sb   a4, 41(s0)
    slt a4, a5, t0
    sb   t4, 18(s0)
    mulhu t4, t5, t5
    li   t4, 31
    lui  s3, 185777
    addi t3, s2, 875
    lb   a1, 8(s0)
    sltu s2, a1, t3
    lh   s4, 22(s0)
    sb   t0, 59(s0)
    sb   t3, 18(s0)
    lbu   a3, 0(s0)
    sltiu s3, s2, 392
    slt s5, t3, s3
    andi a3, a2, 1856
    srai t5, t1, 23
    sh   t5, 42(s0)
    lw   s2, 52(s0)
    andi a2, t3, 1940
    csrr t2, mscratch
    sltiu s2, a3, 1232
    sra a4, a1, s2
    mulh a2, s4, s2
    clmulh s4, t3, s4
    lui  t3, 796145
    addi t3, s4, 2039
    lbu   a3, 8(s0)
    lbu   t4, 4(s0)
    csrr t5, mcycle
    slli s3, t4, 18
    lui  t1, 435549
    bltu  a1, a5, L34
    sw   t1, 0(s0)
    clmulh s3, s3, a5
    lh   t3, 36(s0)
L34:
    lui  t1, 780111
    srli s3, a4, 11
    sub a5, s5, t1
    lhu   t0, 34(s0)
    csrr t3, mstatus
    clmulr a4, t5, a5
    sb   t0, 56(s0)
    li   s6, 5
L35:
    bgeu  t1, t2, L36
    csrr t2, mstatus
    add a3, s2, t2
    addi a1, t0, 972
L36:
    or a3, a3, t4
    slli a5, a2, 1
    blt  a5, s2, L37
    csrr a1, mstatus
L37:
    mulhsu a1, s3, s3
    addi s6, s6, -1
    bnez s6, L35
    lui  s5, 745751
    add t4, t1, a3
    lbu   t5, 57(s0)
    bne  t3, a2, L38
    lui  a1, 20959
    xor s4, t1, a2
    ori a3, t3, -1038
L38:
    sltu t4, a5, s5
    clmulr s4, t4, t5
    sltu t0, s3, s5
    li   s6, 3
L39:
    clmul t0, t4, s4
    mulhsu t5, t2, a2
    addi s6, s6, -1
    bnez s6, L39
    or t0, t1, t1
    sltiu t1, a2, 1473
    add s5, t3, s3
    blt  t2, a1, L40
    bge  t5, t3, L41
    sw   t5, 60(s0)
    lb   s4, 43(s0)
    sub a3, t3, s5
    lb   s2, 8(s0)
L41:
    csrr s3, mstatus
    sh   s5, 24(s0)
L40:
    sh   t4, 60(s0)
    sb   s5, 34(s0)
    lw   s5, 32(s0)
    mulhsu s3, a3, a3
    sub t2, t4, s4
    addi t1, a5, 1128
    clmul t3, a1, a4
    lh   a4, 60(s0)
    or t4, s2, t1
    sh   t4, 62(s0)
    mulh a1, s4, t3
    addi t2, t3, 77
    sll t0, t5, a2
    xori s5, t4, -1635
    lui  s5, 31383
    clmul s5, a4, t2
    srli a4, t0, 4
    li   s6, 1
L42:
    slli a5, a1, 14
    add t5, a5, t1
    slti a4, s5, 1503
    bltu  t1, a4, L43
    sh   t5, 40(s0)
    csrr s5, mscratch
    ori t3, t4, 1399
    mul s5, a1, t3
L43:
    mul a4, s2, t0
    addi s6, s6, -1
    bnez s6, L42
    bgeu  s3, s5, L44
    lw   t2, 16(s0)
    addi a2, s5, -1750
    srli t5, a4, 30
L44:
    li   s6, 2
L45:
    clmulr s2, a5, s3
    sra a4, a5, a4
    addi s6, s6, -1
    bnez s6, L45
    sra s3, a1, s2
    addi t1, a4, -1387
    bge  a3, t2, L46
    slti s3, t0, -686
    sh   a5, 28(s0)
L46:
    ori a2, t3, 663
    sra s4, t2, t5
    xori t0, s2, -1288
    sh   s3, 62(s0)
    clmulr s5, t2, a5
    slli a3, a3, 16
    li   t0, 0
    blt  s3, a3, L47
    sh   t5, 58(s0)
    csrw mscratch, s2
L47:
    ori s3, a2, -107
    srli a4, s2, 31
    csrr t3, mcycle
    xor t2, t0, t2
    lh   s4, 38(s0)
    and a5, a1, t3
    li   s6, 1
L48:
    csrr s2, minstret
    lbu   a3, 42(s0)
    slti a4, s5, 957
    addi s6, s6, -1
    bnez s6, L48
    mulh t3, s4, s2
    call sub0
    slli a3, t1, 26
    lhu   s2, 34(s0)
    sub a2, t2, t4
    mulh t1, t1, s3
    lbu   a4, 36(s0)
    li   a3, 31
    xori s5, t3, 1672
    srl t1, s3, a2
    bne  s3, a5, L49
    sh   s5, 18(s0)
    lb   t1, 52(s0)
L49:
    sw   t3, 56(s0)
    clmul s4, t0, a3
    sltu s4, t4, s2
    sltiu a2, a3, 784
    mulh t2, t5, s4
    sll a4, s2, a1
    ori t4, t5, -1719
    clmulr s4, t2, s3
    sh   t5, 18(s0)
    slti a1, s3, 1382
    srai t2, t0, 26
    sh   a3, 12(s0)
    csrr t2, mcycle
    slti s5, s4, -305
    sltiu t3, s4, 1520
    li   s6, 2
L50:
    sltiu t2, t2, 1178
    lw   a1, 44(s0)
    lh   t2, 40(s0)
    sh   t3, 6(s0)
    clmulh t2, s4, a3
    addi s6, s6, -1
    bnez s6, L50
    sltiu t1, a1, -129
    xori t0, s2, -1470
    sw   a3, 24(s0)
    clmul a4, t4, s2
    clmulh t4, s4, t4
    xori a4, s4, 253
    lw   s4, 16(s0)
    addi a4, a5, -1716
    sb   a4, 33(s0)
    bgeu  t1, t2, L51
    lui  a1, 351576
    slti t2, a5, 339
    csrr a1, minstret
    sb   s4, 29(s0)
L51:
    mulhsu t0, s2, t0
    lbu   a4, 29(s0)
    mulhu a4, t2, a2
    lb   s3, 39(s0)
    sll t3, a3, a4
    sltu t1, s4, a3
    csrr s2, mstatus
    ori s5, t2, 888
    sra t3, t3, t2
    add a1, s2, s2
    call sub1
    clmul t5, a2, t5
    mulhu a1, t2, a4
    lhu   t0, 26(s0)
    bltu  t4, t5, L52
    csrw mscratch, t4
    srl s2, s4, s5
L52:
    and a5, a2, t5
    sh   a2, 6(s0)
    sb   s5, 9(s0)
    bne  a2, t1, L53
    srl s3, a1, t3
L53:
    bne  t2, a2, L54
    xor a1, s3, a3
    mulhu a5, s2, a4
L54:
    lbu   s4, 38(s0)
    sra a2, t2, a1
    clmulh t2, a2, t2
    xori t4, s3, 397
    sub s5, t0, t4
    csrw mscratch, t3
    clmul t3, t2, t5
    lbu   s2, 43(s0)
    lbu   s3, 41(s0)
    sltiu s3, t3, 815
    srl t1, t0, s2
    sltiu t2, a1, -191
    sltu s4, a3, s5
    lw   a1, 48(s0)
    clmul t0, t0, t1
    csrr t2, mcycle
    bgeu  s5, t3, L55
    clmulh a3, a4, a1
L55:
    srli a4, a4, 29
    li   s6, 3
L56:
    bgeu  a5, t3, L57
    csrr a1, mcycle
L57:
    slli t2, s4, 27
    slt t2, s2, s3
    lw   a1, 32(s0)
    sw   t0, 56(s0)
    and s5, a5, s4
    addi s6, s6, -1
    bnez s6, L56
    beq  a5, t5, L58
    bge  t4, a1, L59
    clmul a2, a5, a1
    sub t0, s3, a5
L59:
    xori s5, s2, 1038
    xor s5, a4, s5
L58:
    bne  t3, a1, L60
    beq  t1, t4, L61
    sw   t5, 28(s0)
    add t4, t2, a5
    csrr t3, mscratch
    csrr t3, mstatus
L61:
    blt  a2, a5, L62
    csrr s4, mscratch
    clmulr s4, s4, t0
    lw   t0, 32(s0)
L62:
    mulhsu t1, a1, t5
L60:
    mulhu t0, s4, t4
    sra t1, t2, s5
    li   s6, 4
L63:
    mulh t3, t2, t5
    csrr t2, mcycle
    add t3, t1, a2
    csrr a4, minstret
    addi s6, s6, -1
    bnez s6, L63
    or a4, a5, a3
    xori a2, t4, 463
    lbu   t2, 32(s0)
    lw   s2, 8(s0)
    lw   a1, 16(s0)
    sw   t0, 32(s0)
    bne  a5, t1, L64
    lhu   t5, 12(s0)
    sb   a3, 48(s0)
L64:
    bge  s5, t3, L65
    sh   a5, 6(s0)
    lh   t3, 30(s0)
    sb   t0, 60(s0)
L65:
    call sub0
    call sub2
    sw   a5, 0(s0)
    lhu   s4, 14(s0)
    sub a4, t4, a4
    sh   a4, 16(s0)
    lbu   t4, 47(s0)
    srai a5, t1, 19
    bltu  a1, s3, L66
    sra a1, t0, a5
    lbu   a1, 21(s0)
L66:
    sub s4, t0, a3
    sh   s5, 50(s0)
    mulh a5, a5, a1
    sltu a2, s3, t4
    bne  a1, t3, L67
    lb   s2, 46(s0)
    li   t1, 2047
    or s4, t1, a4
    sw   a2, 24(s0)
L67:
    sb   a2, 7(s0)
    lbu   t0, 52(s0)
    call sub2
    lui  t3, 413882
    lhu   s5, 16(s0)
    li   s6, 2
L68:
    addi t3, s2, -1063
    bgeu  a5, t0, L69
    clmulr a3, t3, t4
    lw   t0, 40(s0)
    lw   s4, 56(s0)
L69:
    addi s6, s6, -1
    bnez s6, L68
    slti a3, s5, -175
    sw   a1, 56(s0)
    lh   t1, 22(s0)
    lw   s2, 44(s0)
    srl t2, s2, t1
    sb   t1, 11(s0)
    blt  t3, s4, L70
    srai a5, t2, 5
    lh   a3, 30(s0)
    lh   t5, 44(s0)
L70:
    bgeu  s4, t3, L71
    bltu  s5, t1, L72
    csrr s4, mstatus
    add a4, t0, a1
    sw   s3, 56(s0)
L72:
    blt  t3, a5, L73
    csrr a2, minstret
    sh   t4, 20(s0)
L73:
L71:
    lui  a2, 42189
    lw   t2, 8(s0)
    lb   t2, 21(s0)
    lhu   t5, 42(s0)
    beq  a1, t2, L74
    lhu   s3, 4(s0)
    bne  s4, t1, L75
    srl s5, a1, s2
    clmul t4, a1, t1
    srl t2, a3, a2
    sll t5, t2, t0
L75:
L74:
    lbu   t0, 43(s0)
    mulhu a3, s3, a5
    lb   a2, 60(s0)
    srl a1, s2, t1
    sw   t5, 32(s0)
    li   t3, 32767
    addi a3, a3, 1640
    or s4, t2, s5
    sltiu a5, a2, -564
    csrr t4, mcycle
    or s3, t0, a5
    sh   t1, 10(s0)
    sb   t0, 47(s0)
    sb   s5, 22(s0)
    mulhsu s3, t4, s5
    sltiu t2, a4, -1000
    addi t2, t0, -1709
    sltu a5, a2, s4
    mulhu a5, t2, a2
    mulhu a3, a1, a4
    lhu   a3, 52(s0)
    lui  a5, 410517
    lh   a3, 26(s0)
    lb   s5, 17(s0)
    lw   s4, 48(s0)
    mul a3, t3, a1
    lhu   t0, 44(s0)
    sh   a3, 62(s0)
    li   a2, 2147483647
    sub s4, s4, a4
    bne  t2, s5, L76
    xori a1, s5, 1995
L76:
    slli s3, a2, 3
    add a4, t2, t2
    bgeu  t3, t4, L77
    bgeu  s3, t1, L78
    csrr s2, mstatus
L78:
    slti t2, s4, -113
    beq  t3, t1, L79
    xor a5, t0, a4
    lh   t5, 52(s0)
    mulhu t3, t4, a5
    csrr a4, minstret
L79:
L77:
    li   t0, 128
    csrw mscratch, t3
    sll a5, a5, t1
    mulhsu t1, a5, t0
    lhu   s4, 60(s0)
    sw   a4, 0(s0)
    csrw mscratch, a5
    call sub3
    lui  a1, 163735
    lb   a5, 44(s0)
    sb   t0, 39(s0)
    and a5, t0, t0
    bne  t2, t0, L80
    csrr s5, mcycle
    mul t3, s5, a3
L80:
    clmulr s4, a3, t1
    lw   t2, 60(s0)
    mulh t0, a2, t4
    lbu   a4, 18(s0)
    clmulr t1, t3, a2
    clmulr t3, s3, s5
    csrr t0, mstatus
    clmul a2, t2, s2
    li   s6, 5
L81:
    csrw mscratch, a4
    xori a1, a4, -1956
    addi s6, s6, -1
    bnez s6, L81
    mulh t2, t4, s4
    andi a5, t3, -449
    slti s2, t0, -1316
    xor a5, t5, a4
    and s3, t3, s5
    lw   t3, 60(s0)
    sb   a4, 51(s0)
    and t3, s4, t1
    slt s4, t1, t3
    bge  t1, t1, L82
    lui  t3, 1006846
L82:
    sh   t5, 12(s0)
    clmulr a2, a1, t0
    sb   a1, 28(s0)
    beq  a2, s5, L83
    sh   t1, 2(s0)
L83:
    sb   a3, 54(s0)
    lui  s3, 1016029
    andi a1, a3, -730
    slti s3, a4, 1627
    andi a4, s3, 519
    li   s6, 2
L84:
    blt  a4, s4, L85
    lui  a2, 724772
L85:
    sb   s4, 25(s0)
    addi s6, s6, -1
    bnez s6, L84
    mulhsu s5, t5, a2
    srai s5, t4, 6
    clmul s4, t2, a5
    xor a5, s3, t5
    mulhu t2, t3, t0
    addi t2, t4, 887
    mul t5, a2, a2
    lw   a1, 40(s0)
    lh   t4, 14(s0)
    slli s4, a3, 3
    andi a2, t4, -853
    ori t0, a2, -1619
    xor s2, s5, a1
    addi t2, a3, -223
    lbu   s3, 38(s0)
    slti t0, s5, 829
    blt  t3, t2, L86
    sb   a3, 28(s0)
L86:
    bne  t0, t0, L87
    mulh t5, t5, t3
    sb   a2, 33(s0)
    sb   s2, 27(s0)
L87:
    clmulh t2, a2, s4
    bgeu  a4, a3, L88
    or t0, t2, t4
    lb   a4, 14(s0)
    lw   a4, 60(s0)
    sltiu t1, a3, 2035
L88:
    lw   t4, 12(s0)
    clmulr a4, t1, s2
    slti t4, s3, 1488
    sb   a5, 1(s0)
    lui  t3, 815273
    sltu t2, s2, t0
    add s2, s3, a5
    bge  a2, t3, L89
    lw   a2, 32(s0)
    xori a4, s4, 965
    bltu  t2, t1, L90
    clmul s4, s3, s2
    srli a1, t0, 21
    sh   s4, 38(s0)
L90:
    slt a5, a3, t5
L89:
    csrw mscratch, a1
    clmulh t5, a4, s4
    xor a3, t0, s5
    sltiu s4, t0, 679
    sh   a5, 54(s0)
    srl s2, a4, t0
    ori a4, t0, 1183
    xor t4, a5, a3
    sub t0, a1, a5
    li   s4, 2047
    li   s2, 255
    mulhu s2, t5, t3
    li   s6, 1
L91:
    sltu t3, t1, s2
    clmul t0, a2, a3
    addi s6, s6, -1
    bnez s6, L91
    clmulr s3, s4, a2
    lbu   t2, 40(s0)
    lbu   t0, 25(s0)
    clmulh a3, s3, a1
    mulhu s2, s3, a5
    clmulr a3, s2, s3
    andi s2, t4, 830
    lhu   s4, 36(s0)
    lw   s2, 12(s0)
    csrw mscratch, a5
    mulhsu s3, t1, a2
    bge  s4, s2, L92
    csrr s2, mscratch
    lw   s4, 16(s0)
    sltiu a1, t5, 288
    sb   t3, 11(s0)
L92:
    sh   a1, 4(s0)
    sltu a1, t1, s3
    call sub0
    xori s3, a4, 1410
    lw   t1, 36(s0)
    lbu   s5, 16(s0)
    sra a2, a2, t3
    sh   t3, 16(s0)
    xori s5, t0, 180
    sltiu t1, a4, -944
    sltiu t5, s5, 1576
    lw   t1, 4(s0)
    slti s2, t3, -303
    lbu   t1, 60(s0)
    sh   a3, 62(s0)
    or t1, s4, s5
    sw   s2, 8(s0)
    mulh a4, t5, s4
    srli a5, a1, 27
    bgeu  t3, s4, L93
    sw   s5, 40(s0)
    srai t2, a4, 20
L93:
    mulhu t1, t0, t1
    lui  a4, 670791
    lui  a3, 295697
    xor a5, t2, a5
    lh   s3, 2(s0)
    li   t0, 2147483647
    mulhsu a3, a5, a3
    mulhsu t2, s2, s2
    srl s5, s3, a1
    clmul t1, s5, s2
    sh   t1, 58(s0)
    slli t2, a4, 30
    and t1, a3, s4
    li   a1, 1
    ori a3, a1, -814
    li   s6, 5
L94:
    mulh a1, s3, s2
    lh   t5, 16(s0)
    sltiu t1, a1, -181
    addi s6, s6, -1
    bnez s6, L94
    ori a3, t5, -821
    add s3, a2, s3
    clmul s4, s4, t4
    and t3, a5, s5
    ori t1, s4, -1093
    or t3, s4, s2
    srl a4, s5, t0
    bltu  t5, s4, L95
    lh   s4, 30(s0)
    andi a3, s5, 268
    sltu s5, s5, t5
L95:
    xor t4, t0, t2
    csrr a4, minstret
    lbu   s5, 23(s0)
    lh   a2, 8(s0)
    xor t2, t3, t1
    ori t2, t3, -1597
    lbu   t4, 46(s0)
    slti t0, t2, 1284
    li   s6, 3
L96:
    lui  t2, 161382
    srai s5, a3, 16
    csrr a1, mscratch
    li   t2, 128
    addi s6, s6, -1
    bnez s6, L96
    sltu t2, a5, t2
    mulhu t0, a3, s2
    addi s4, t5, 290
    lui  t4, 317534
    li   s6, 1
L97:
    csrr a2, mcycle
    sw   t3, 40(s0)
    addi s6, s6, -1
    bnez s6, L97
    clmulh t4, s5, t2
    addi t2, a4, 630
    slt a1, t2, t5
    lhu   t5, 8(s0)
    clmul t5, s5, t5
    slti t2, a2, -1261
    sw   s3, 24(s0)
    slti t4, a1, 1330
    sltiu t1, t0, 1565
    mul a5, s3, t1
    sltiu s4, s5, 1876
    lh   t5, 56(s0)
    lui  t5, 523217
    lh   s3, 50(s0)
    add a2, a5, a5
    add a3, s2, s5
    sll t3, a5, a1
    lw   s3, 0(s0)
    mulhsu a4, a1, s3
    lb   t3, 8(s0)
    sw   a2, 8(s0)
    lui  t2, 296319
    srai s3, s2, 22
    beq  t5, t4, L98
    csrr t5, minstret
L98:
    clmul t5, a4, a4
    addi a4, a5, 568
    clmulh t3, a5, s5
    mul s4, a5, a3
    mul s5, t2, a2
    bne  t1, t3, L99
    csrr s5, mstatus
    lb   t0, 48(s0)
    lw   t1, 12(s0)
    slti s5, t5, -1628
L99:
    sltiu a1, t3, 1376
    clmulr s3, s2, s3
    mulhsu s4, a5, t4
    csrr a2, minstret
    sltiu s5, s3, 1525
    sll t4, t3, t5
    andi t2, t5, 134
    ori t3, a3, -678
    mulhsu s2, t2, t0
    li   s6, 2
L100:
    mulh t4, a3, t1
    clmulh a2, t1, a1
    csrr t0, mstatus
    srl a1, a5, s3
    lb   a1, 0(s0)
    csrr s3, mcycle
    addi s6, s6, -1
    bnez s6, L100
    csrr t3, mscratch
    slti s4, a3, -367
    sltu a3, s2, s2
    xori s4, t1, 1367
    call sub3
    xori s5, t0, 467
    clmul a5, a4, t5
    mul t1, t5, a5
    ori a5, a2, -979
    mulhsu a4, s3, s5
    sw   a2, 12(s0)
    sw   t3, 36(s0)
    sw   s3, 16(s0)
    bgeu  t0, t5, L101
    clmulh s3, a4, t4
    blt  a5, a2, L102
    addi t5, t5, 440
    csrr a4, minstret
    sw   t2, 28(s0)
    csrr a2, mcycle
L102:
L101:
    lh   s5, 34(s0)
    xor t4, a4, a4
    clmul t0, a3, t2
    sh   s4, 50(s0)
    sh   a3, 28(s0)
    lh   t1, 24(s0)
    slt t1, t3, a2
    sltu t3, s2, s4
    bltu  a1, s2, L103
    csrr t5, mstatus
    csrr a5, mcycle
    mulh a1, s3, s2
L103:
    lhu   a5, 42(s0)
    call sub3
    lw   t2, 60(s0)
    clmulr t2, a2, t2
    sub a5, s3, t1
    sra s4, a4, t0
    sh   a4, 42(s0)
    lh   a2, 28(s0)
    lbu   a1, 12(s0)
    mulh s2, s5, t0
    and a1, t0, t2
    srli t0, t2, 0
    sll t1, a5, t0
    lw   a2, 8(s0)
    clmul a2, t3, a5
    ori t1, s5, -1690
    sb   t0, 41(s0)
    sub t5, t4, t5
    lh   s4, 44(s0)
    lw   t1, 0(s0)
    csrw mscratch, a1
    sb   a4, 9(s0)
    lbu   t3, 0(s0)
    and t2, s3, a2
    mulhu a3, a4, t0
    and t3, a1, a4
    slt t0, t2, a2
    sh   s3, 22(s0)
    srl s4, t2, a1
    sltiu s4, t0, 722
    mulh a2, s3, a3
    xor t2, a1, t2
    sw   a5, 0(s0)
    mulh t2, a3, s2
    sll t2, s2, a2
    lui  a5, 1007406
    lw   t3, 0(s0)
    addi t3, a5, -460
    sh   s4, 8(s0)
    slt a3, a3, s2
    li   s6, 5
L104:
    lb   t3, 47(s0)
    mul t3, a2, t0
    blt  t4, a1, L105
    csrr a2, mcycle
L105:
    lb   t0, 3(s0)
    csrr a1, mstatus
    addi s6, s6, -1
    bnez s6, L104
    mulh a5, t2, a1
    xori t3, t2, 1997
    csrr a5, mstatus
    lw   s5, 44(s0)
    clmul t2, t4, a4
    ori a4, a5, 2014
    bltu  t5, a2, L106
    or s2, s3, s3
    ori a4, a4, 1724
L106:
    lb   a2, 19(s0)
    sll a1, t2, t2
    lb   s5, 25(s0)
    clmulh a4, a5, t5
    slli a2, a1, 25
    lbu   t2, 19(s0)
    sra a1, t3, a1
    sh   a3, 4(s0)
    sw   t2, 44(s0)
    srai t0, s5, 29
    lw   s4, 40(s0)
    lbu   t2, 49(s0)
    clmul t4, a2, t2
    sh   s3, 12(s0)
    bge  s2, a2, L107
    sb   t0, 58(s0)
    clmulh t2, s4, s2
    mul a4, s4, a5
    bge  t0, a2, L108
    sltiu t0, a1, -143
L108:
L107:
    sub s3, s4, s4
    bne  a2, a4, L109
    clmulr a3, t2, a2
    csrr a4, mscratch
    addi t0, t5, 1770
    sw   s4, 8(s0)
L109:
    lb   t2, 6(s0)
    and t5, s4, a2
    li   s5, 32768
    slt s2, a4, t5
    sub s4, t5, t2
    slti s3, a1, 1179
    slt t5, a5, t1
    lh   t2, 12(s0)
    li   s6, 3
L110:
    xori t0, t3, -725
    lui  s5, 327340
    csrr t2, minstret
    slti s3, a5, -1696
    clmul a2, a1, a2
    lbu   s5, 53(s0)
    addi s6, s6, -1
    bnez s6, L110
    slli a3, a3, 16
    ori a5, s2, 6
    sltiu t2, t4, -1395
    lb   a5, 35(s0)
    lb   a4, 19(s0)
    bne  a2, a5, L111
    ori t2, t1, -1565
    ori t0, a5, -679
    lb   t3, 23(s0)
    li   a2, 2
L111:
    srl t0, t4, t5
    sh   s3, 20(s0)
    or s5, t1, t4
    sw   t4, 40(s0)
    clmulh t5, a1, t5
    bne  t0, a1, L112
    csrr a2, minstret
    lh   t4, 52(s0)
    sh   a1, 2(s0)
    lb   t0, 48(s0)
L112:
    sb   t4, 9(s0)
    xori t0, a5, 1253
    srl t0, a4, s3
    andi s5, t2, -658
    xori a5, t5, 970
    lh   t1, 32(s0)
    sw   a1, 4(s0)
    andi s3, a1, 194
    lhu   t3, 26(s0)
    xori s4, s3, -300
    lui  a3, 543504
    lhu   s4, 48(s0)
    csrw mscratch, a4
    lui  a1, 745794
    lhu   t5, 8(s0)
    sltiu t2, a5, -1042
    sw   s5, 60(s0)
    clmulh s2, a3, a2
    bgeu  t3, t3, L113
    bne  t1, s5, L114
    and t1, t5, t4
L114:
    lbu   t5, 31(s0)
L113:
    lb   a2, 31(s0)
    xori s3, s5, 928
    lh   t4, 28(s0)
    srai s5, t4, 14
    sh   s2, 36(s0)
    add t4, t4, t1
    andi s4, t4, 1575
    csrw mscratch, a3
    sh   t0, 16(s0)
    mul a1, s2, a2
    sw   t3, 32(s0)
    call sub0
    srl s4, t5, t0
    lw   a3, 56(s0)
    sra t3, a2, t0
    blt  t3, a3, L115
    sltu t5, a2, a2
L115:
    clmul a1, t0, t1
    csrw mscratch, t2
    andi s2, t2, -1723
    srli s4, a2, 0
    call sub1
    blt  t5, t2, L116
    slli a4, t0, 6
    lw   s4, 8(s0)
    sb   s4, 41(s0)
L116:
    lbu   t5, 18(s0)
    sw   s2, 20(s0)
    lbu   t5, 23(s0)
    lui  t1, 58704
    slli a2, t3, 13
    ori s2, t4, -1063
    addi t4, s4, 996
    clmulh t3, a4, t2
    clmul s3, t0, t2
    sh   t4, 16(s0)
    xori s4, a2, -452
    beq  t5, a2, L117
    bltu  a3, t5, L118
    sra s3, s2, a4
    csrr a3, mcycle
    csrr s4, minstret
    csrr a2, mscratch
L118:
L117:
    lbu   a4, 52(s0)
    sw   s2, 44(s0)
    clmul s5, s5, a3
    sw   s3, 44(s0)
    sw   a5, 44(s0)
    slt a5, a1, a1
    lhu   s3, 58(s0)
    sub s2, t1, t3
    mulh s3, s3, t2
    addi t2, s2, 928
    sltu s5, s5, t2
    or t1, s2, s5
    mulhu t0, s3, s2
    xor t1, s5, s5
    lhu   t4, 10(s0)
    andi t5, t4, 2027
    slt s3, a2, a3
    srli s3, a5, 20
    sll s5, t2, t4
    slt t2, a5, t0
    slt t3, a1, t5
    sltiu t5, a2, -302
    xori a5, s4, 1288
    sh   a4, 16(s0)
    clmulh t5, t2, s4
    srli t2, a2, 22
    slt a4, a2, a5
    sra t3, t0, t0
    lw   s4, 60(s0)
    lw   a2, 0(s0)
    lb   t3, 51(s0)
    lw   s4, 8(s0)
    addi a4, t3, 1244
    add t3, a5, a3
    srli a3, t3, 22
    li   t3, -2048
    csrw mscratch, s4
    lui  t2, 177461
    mulhsu s3, t0, a3
    call sub3
    li   a4, 128
    mulhu s2, s2, s4
    bgeu  s2, a3, L119
    csrr t0, mscratch
    sub t0, s5, a3
    beq  t5, s2, L120
    lw   t3, 24(s0)
    csrw mscratch, a1
L120:
L119:
    bne  s2, s5, L121
    lbu   s5, 37(s0)
    xori t3, t3, -1439
    ori s4, t5, -634
    xor t3, s4, s5
L121:
    li   s6, 5
L122:
    srl a3, t1, a4
    beq  s2, t2, L123
    xori a3, t1, 1709
L123:
    addi s6, s6, -1
    bnez s6, L122
    sltu a5, a2, a1
    call sub1
    sw   s3, 28(s0)
    lbu   a2, 32(s0)
    call sub2
    lhu   t1, 16(s0)
    sw   t1, 28(s0)
    lhu   a4, 2(s0)
    lw   a3, 20(s0)
    xori s3, s5, -733
    ori s5, a2, 394
    li   s2, 32768
    li   s6, 4
L124:
    slti s3, t5, 353
    lw   t2, 32(s0)
    addi s6, s6, -1
    bnez s6, L124
    slt s5, a1, t4
    lbu   a1, 30(s0)
    sltiu s4, t1, -201
    slt t3, s2, t4
    or s2, s5, t0
    xori s2, s3, 958
    sltiu t2, s2, 1352
    sra t1, t0, t5
    call sub2
    or t2, t3, a1
    srl a2, t5, a2
    bgeu  t4, s4, L125
    add a4, s4, a3
    and t1, a2, s4
    bgeu  t0, a2, L126
    xor a4, t4, t5
L126:
    slt a5, t2, t0
L125:
    slti a5, t1, -1074
    lbu   t2, 3(s0)
    sltiu a1, s4, -812
    lh   t5, 38(s0)
    and t0, a5, t3
    xor s4, a4, a3
    lbu   a4, 33(s0)
    lw   s4, 16(s0)
    sltiu s3, s5, 1431
    clmulh s2, a5, t0
    bge  s3, s4, L127
    beq  t3, t5, L128
    sll a1, t1, s3
    sll a1, a2, s2
    clmulr t5, a5, s5
    xori t0, a1, -1629
L128:
    add a5, t5, s3
    lw   s4, 32(s0)
L127:
    clmulh s3, t5, t3
    call sub3
    and a1, a4, s4
    lhu   s5, 46(s0)
    sb   t0, 62(s0)
    lh   a4, 8(s0)
    addi a2, a4, -387
    lbu   a2, 4(s0)
    li   s6, 3
L129:
    lb   a4, 16(s0)
    lui  a4, 207121
    mulhu s2, t5, s2
    addi s6, s6, -1
    bnez s6, L129
    mulhu a1, t2, t2
    clmulr t2, t0, t3
    slli s4, t0, 14
    srli t2, t5, 26
    lb   a2, 60(s0)
    clmulr s4, s5, a4
    lw   s3, 48(s0)
    lhu   t4, 0(s0)
    li   s6, 5
L130:
    bne  t0, a3, L131
    sub s4, s4, s2
    addi t2, t0, 1719
L131:
    lui  s5, 268374
    sub a2, t4, t5
    or t3, s3, a3
    xori s5, t3, -988
    addi s6, s6, -1
    bnez s6, L130
    or a4, s2, t4
    mulhu t2, s3, s4
    sb   a4, 50(s0)
    lw   t0, 4(s0)
    slli a1, t5, 25
    lui  t5, 879414
    srl a3, a3, t0
    lui  s3, 766614
    slli a1, s4, 1
    mulhu s3, t3, t5
    bgeu  t3, s4, L132
    slt s4, a3, s5
L132:
    addi t2, a1, -1044
    sh   s2, 8(s0)
    slli t1, s4, 9
    slti a5, t4, -305
    andi t4, t3, -1482
    sltiu s2, t4, -703
    ori a3, t5, -577
    xor s3, t0, s3
    bge  t5, t4, L133
    and s5, s2, t5
    csrr a1, mscratch
    mulhsu t5, s4, a5
    bne  a4, t1, L134
    clmulh a1, a4, t4
    addi t3, s4, -603
    lhu   s4, 18(s0)
    sh   a5, 10(s0)
L134:
L133:
    sw   a4, 4(s0)
    lb   s2, 15(s0)
    addi a5, s5, -1322
    sltiu t1, t4, -777
    ori a5, t4, -296
    clmulh s5, t1, t0
    srai a3, a4, 29
    srli a4, s3, 7
    li   t1, 1
    xori t2, s4, 305
    sh   a2, 42(s0)
    xori a3, a1, 568
    lbu   t4, 52(s0)
    sw   s3, 16(s0)
    bgeu  t5, s3, L135
    li   t2, 32767
L135:
    lb   t2, 61(s0)
    xor s3, t1, a1
    xori t3, t0, -735
    lw   t0, 44(s0)
    sb   t2, 4(s0)
    lui  a2, 755536
    lw   a3, 60(s0)
    sh   a5, 16(s0)
    mulhsu a1, a4, t5
    andi a2, a3, 1099
    add t5, t1, t5
    sltu s5, s5, s4
    sb   a5, 39(s0)
    lb   a2, 30(s0)
    call sub2
    clmulh t2, s2, t5
    call sub1
    sw   a2, 44(s0)
    clmulh s4, t3, t0
    lw   s5, 4(s0)
    slti a4, a5, 49
    lw   t5, 56(s0)
    bge  a4, s2, L136
    slt t3, a3, t2
    sb   s2, 7(s0)
    mul t2, a2, a5
    lui  a5, 200551
L136:
    bne  a1, s4, L137
    sb   a4, 15(s0)
    lb   a3, 62(s0)
L137:
    blt  a3, t5, L138
    sra t5, t2, s3
    beq  s2, s4, L139
    and t3, t1, a2
    lw   t0, 32(s0)
L139:
    blt  t4, t2, L140
    lw   a1, 20(s0)
    sh   a4, 22(s0)
    csrr t5, mcycle
L140:
    csrr s2, mscratch
L138:
    blt  t1, t5, L141
    ori a5, a4, 1103
    sh   t3, 2(s0)
    csrr s2, mcycle
L141:
    ori s4, t2, -1001
    clmulh a3, t0, a3
    sh   a3, 60(s0)
    sh   t3, 8(s0)
    srli s4, t5, 21
    clmul a3, t1, s5
    ori t3, a2, 1824
    lw   s5, 20(s0)
    add t4, s5, t2
    ori t1, s4, 134
    ori t3, t1, 1433
    csrw mscratch, t0
    clmul t5, t0, t1
    clmulr a4, a5, t4
    bltu  s4, a2, L142
    clmulr a5, t4, a5
    lhu   a5, 32(s0)
    li   a5, 32768
L142:
    lb   t4, 6(s0)
    call sub1
    mul t2, a1, t0
    srai t3, s4, 6
    slt t0, a1, s4
    clmulr s3, a2, t5
    andi a4, s4, -2013
    slti a5, t5, 440
    sh   t2, 4(s0)
    sb   t5, 32(s0)
    and t2, s5, s4
    lb   s2, 55(s0)
    srl a3, t2, a5
    clmulr s3, t2, a3
    sh   t0, 2(s0)
    addi a2, a4, -14
    clmulr a1, t0, t3
    and a4, t3, a5
    sh   t3, 30(s0)
    bgeu  a3, a2, L143
    sh   s5, 48(s0)
    sb   t3, 8(s0)
    srli t5, t4, 2
    lh   a2, 32(s0)
L143:
    slt s5, t0, t3
    mulhsu a3, a4, a1
    li   t0, 32
    li   s6, 5
L144:
    sra a2, a4, t4
    sub s4, t2, a1
    clmulh t4, t3, s4
    lh   t5, 62(s0)
    mul s3, t2, s4
    mulhsu t4, t0, a5
    addi s6, s6, -1
    bnez s6, L144
    sb   s5, 54(s0)
    sra s5, t0, t2
    bgeu  a4, a1, L145
    beq  a2, s3, L146
    lbu   s5, 42(s0)
    srli s3, t0, 14
L146:
    csrr s2, mstatus
    xori t4, t3, 814
L145:
    sll t2, s3, s3
    sb   s4, 57(s0)
    slli a5, a1, 10
    li   s6, 1
L147:
    ori t1, a1, 1036
    sb   t3, 58(s0)
    sltu t4, t0, a4
    ori a5, s2, 415
    addi s6, s6, -1
    bnez s6, L147
    slti t5, a5, -538
    add t1, s5, t4
    mulh s5, s5, a2
    xor s3, s3, s5
    sltiu t4, t4, -1281
    ori s2, t0, -1956
    lw   s2, 24(s0)
    csrr t2, mcycle
    sub a2, a3, a4
    li   s6, 5
L148:
    lw   s2, 20(s0)
    bne  t0, a2, L149
    csrr s2, minstret
    sll s2, a3, t0
    sw   a1, 32(s0)
L149:
    addi s6, s6, -1
    bnez s6, L148
    lh   t2, 54(s0)
    sltu a5, s4, t4
    lb   t0, 32(s0)
    andi a1, a5, -1461
    clmul s3, t1, a5
    lh   a1, 34(s0)
    srl a1, t5, s5
    bltu  t4, t3, L150
    slti t0, a2, 921
L150:
    sw   a1, 24(s0)
    lh   t5, 4(s0)
    lhu   t5, 12(s0)
    sra a1, a1, s5
    sw   t5, 32(s0)
    sll s5, t2, t5
    srl t2, a3, t2
    xori t4, a1, -507
    add a3, t0, t4
    mulhsu t1, s4, t2
    li   s6, 2
L151:
    add s3, s3, a2
    ori t1, s2, -932
    addi s6, s6, -1
    bnez s6, L151
    bge  a5, s3, L152
    sb   t1, 15(s0)
    ori t0, s4, 1707
L152:
    sltu t5, t4, s3
    beq  t4, t3, L153
    csrr s2, mstatus
    lbu   a5, 9(s0)
    andi t1, s3, -1676
L153:
    li   s6, 5
L154:
    lbu   a5, 54(s0)
    csrr t2, minstret
    sltiu s3, t0, 1048
    srl t5, a1, s2
    addi s6, s6, -1
    bnez s6, L154
    lui  a4, 674134
    call sub2
    sb   t4, 13(s0)
    or t1, a5, t3
    bge  s5, t0, L155
    xor t4, s5, a2
    lbu   s3, 39(s0)
    mulhsu s2, t4, t2
L155:
    mul s4, a5, s4
    li   t4, 32
    bltu  a4, a2, L156
    xori s3, a2, -1473
    lhu   s5, 48(s0)
    srl t3, s4, t0
L156:
    mulhu t0, t5, a1
    lw   a5, 16(s0)
    li   t2, 1
    sh   t0, 36(s0)
    sub a5, a4, t1
    mul t3, t2, t0
    andi t3, s4, -131
    sw   a1, 0(s0)
    li   s6, 3
L157:
    xor a5, t5, s3
    sub s4, t5, a2
    srai t3, s4, 27
    sra a2, s4, a2
    addi s6, s6, -1
    bnez s6, L157
    srl a2, a1, t0
    clmulr s5, s3, s2
    srl a2, a5, t5
    addi t1, s3, 907
    clmulr s4, t0, t5
    slt a3, t3, t2
    sw   t3, 52(s0)
    or s5, t4, a4
    srli t1, t4, 21
    call sub1
    call sub1
    call sub2
    sll t5, s2, t0
    add t2, t0, s3
    slti t5, a3, 1828
    mulh s4, t1, s2
    sltu t2, t2, a1
    sw   t5, 20(s0)
    clmulr a2, a5, a5
    srai a2, t4, 9
    lhu   a2, 50(s0)
    li   s4, 32767
    sll t2, t0, t3
    lbu   s4, 36(s0)
    bge  s3, a2, L158
    sh   s2, 16(s0)
    csrr a5, mcycle
    csrr s4, mcycle
L158:
    mulh t1, a4, a5
    sw   t0, 44(s0)
    lw   a3, 56(s0)
    andi t2, s5, -683
    mulhsu t3, t3, t0
    lh   a5, 38(s0)
    sw   a4, 36(s0)
    lhu   t3, 28(s0)
    lui  a1, 1039104
    li   s6, 3
L159:
    andi a1, t5, -559
    mulhsu s4, a2, s3
    lb   t1, 33(s0)
    csrr t2, mscratch
    addi s6, s6, -1
    bnez s6, L159
    csrw mscratch, s3
    call sub0
    sll a1, t0, a1
    lw   t5, 20(s0)
    mulhsu a4, t5, s5
    xori s4, s2, -1231
    sltiu a4, t1, -1717
    add t5, t4, t5
    lb   t1, 21(s0)
    lui  t4, 340505
    sub t2, a4, t5
    li   s6, 4
L160:
    sw   a2, 48(s0)
    ori a3, t1, -732
    ori a3, s4, 249
    lb   a5, 60(s0)
    andi t3, s5, -1842
    addi s6, s6, -1
    bnez s6, L160
    sw   s2, 0(s0)
    clmul a3, a5, a5
    li   s6, 4
L161:
    sll a5, s4, a2
    andi t1, t2, 22
    addi s6, s6, -1
    bnez s6, L161
    call sub3
    li   t5, 255
    slt t3, a4, a5
    mulh a5, a1, a5
    add t3, t1, t0
    add t4, t1, a1
    sh   a5, 0(s0)
    sh   a1, 30(s0)
    mulhu t2, a5, s4
    slti a1, a3, -396
    or t5, s2, a3
    bgeu  a1, t0, L162
    sw   t3, 20(s0)
L162:
    sh   s3, 38(s0)
    sb   t3, 60(s0)
    lw   a5, 4(s0)
    csrw mscratch, a2
    add t3, a1, t2
    sh   a3, 44(s0)
    slt a5, t4, t5
    beq  s3, a2, L163
    bltu  a5, a3, L164
    lw   t4, 40(s0)
L164:
    or a5, t4, t2
L163:
    sb   t3, 6(s0)
    lui  a4, 549966
    srai s4, t3, 10
    lh   t3, 58(s0)
    lb   t3, 28(s0)
    sw   s2, 8(s0)
    mulh t4, s5, a4
    ori a3, t3, 1198
    slti a5, t5, -242
    add s5, a1, s5
    lui  t3, 374164
    xori t4, a3, 693
    lw   t4, 52(s0)
    li   t5, -2147483648
    lhu   t4, 40(s0)
    bltu  t0, a1, L165
    csrr t5, mscratch
    slli s2, a4, 11
    sw   a5, 48(s0)
    andi s2, a2, 938
L165:
    bge  s3, s3, L166
    lh   a5, 0(s0)
    addi t3, s2, -1025
L166:
    beq  t2, t4, L167
    slt s2, a3, t1
    bne  s5, t0, L168
    sh   a3, 2(s0)
    lui  a2, 405270
    mulhsu a1, t2, t0
L168:
    lhu   s3, 44(s0)
L167:
    li   s6, 3
L169:
    li   a3, 2147483647
    clmulr a5, s5, a1
    slli a5, t3, 7
    clmulr t3, a5, s3
    add t1, s2, a5
    csrr t3, mstatus
    addi s6, s6, -1
    bnez s6, L169
    call sub0
    lbu   a2, 48(s0)
    lui  t2, 952541
    li   a5, -1
    sll a2, t5, s3
    srl t1, t3, t1
    add t3, a2, a1
    clmulr a2, a1, a3
    lb   s4, 21(s0)
    sub a1, a4, t5
    lb   a1, 14(s0)
    addi s1, s1, -1
    bnez s1, outer
    li   a0, EXIT
    li   t0, 1
    sw   t0, 0(a0)
9:  j    9b
sub0:
    clmul t1, a2, a1
    or a5, s2, t1
    mulh s5, a5, t3
    or a2, t4, t1
    mv   s7, ra
    la   s8, sub3
    jalr ra, 0(s8)
    mv   ra, s7
    ret
sub1:
    mulh t2, a5, t5
    lhu   a3, 18(s0)
    ret
sub2:
    clmulh a1, t4, t4
    lbu   a3, 55(s0)
    ret
sub3:
    lbu   t5, 15(s0)
    add s3, t4, t3
    or t3, t0, t1
    ret
    .data
    .align 6
buf: .space 128
