    .equ EXIT, 0x20000000
    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la   sp, __stack_top
    la   s0, buf
    li   s1, 12             /* outer iterations */
    li   s2, 0x1234567      /* LFSR */
    li   t0, 912006184
    li   t1, -1363257452
    li   t2, 2140107612
    li   t3, -1313849899
    li   t4, 887188596
    li   a1, 1142215581
    li   a2, -251780636
    li   a3, -1651012212
    li   a4, 72561223
    li   a5, 1967785814
outer:
    slli t5, s2, 13
    xor  s2, s2, t5
    srli t5, s2, 17
    xor  s2, s2, t5
    slli t5, s2, 5
    xor  s2, s2, t5
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1
    addi a5, t2, 74
L1:
    sh   t4, 0(s3)
    andi t5, s2, 256
    bnez t5, L2
    addi t0, t3, 1
L2:
    lhu   t1, 18(s0)
    lw   t3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L3
    xor  a4, t4, t3
L3:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L4
    xor  t2, t2, a1
L4:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L5
    xor  a5, t2, a3
L5:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L6
    addi t4, a1, 64
L6:
    sw   a2, 0(s3)
    andi t5, s2, 16
    bnez t5, L7
    addi t1, a3, 1
L7:
    lhu   t4, 10(s0)
    lb   a1, 15(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L8
    xor  a3, a1, a3
L8:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L9
    xor  t0, t1, a1
L9:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L10
    xor  a4, a3, a5
L10:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L11
    addi t2, a1, 90
L11:
    andi t5, s2, 2
    beqz t5, L12
    addi t4, a4, -97
L12:
    sb   a2, 0(s3)
    andi t5, s2, 16
    bnez t5, L13
    addi a3, a2, 1
L13:
    andi t5, s2, 1024
    bnez t5, L14
    addi a1, t0, 1
L14:
    lw   a3, 28(s0)
    lw   t2, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L15
    xor  a3, t2, t2
L15:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L16
    xor  t1, t0, t3
L16:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L17
    addi t2, t1, -64
L17:
    andi t5, s2, 256
    beqz t5, L18
    addi a5, a4, 27
L18:
    sh   t4, 0(s3)
    andi t5, s2, 128
    bnez t5, L19
    addi a2, t2, 1
L19:
    andi t5, s2, 32
    beqz t5, L20
    addi t3, a4, 1
L20:
    lw   t2, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L21
    xor  a5, t2, t3
L21:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L22
    xor  a5, a5, t3
L22:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L23
    xor  t1, t3, t3
L23:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L24
    addi t2, t2, -52
L24:
    andi t5, s2, 8
    beqz t5, L25
    addi t3, t4, -22
L25:
    sb   a5, 0(s3)
    andi t5, s2, 32
    bnez t5, L26
    addi t3, t4, 1
L26:
    lhu   t0, 14(s0)
    lhu   a5, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L27
    xor  a4, a2, a1
L27:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L28
    xor  a1, a3, a3
L28:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L29
    addi t1, t2, 32
L29:
    andi t5, s2, 1
    bnez t5, L30
    addi a4, t1, 49
L30:
    sh   t3, 0(s3)
    andi t5, s2, 32
    beqz t5, L31
    addi t1, a4, 1
L31:
    lhu   a5, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L32
    xor  t4, t2, t4
L32:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L33
    xor  a2, a5, t0
L33:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L34
    addi a3, t2, 37
L34:
    sw   a5, 0(s3)
    andi t5, s2, 2
    beqz t5, L35
    addi a1, t2, 1
L35:
    andi t5, s2, 1024
    beqz t5, L36
    addi a5, t3, 1
L36:
    lw   a5, 24(s0)
    lw   t4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L37
    xor  a3, a4, a1
L37:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L38
    xor  a3, t3, t2
L38:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L39
    xor  t4, t2, a4
L39:
    sw   a4, 12(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L40
    addi a1, a5, 97
L40:
    sb   a5, 0(s3)
    andi t5, s2, 4
    beqz t5, L41
    addi a1, t4, 1
L41:
    lw   t1, 12(s0)
    lb   a5, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L42
    xor  t3, t3, t4
L42:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L43
    xor  a4, a5, a5
L43:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L44
    xor  t4, t1, t0
L44:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L45
    xor  a5, a2, t2
L45:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L46
    addi t4, t1, -47
L46:
    andi t5, s2, 2
    bnez t5, L47
    addi t4, t2, 53
L47:
    andi t5, s2, 32
    beqz t5, L48
    addi t3, a2, -39
L48:
    sw   a5, 0(s3)
    andi t5, s2, 2
    beqz t5, L49
    addi t1, a5, 1
L49:
    andi t5, s2, 16
    bnez t5, L50
    addi a2, a4, 1
L50:
    lw   t4, 20(s0)
    lb   a2, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L51
    xor  t1, a3, t0
L51:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L52
    xor  a5, a3, t0
L52:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L53
    addi a1, t1, 47
L53:
    andi t5, s2, 512
    bnez t5, L54
    addi t1, a1, 91
L54:
    sh   t4, 0(s3)
    andi t5, s2, 1024
    bnez t5, L55
    addi t2, a4, 1
L55:
    andi t5, s2, 8
    beqz t5, L56
    addi t2, t3, 1
L56:
    lb   a2, 6(s0)
    lb   t4, 25(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L57
    xor  t3, a2, t1
L57:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L58
    xor  t3, a3, a1
L58:
    sw   a5, 0(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L59
    addi t2, t1, 42
L59:
    andi t5, s2, 256
    beqz t5, L60
    addi t3, t3, 84
L60:
    sh   a4, 0(s3)
    andi t5, s2, 8
    bnez t5, L61
    addi t3, a3, 1
L61:
    andi t5, s2, 16
    beqz t5, L62
    addi a4, a2, 1
L62:
    lw   a1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L63
    xor  t2, t3, t4
L63:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L64
    xor  a1, a3, t4
L64:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L65
    addi a3, a1, -65
L65:
    andi t5, s2, 256
    beqz t5, L66
    addi t4, t0, -1
L66:
    sw   a2, 0(s3)
    andi t5, s2, 64
    beqz t5, L67
    addi t2, t3, 1
L67:
    andi t5, s2, 512
    beqz t5, L68
    addi t4, t4, 1
L68:
    lw   t2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L69
    xor  t3, t1, a3
L69:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L70
    xor  t3, a2, t2
L70:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L71
    addi t0, t2, 64
L71:
    andi t5, s2, 32
    bnez t5, L72
    addi t2, a3, 22
L72:
    andi t5, s2, 1024
    beqz t5, L73
    addi t1, a1, -33
L73:
    sw   a1, 0(s3)
    andi t5, s2, 16
    bnez t5, L74
    addi a3, t2, 1
L74:
    lb   t1, 18(s0)
    lw   t0, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L75
    xor  t3, t1, t3
L75:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L76
    xor  t0, t2, a5
L76:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L77
    addi a5, t0, -52
L77:
    andi t5, s2, 4
    beqz t5, L78
    addi t0, t1, 44
L78:
    andi t5, s2, 1
    beqz t5, L79
    addi a2, a1, 94
L79:
    sh   t1, 0(s3)
    andi t5, s2, 4
    bnez t5, L80
    addi t0, t1, 1
L80:
    andi t5, s2, 1024
    beqz t5, L81
    addi a2, t0, 1
L81:
    lhu   a1, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L82
    xor  t1, t2, a2
L82:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L83
    xor  t3, t4, a2
L83:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L84
    xor  a2, t3, a2
L84:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L85
    xor  a1, a5, a2
L85:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L86
    addi a5, t2, -30
L86:
    andi t5, s2, 4
    beqz t5, L87
    addi a2, a5, -70
L87:
    sh   a1, 0(s3)
    andi t5, s2, 1024
    bnez t5, L88
    addi a1, t2, 1
L88:
    lw   a5, 24(s0)
    lw   a1, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L89
    xor  a3, t2, a1
L89:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L90
    xor  t4, a4, t4
L90:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L91
    xor  t4, a5, a4
L91:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L92
    addi t3, t4, -19
L92:
    andi t5, s2, 32
    beqz t5, L93
    addi t2, t0, -35
L93:
    sw   a1, 0(s3)
    andi t5, s2, 128
    beqz t5, L94
    addi t0, a5, 1
L94:
    andi t5, s2, 32
    beqz t5, L95
    addi t2, a4, 1
L95:
    lhu   t2, 30(s0)
    lb   t4, 5(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L96
    xor  t3, t4, a1
L96:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L97
    xor  a4, t1, a2
L97:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L98
    xor  a2, t2, t1
L98:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L99
    xor  a5, t1, a2
L99:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L100
    addi a4, t2, -98
L100:
    sw   a2, 0(s3)
    andi t5, s2, 32
    bnez t5, L101
    addi t1, a1, 1
L101:
    andi t5, s2, 128
    bnez t5, L102
    addi t4, t1, 1
L102:
    lw   a3, 4(s0)
    lhu   t3, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L103
    xor  a4, a5, a1
L103:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L104
    xor  t4, a3, t0
L104:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L105
    xor  t2, a2, t0
L105:
    sw   t2, 16(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L106
    addi t0, a3, 26
L106:
    andi t5, s2, 512
    bnez t5, L107
    addi a1, t2, -78
L107:
    sb   t0, 0(s3)
    andi t5, s2, 32
    bnez t5, L108
    addi a2, a2, 1
L108:
    lb   t2, 1(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L109
    xor  a1, t4, t4
L109:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L110
    xor  t1, t4, t2
L110:
    sw   a2, 20(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L111
    addi t4, a5, -57
L111:
    andi t5, s2, 1
    beqz t5, L112
    addi a1, a5, 70
L112:
    andi t5, s2, 256
    bnez t5, L113
    addi t4, t4, 54
L113:
    sb   t4, 0(s3)
    andi t5, s2, 128
    bnez t5, L114
    addi a3, t2, 1
L114:
    lb   a2, 7(s0)
    lb   t3, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L115
    xor  a4, a2, a3
L115:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L116
    xor  a4, a1, a3
L116:
    sw   a5, 16(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L117
    addi a1, t3, -77
L117:
    sw   a2, 0(s3)
    andi t5, s2, 4
    beqz t5, L118
    addi a4, a2, 1
L118:
    andi t5, s2, 16
    bnez t5, L119
    addi a1, a2, 1
L119:
    lhu   a1, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L120
    xor  t0, t0, t0
L120:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L121
    xor  a1, a5, a3
L121:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L122
    xor  a3, t4, t3
L122:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L123
    xor  a3, a3, t1
L123:
    sw   a3, 8(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L124
    addi t0, t2, 85
L124:
    andi t5, s2, 16
    bnez t5, L125
    addi t3, a3, -8
L125:
    sw   t3, 0(s3)
    andi t5, s2, 1
    bnez t5, L126
    addi t3, t3, 1
L126:
    lw   a3, 0(s0)
    lhu   a2, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L127
    xor  a3, t1, t4
L127:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L128
    xor  a5, a1, t2
L128:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L129
    xor  t4, a1, a1
L129:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L130
    xor  t4, a4, t4
L130:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L131
    addi a2, a2, 84
L131:
    andi t5, s2, 64
    beqz t5, L132
    addi t1, t4, -26
L132:
    andi t5, s2, 2
    beqz t5, L133
    addi t2, a2, -93
L133:
    sh   a1, 0(s3)
    andi t5, s2, 16
    beqz t5, L134
    addi a3, a5, 1
L134:
    lb   a5, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L135
    xor  t2, t3, t4
L135:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L136
    xor  a2, a4, t4
L136:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L137
    xor  t3, a5, a5
L137:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L138
    addi a1, t0, 82
L138:
    andi t5, s2, 16
    bnez t5, L139
    addi a4, a1, -18
L139:
    andi t5, s2, 128
    beqz t5, L140
    addi t0, t4, 59
L140:
    sw   a4, 0(s3)
    andi t5, s2, 8
    beqz t5, L141
    addi a2, a3, 1
L141:
    andi t5, s2, 4
    bnez t5, L142
    addi t4, a1, 1
L142:
    lb   t3, 3(s0)
    lw   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L143
    xor  a2, a3, a1
L143:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L144
    xor  a3, a5, t2
L144:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L145
    addi a3, t2, -8
L145:
    sb   a2, 0(s3)
    andi t5, s2, 2
    bnez t5, L146
    addi t1, t4, 1
L146:
    andi t5, s2, 256
    beqz t5, L147
    addi t3, t4, 1
L147:
    lb   t4, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L148
    xor  t1, t4, t2
L148:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L149
    xor  t0, t3, a2
L149:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L150
    xor  a3, t1, a2
L150:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L151
    addi a1, t2, 0
L151:
    andi t5, s2, 8
    bnez t5, L152
    addi a4, t0, -8
L152:
    sw   t1, 0(s3)
    andi t5, s2, 256
    bnez t5, L153
    addi a4, a5, 1
L153:
    andi t5, s2, 8
    bnez t5, L154
    addi a2, t1, 1
L154:
    lw   t2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L155
    xor  a3, a3, a1
L155:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L156
    xor  a5, a3, a2
L156:
    sw   a4, 24(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L157
    addi t1, t4, 76
L157:
    andi t5, s2, 1024
    bnez t5, L158
    addi t1, a1, -28
L158:
    sw   a5, 0(s3)
    andi t5, s2, 4
    beqz t5, L159
    addi a3, t0, 1
L159:
    lb   a2, 0(s0)
    lb   t0, 23(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L160
    xor  t2, t1, t4
L160:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L161
    xor  t4, t3, t2
L161:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L162
    xor  a1, a4, a3
L162:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L163
    xor  a2, t2, t3
L163:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L164
    addi a3, t2, -12
L164:
    andi t5, s2, 256
    bnez t5, L165
    addi t2, t4, -7
L165:
    andi t5, s2, 512
    bnez t5, L166
    addi t4, t4, 54
L166:
    sh   t1, 0(s3)
    andi t5, s2, 4
    beqz t5, L167
    addi t4, a2, 1
L167:
    andi t5, s2, 1
    bnez t5, L168
    addi t1, t4, 1
L168:
    lw   t3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L169
    xor  a4, t2, t2
L169:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L170
    xor  a3, t1, t2
L170:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L171
    xor  t2, t4, a3
L171:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L172
    xor  t2, a3, t2
L172:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L173
    addi t3, a4, 41
L173:
    sh   t1, 0(s3)
    andi t5, s2, 64
    bnez t5, L174
    addi t2, a1, 1
L174:
    lb   t3, 21(s0)
    lw   a2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L175
    xor  t1, a3, t3
L175:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L176
    xor  a4, a1, a2
L176:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L177
    xor  a3, t0, a2
L177:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L178
    addi t1, a2, 33
L178:
    andi t5, s2, 512
    beqz t5, L179
    addi t3, t4, 34
L179:
    sw   a3, 0(s3)
    andi t5, s2, 1024
    beqz t5, L180
    addi t3, a5, 1
L180:
    andi t5, s2, 64
    beqz t5, L181
    addi t1, t4, 1
L181:
    lw   a3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L182
    xor  t3, a1, t3
L182:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L183
    xor  a2, a2, t4
L183:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L184
    xor  t2, t2, a1
L184:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L185
    xor  t0, t0, a2
L185:
    sw   a4, 8(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L186
    addi t1, t0, 29
L186:
    andi t5, s2, 8
    beqz t5, L187
    addi t1, t1, 46
L187:
    sh   t3, 0(s3)
    andi t5, s2, 64
    bnez t5, L188
    addi t4, t4, 1
L188:
    lb   t0, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L189
    xor  a5, t0, t1
L189:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L190
    xor  t2, a4, a5
L190:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L191
    addi t1, a3, -44
L191:
    andi t5, s2, 1
    beqz t5, L192
    addi t0, t4, 16
L192:
    sw   a4, 0(s3)
    andi t5, s2, 4
    bnez t5, L193
    addi t1, a3, 1
L193:
    lhu   a5, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L194
    xor  t0, t1, a3
L194:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L195
    xor  t0, a3, a1
L195:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L196
    xor  t4, a1, t3
L196:
    sw   a1, 4(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L197
    addi a5, t3, -50
L197:
    andi t5, s2, 512
    beqz t5, L198
    addi a4, t0, -43
L198:
    sw   a5, 0(s3)
    andi t5, s2, 16
    beqz t5, L199
    addi t1, a3, 1
L199:
    andi t5, s2, 512
    beqz t5, L200
    addi a2, t1, 1
L200:
    lhu   a3, 30(s0)
    lb   a4, 19(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L201
    xor  t4, a1, a2
L201:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L202
    xor  t4, t0, a5
L202:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L203
    addi t2, a3, 23
L203:
    andi t5, s2, 2
    beqz t5, L204
    addi a3, t4, 80
L204:
    sw   a1, 0(s3)
    andi t5, s2, 64
    beqz t5, L205
    addi a1, a3, 1
L205:
    lb   a2, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L206
    xor  a4, t0, t2
L206:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L207
    xor  t4, t4, a2
L207:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L208
    xor  t2, t3, a1
L208:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L209
    addi a1, t2, 16
L209:
    sw   t0, 0(s3)
    andi t5, s2, 128
    bnez t5, L210
    addi a3, a4, 1
L210:
    andi t5, s2, 32
    bnez t5, L211
    addi a5, a3, 1
L211:
    lw   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L212
    xor  t1, a1, a3
L212:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L213
    xor  t4, a2, t2
L213:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L214
    xor  a3, a5, t1
L214:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L215
    xor  a4, a5, t4
L215:
    sw   t4, 0(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L216
    addi t0, t1, 32
L216:
    andi t5, s2, 256
    bnez t5, L217
    addi t4, t3, 57
L217:
    sb   t3, 0(s3)
    andi t5, s2, 16
    beqz t5, L218
    addi a4, a3, 1
L218:
    andi t5, s2, 128
    bnez t5, L219
    addi t0, t3, 1
L219:
    lb   a5, 4(s0)
    lb   t3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L220
    xor  a2, a5, t3
L220:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L221
    xor  a3, t3, t3
L221:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L222
    xor  a3, t3, a1
L222:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L223
    addi a5, t0, 83
L223:
    andi t5, s2, 2
    beqz t5, L224
    addi t1, a4, -59
L224:
    andi t5, s2, 1
    beqz t5, L225
    addi a5, t4, -95
L225:
    sb   t4, 0(s3)
    andi t5, s2, 1024
    beqz t5, L226
    addi t0, a2, 1
L226:
    andi t5, s2, 512
    beqz t5, L227
    addi t1, t0, 1
L227:
    lb   t4, 6(s0)
    lb   t4, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L228
    xor  a3, a1, t4
L228:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L229
    xor  a1, a4, a3
L229:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L230
    addi t2, t1, -61
L230:
    andi t5, s2, 64
    bnez t5, L231
    addi a4, a1, -9
L231:
    andi t5, s2, 64
    bnez t5, L232
    addi a2, a1, -10
L232:
    sw   a4, 0(s3)
    andi t5, s2, 32
    beqz t5, L233
    addi a5, t3, 1
L233:
    andi t5, s2, 4
    bnez t5, L234
    addi t0, t2, 1
L234:
    lb   t1, 27(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L235
    xor  a4, a4, a5
L235:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L236
    xor  a4, a4, a3
L236:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L237
    xor  a3, t2, a5
L237:
    sw   a2, 24(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L238
    addi t0, t0, 25
L238:
    sw   a5, 0(s3)
    andi t5, s2, 512
    beqz t5, L239
    addi a5, a1, 1
L239:
    andi t5, s2, 8
    beqz t5, L240
    addi a5, a1, 1
L240:
    lw   t3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L241
    xor  t1, t0, a2
L241:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L242
    xor  a4, t4, t1
L242:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L243
    xor  a4, a4, a2
L243:
    sw   t0, 12(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L244
    addi t1, a5, 2
L244:
    andi t5, s2, 256
    bnez t5, L245
    addi a4, a3, 48
L245:
    andi t5, s2, 1
    bnez t5, L246
    addi a1, t0, 1
L246:
    sh   a2, 0(s3)
    andi t5, s2, 128
    beqz t5, L247
    addi a2, a2, 1
L247:
    andi t5, s2, 1024
    bnez t5, L248
    addi a4, t4, 1
L248:
    lw   t1, 8(s0)
    lhu   t1, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L249
    xor  a3, t3, t2
L249:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L250
    xor  a3, t1, a3
L250:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L251
    xor  t1, a3, t1
L251:
    sw   a4, 24(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L252
    addi t0, a2, -38
L252:
    sh   t4, 0(s3)
    andi t5, s2, 8
    bnez t5, L253
    addi a4, a5, 1
L253:
    lw   t1, 4(s0)
    lb   t1, 5(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L254
    xor  t2, a3, t3
L254:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L255
    xor  a5, a1, a3
L255:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L256
    xor  a2, t2, a1
L256:
    sw   a1, 20(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L257
    addi t1, a4, 84
L257:
    andi t5, s2, 128
    beqz t5, L258
    addi t2, a5, -21
L258:
    andi t5, s2, 8
    bnez t5, L259
    addi a1, a4, -85
L259:
    sh   t3, 0(s3)
    andi t5, s2, 1024
    beqz t5, L260
    addi a4, a4, 1
L260:
    andi t5, s2, 1024
    beqz t5, L261
    addi a3, a2, 1
L261:
    lw   a5, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L262
    xor  t3, a4, a2
L262:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L263
    xor  a4, a4, a3
L263:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L264
    xor  a5, t4, a2
L264:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L265
    xor  t4, a3, t2
L265:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L266
    addi t4, t1, 53
L266:
    andi t5, s2, 4
    bnez t5, L267
    addi a3, t0, 39
L267:
    sb   t4, 0(s3)
    andi t5, s2, 256
    bnez t5, L268
    addi a1, t3, 1
L268:
    lhu   t3, 20(s0)
    lb   a5, 23(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L269
    xor  t0, t1, t1
L269:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L270
    xor  t4, a4, t2
L270:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L271
    xor  a2, a2, a1
L271:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L272
    addi a1, t2, 95
L272:
    andi t5, s2, 512
    bnez t5, L273
    addi a4, a3, -68
L273:
    sb   a2, 0(s3)
    andi t5, s2, 16
    bnez t5, L274
    addi t2, a4, 1
L274:
    lhu   t0, 8(s0)
    lb   a5, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L275
    xor  a4, t3, t3
L275:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L276
    xor  t3, a3, t1
L276:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L277
    addi a1, t2, -35
L277:
    sw   a4, 0(s3)
    andi t5, s2, 1
    beqz t5, L278
    addi a4, a5, 1
L278:
    andi t5, s2, 32
    beqz t5, L279
    addi t1, t2, 1
L279:
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L280
    xor  t2, a3, t2
L280:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L281
    xor  a5, t3, t4
L281:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L282
    xor  a3, t4, a4
L282:
    sw   t3, 8(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L283
    addi t4, a1, 67
L283:
    andi t5, s2, 2
    bnez t5, L284
    addi t2, t1, 94
L284:
    andi t5, s2, 2
    bnez t5, L285
    addi t2, a3, -100
L285:
    sw   t3, 0(s3)
    andi t5, s2, 1024
    beqz t5, L286
    addi t3, a3, 1
L286:
    lw   t4, 16(s0)
    lb   t2, 3(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L287
    xor  a1, t4, a2
L287:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L288
    xor  a2, t2, t2
L288:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L289
    xor  a3, a2, a1
L289:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L290
    xor  a1, a2, a3
L290:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L291
    addi a3, t2, 83
L291:
    andi t5, s2, 256
    beqz t5, L292
    addi t4, a1, 57
L292:
    andi t5, s2, 32
    bnez t5, L293
    addi t3, a1, 52
L293:
    sw   t4, 0(s3)
    andi t5, s2, 512
    bnez t5, L294
    addi a2, a4, 1
L294:
    andi t5, s2, 512
    beqz t5, L295
    addi t4, a5, 1
L295:
    lhu   a2, 4(s0)
    lb   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L296
    xor  a1, a4, t1
L296:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L297
    xor  a4, a4, t0
L297:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L298
    xor  a2, a4, t0
L298:
    sw   t3, 28(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L299
    addi t4, a4, -32
L299:
    andi t5, s2, 2
    beqz t5, L300
    addi a5, t4, 63
L300:
    sh   a4, 0(s3)
    andi t5, s2, 512
    beqz t5, L301
    addi t1, a4, 1
L301:
    lw   a4, 8(s0)
    lw   t3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L302
    xor  t3, a1, a4
L302:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L303
    xor  a1, t1, a1
L303:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L304
    addi t4, t3, 68
L304:
    sw   t2, 0(s3)
    andi t5, s2, 32
    beqz t5, L305
    addi t3, t1, 1
L305:
    andi t5, s2, 64
    beqz t5, L306
    addi t0, a2, 1
L306:
    lw   a3, 0(s0)
    lb   a4, 17(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L307
    xor  a3, a4, t1
L307:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L308
    xor  a5, t3, a5
L308:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L309
    xor  t1, t0, t4
L309:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L310
    xor  t2, t1, a2
L310:
    sw   a1, 16(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L311
    addi t0, a3, 51
L311:
    andi t5, s2, 512
    beqz t5, L312
    addi t2, a3, 93
L312:
    andi t5, s2, 256
    beqz t5, L313
    addi a3, a2, -3
L313:
    sb   a3, 0(s3)
    andi t5, s2, 2
    bnez t5, L314
    addi t3, a1, 1
L314:
    andi t5, s2, 4
    bnez t5, L315
    addi t3, a2, 1
L315:
    lb   t0, 5(s0)
    lw   t4, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L316
    xor  t1, t2, a3
L316:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L317
    xor  a2, t1, a4
L317:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L318
    xor  a1, a5, t0
L318:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L319
    xor  t2, a3, t3
L319:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L320
    addi a1, a4, -37
L320:
    andi t5, s2, 32
    bnez t5, L321
    addi t2, t1, -94
L321:
    sh   a5, 0(s3)
    andi t5, s2, 128
    bnez t5, L322
    addi a5, a5, 1
L322:
    andi t5, s2, 16
    beqz t5, L323
    addi t1, a3, 1
L323:
    lw   t2, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L324
    xor  a3, a5, a5
L324:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L325
    xor  a1, t1, a5
L325:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L326
    xor  t0, t4, t4
L326:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L327
    addi t4, a4, -73
L327:
    andi t5, s2, 256
    bnez t5, L328
    addi t2, t0, 52
L328:
    sw   a4, 0(s3)
    andi t5, s2, 8
    bnez t5, L329
    addi t2, a3, 1
L329:
    lhu   a4, 24(s0)
    lhu   a3, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L330
    xor  a1, a2, a3
L330:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L331
    xor  t3, a3, a4
L331:
    sw   t3, 4(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L332
    addi t3, a3, -98
L332:
    andi t5, s2, 64
    beqz t5, L333
    addi t1, t2, 79
L333:
    sw   a3, 0(s3)
    andi t5, s2, 8
    beqz t5, L334
    addi t1, t2, 1
L334:
    lhu   a3, 30(s0)
    lw   t4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L335
    xor  a3, a1, a4
L335:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L336
    xor  t2, t4, t0
L336:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L337
    addi a3, t2, -47
L337:
    andi t5, s2, 256
    beqz t5, L338
    addi t1, a3, 13
L338:
    andi t5, s2, 8
    beqz t5, L339
    addi a2, a5, 73
L339:
    sb   a2, 0(s3)
    andi t5, s2, 64
    beqz t5, L340
    addi t3, t4, 1
L340:
    andi t5, s2, 2
    beqz t5, L341
    addi a1, t1, 1
L341:
    lw   t3, 0(s0)
    lb   a3, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L342
    xor  t3, a4, a3
L342:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L343
    xor  t0, a3, a5
L343:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L344
    xor  a4, a3, a1
L344:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L345
    xor  t4, t2, t0
L345:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L346
    addi a5, t2, -11
L346:
    sb   t3, 0(s3)
    andi t5, s2, 8
    beqz t5, L347
    addi t2, a3, 1
L347:
    lhu   a3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L348
    xor  a1, a1, t1
L348:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L349
    xor  a1, t1, t1
L349:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L350
    xor  t4, a5, t0
L350:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L351
    xor  a5, a3, a4
L351:
    sw   t4, 4(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L352
    addi t2, t2, 69
L352:
    andi t5, s2, 128
    beqz t5, L353
    addi a4, t2, 60
L353:
    andi t5, s2, 64
    bnez t5, L354
    addi t3, t3, -48
L354:
    sw   t2, 0(s3)
    andi t5, s2, 4
    beqz t5, L355
    addi a2, t4, 1
L355:
    andi t5, s2, 32
    bnez t5, L356
    addi t2, t3, 1
L356:
    lhu   a2, 22(s0)
    lw   t4, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L357
    xor  t0, a4, a1
L357:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L358
    xor  t4, t4, a4
L358:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L359
    xor  t3, a5, t2
L359:
    sw   a2, 16(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L360
    addi t0, t2, 31
L360:
    andi t5, s2, 1024
    bnez t5, L361
    addi a4, a5, 18
L361:
    sw   t2, 0(s3)
    andi t5, s2, 512
    beqz t5, L362
    addi a1, t2, 1
L362:
    andi t5, s2, 128
    bnez t5, L363
    addi a1, a5, 1
L363:
    lw   t0, 28(s0)
    lb   t4, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L364
    xor  a3, t3, a2
L364:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L365
    xor  t1, t0, t3
L365:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L366
    addi t3, t3, 75
L366:
    andi t5, s2, 4
    beqz t5, L367
    addi t3, a1, -27
L367:
    sb   t1, 0(s3)
    andi t5, s2, 16
    bnez t5, L368
    addi a5, a4, 1
L368:
    andi t5, s2, 16
    beqz t5, L369
    addi a5, a4, 1
L369:
    lhu   t3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L370
    xor  t4, t2, t4
L370:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L371
    xor  t4, t3, t4
L371:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L372
    xor  a3, a2, a1
L372:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L373
    xor  a4, a1, t4
L373:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L374
    addi a3, t3, -93
L374:
    andi t5, s2, 16
    bnez t5, L375
    addi t1, a2, -45
L375:
    andi t5, s2, 8
    beqz t5, L376
    addi a4, t2, -69
L376:
    sb   a2, 0(s3)
    andi t5, s2, 1
    bnez t5, L377
    addi t0, a1, 1
L377:
    lw   t0, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L378
    xor  a5, a1, a5
L378:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L379
    xor  a3, a2, t4
L379:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L380
    xor  t1, t1, a5
L380:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L381
    addi a3, t4, -24
L381:
    andi t5, s2, 512
    bnez t5, L382
    addi a2, a3, 21
L382:
    andi t5, s2, 1
    bnez t5, L383
    addi t0, t3, -54
L383:
    sh   a5, 0(s3)
    andi t5, s2, 2
    beqz t5, L384
    addi t2, t4, 1
L384:
    lw   t1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L385
    xor  a4, a1, a5
L385:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L386
    xor  t0, a2, t2
L386:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L387
    xor  t3, a5, a2
L387:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L388
    addi a2, a2, 22
L388:
    sw   t0, 0(s3)
    andi t5, s2, 16
    bnez t5, L389
    addi t0, t4, 1
L389:
    andi t5, s2, 32
    bnez t5, L390
    addi a5, t3, 1
L390:
    lb   a1, 24(s0)
    lw   a5, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L391
    xor  a4, a2, a1
L391:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L392
    xor  a3, a4, t1
L392:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L393
    xor  a4, a3, a5
L393:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L394
    xor  t2, a1, a4
L394:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L395
    addi a2, t4, -30
L395:
    andi t5, s2, 4
    bnez t5, L396
    addi t1, a4, 48
L396:
    andi t5, s2, 4
    bnez t5, L397
    addi a2, t4, 59
L397:
    sb   a3, 0(s3)
    andi t5, s2, 1
    bnez t5, L398
    addi t3, t4, 1
L398:
    lhu   t2, 2(s0)
    lw   a3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L399
    xor  a1, a2, t1
L399:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L400
    xor  t1, a3, t0
L400:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L401
    xor  a4, a4, t2
L401:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L402
    xor  a3, t2, t4
L402:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L403
    addi t1, t2, 84
L403:
    andi t5, s2, 32
    beqz t5, L404
    addi t1, a3, -65
L404:
    sb   a1, 0(s3)
    andi t5, s2, 512
    beqz t5, L405
    addi a5, a1, 1
L405:
    lw   t3, 16(s0)
    lw   t0, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L406
    xor  t1, t4, t1
L406:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L407
    xor  t1, a3, t2
L407:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L408
    xor  a2, t2, a2
L408:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L409
    addi t0, t2, 31
L409:
    andi t5, s2, 1
    beqz t5, L410
    addi t1, t4, 54
L410:
    sw   t3, 0(s3)
    andi t5, s2, 16
    bnez t5, L411
    addi t4, a2, 1
L411:
    lhu   t0, 2(s0)
    lw   a4, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L412
    xor  t1, t0, t2
L412:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L413
    xor  t4, a3, t3
L413:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L414
    addi t0, t2, -27
L414:
    andi t5, s2, 32
    bnez t5, L415
    addi a5, t3, -40
L415:
    andi t5, s2, 8
    beqz t5, L416
    addi t4, a1, -13
L416:
    sb   t3, 0(s3)
    andi t5, s2, 2
    beqz t5, L417
    addi a5, a4, 1
L417:
    lb   a5, 18(s0)
    lw   a3, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L418
    xor  a2, a5, a2
L418:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L419
    xor  t4, t4, a2
L419:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L420
    xor  a5, a3, a2
L420:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L421
    xor  a4, a5, t2
L421:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L422
    addi t2, t2, -29
L422:
    sh   a5, 0(s3)
    andi t5, s2, 64
    beqz t5, L423
    addi a5, a3, 1
L423:
    lb   a4, 9(s0)
    lb   t1, 25(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L424
    xor  t2, t3, a1
L424:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L425
    xor  t2, t4, a5
L425:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L426
    xor  t4, t0, a3
L426:
    sw   t3, 24(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L427
    addi a1, t4, -69
L427:
    sh   t2, 0(s3)
    andi t5, s2, 64
    bnez t5, L428
    addi t2, a3, 1
L428:
    lhu   a3, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L429
    xor  t4, t4, t4
L429:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L430
    xor  a3, a2, t0
L430:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L431
    addi t2, a5, 95
L431:
    andi t5, s2, 1
    bnez t5, L432
    addi t4, t3, 28
L432:
    andi t5, s2, 32
    beqz t5, L433
    addi t0, t0, -9
L433:
    sb   a2, 0(s3)
    andi t5, s2, 32
    beqz t5, L434
    addi a1, t3, 1
L434:
    lw   a3, 8(s0)
    lw   a3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L435
    xor  a2, a1, a3
L435:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L436
    xor  a3, t4, t1
L436:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L437
    addi a1, t1, -28
L437:
    andi t5, s2, 1
    beqz t5, L438
    addi a4, a3, -69
L438:
    sb   a5, 0(s3)
    andi t5, s2, 1024
    bnez t5, L439
    addi t2, t3, 1
L439:
    lw   t4, 4(s0)
    lb   a3, 27(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L440
    xor  a4, t0, t4
L440:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L441
    xor  a5, a4, a5
L441:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L442
    xor  a1, a4, t1
L442:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L443
    xor  t2, a3, t2
L443:
    sw   t1, 12(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L444
    addi a5, a2, 59
L444:
    andi t5, s2, 64
    bnez t5, L445
    addi t0, a5, 23
L445:
    sw   a3, 0(s3)
    andi t5, s2, 1
    beqz t5, L446
    addi a1, a5, 1
L446:
    lw   a5, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L447
    xor  t2, a2, a4
L447:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L448
    xor  a5, a5, a3
L448:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L449
    xor  a1, t0, a3
L449:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L450
    xor  t2, t2, a2
L450:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L451
    addi a2, a1, -24
L451:
    sh   t0, 0(s3)
    andi t5, s2, 16
    bnez t5, L452
    addi a3, a5, 1
L452:
    lw   t2, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L453
    xor  t1, a3, t1
L453:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L454
    xor  a3, t1, a5
L454:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L455
    addi t1, a3, -71
L455:
    sh   t4, 0(s3)
    andi t5, s2, 512
    bnez t5, L456
    addi t2, t1, 1
L456:
    andi t5, s2, 512
    bnez t5, L457
    addi a1, t3, 1
L457:
    lw   t0, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L458
    xor  a3, t4, a3
L458:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L459
    xor  a4, t3, t3
L459:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L460
    xor  t4, t1, a3
L460:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L461
    xor  a2, t0, t1
L461:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L462
    addi t2, a4, 68
L462:
    andi t5, s2, 1
    beqz t5, L463
    addi t3, t1, 7
L463:
    sw   a3, 0(s3)
    andi t5, s2, 2
    beqz t5, L464
    addi t2, a5, 1
L464:
    lw   t1, 28(s0)
    lw   a1, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L465
    xor  t0, a2, t3
L465:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L466
    xor  t1, a3, a4
L466:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L467
    xor  a1, t3, a1
L467:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L468
    xor  a4, a5, a3
L468:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L469
    addi a5, t1, -55
L469:
    andi t5, s2, 8
    beqz t5, L470
    addi a2, a4, -70
L470:
    andi t5, s2, 1024
    bnez t5, L471
    addi t0, t1, 95
L471:
    sh   a1, 0(s3)
    andi t5, s2, 32
    bnez t5, L472
    addi t4, t2, 1
L472:
    andi t5, s2, 1024
    beqz t5, L473
    addi a4, a4, 1
L473:
    lhu   t4, 4(s0)
    lhu   t4, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L474
    xor  t2, t3, a1
L474:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L475
    xor  t0, t0, a5
L475:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L476
    addi t3, a5, -14
L476:
    andi t5, s2, 1
    bnez t5, L477
    addi a4, t2, 64
L477:
    andi t5, s2, 512
    beqz t5, L478
    addi a1, t3, 36
L478:
    sw   t2, 0(s3)
    andi t5, s2, 1024
    beqz t5, L479
    addi a3, t2, 1
L479:
    lw   a4, 24(s0)
    lw   a3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L480
    xor  a4, a3, t3
L480:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L481
    xor  t3, a5, a4
L481:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L482
    xor  a2, t0, t0
L482:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L483
    addi a4, a1, 42
L483:
    andi t5, s2, 512
    bnez t5, L484
    addi a4, a4, 29
L484:
    andi t5, s2, 256
    bnez t5, L485
    addi t4, t2, -67
L485:
    sw   a3, 0(s3)
    andi t5, s2, 16
    bnez t5, L486
    addi t3, a2, 1
L486:
    lw   t2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L487
    xor  t2, a4, t4
L487:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L488
    xor  t4, a5, t3
L488:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L489
    addi t3, t4, 89
L489:
    andi t5, s2, 4
    bnez t5, L490
    addi t3, a5, -25
L490:
    sb   t3, 0(s3)
    andi t5, s2, 8
    beqz t5, L491
    addi t2, a3, 1
L491:
    andi t5, s2, 4
    bnez t5, L492
    addi t1, a4, 1
L492:
    lb   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L493
    xor  a4, t2, a1
L493:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L494
    xor  a1, t4, a4
L494:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L495
    xor  a2, t0, t0
L495:
    sw   a5, 12(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L496
    addi a5, t1, 43
L496:
    andi t5, s2, 1024
    beqz t5, L497
    addi t4, a2, -97
L497:
    andi t5, s2, 256
    bnez t5, L498
    addi t4, t1, -58
L498:
    sh   t4, 0(s3)
    andi t5, s2, 128
    beqz t5, L499
    addi t4, t3, 1
L499:
    andi t5, s2, 512
    bnez t5, L500
    addi a4, a5, 1
L500:
    lb   t0, 31(s0)
    lb   a5, 1(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L501
    xor  a5, a2, a5
L501:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L502
    xor  t4, t2, a3
L502:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L503
    xor  a3, t3, t2
L503:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L504
    xor  t3, a1, t2
L504:
    sw   a3, 16(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L505
    addi a4, t1, 57
L505:
    sh   a5, 0(s3)
    andi t5, s2, 1024
    beqz t5, L506
    addi a3, t4, 1
L506:
    andi t5, s2, 64
    bnez t5, L507
    addi a5, t4, 1
L507:
    lb   t4, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L508
    xor  t0, a4, a3
L508:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L509
    xor  a5, a1, t4
L509:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L510
    xor  a4, t2, t0
L510:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L511
    xor  a1, a5, t3
L511:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L512
    addi a3, a5, -27
L512:
    andi t5, s2, 1024
    beqz t5, L513
    addi a5, t0, -85
L513:
    sb   t0, 0(s3)
    andi t5, s2, 256
    beqz t5, L514
    addi a2, a1, 1
L514:
    lw   t4, 12(s0)
    lhu   t3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L515
    xor  t3, a3, a4
L515:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L516
    xor  t3, t3, a4
L516:
    sw   a4, 28(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L517
    addi a2, t0, -62
L517:
    andi t5, s2, 16
    bnez t5, L518
    addi t2, t1, 35
L518:
    andi t5, s2, 8
    beqz t5, L519
    addi a3, a4, -87
L519:
    sw   a2, 0(s3)
    andi t5, s2, 8
    beqz t5, L520
    addi t3, a1, 1
L520:
    andi t5, s2, 2
    bnez t5, L521
    addi a5, t2, 1
L521:
    lw   a5, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L522
    xor  t0, t4, a5
L522:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L523
    xor  t4, t1, a1
L523:
    sw   a5, 4(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L524
    addi t0, t1, 79
L524:
    andi t5, s2, 32
    beqz t5, L525
    addi t2, a3, 95
L525:
    andi t5, s2, 128
    bnez t5, L526
    addi t1, a1, -4
L526:
    sw   a1, 0(s3)
    andi t5, s2, 16
    bnez t5, L527
    addi a2, t1, 1
L527:
    andi t5, s2, 128
    beqz t5, L528
    addi a5, t2, 1
L528:
    lw   a5, 12(s0)
    lw   a5, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L529
    xor  t3, t1, t1
L529:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L530
    xor  t0, a5, a5
L530:
    sw   t1, 4(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L531
    addi a2, t3, -78
L531:
    sb   t3, 0(s3)
    andi t5, s2, 16
    beqz t5, L532
    addi a2, t4, 1
L532:
    lw   t3, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L533
    xor  a2, a3, a3
L533:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L534
    xor  a1, a2, t2
L534:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L535
    xor  t4, a5, t3
L535:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L536
    xor  a4, t0, a3
L536:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L537
    addi a1, t3, -84
L537:
    andi t5, s2, 16
    beqz t5, L538
    addi t4, a1, 83
L538:
    sb   t3, 0(s3)
    andi t5, s2, 2
    beqz t5, L539
    addi t0, a5, 1
L539:
    lw   t3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L540
    xor  a4, t1, t4
L540:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L541
    xor  t1, a2, t1
L541:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L542
    addi t3, t0, -84
L542:
    andi t5, s2, 1
    beqz t5, L543
    addi t3, t0, -52
L543:
    andi t5, s2, 8
    bnez t5, L544
    addi a2, t2, -11
L544:
    sw   a5, 0(s3)
    andi t5, s2, 256
    beqz t5, L545
    addi t2, t0, 1
L545:
    lw   a5, 28(s0)
    lb   a3, 15(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L546
    xor  a3, a1, a4
L546:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L547
    xor  t2, t3, a2
L547:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L548
    xor  a4, t0, t4
L548:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L549
    xor  t1, t4, a3
L549:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L550
    addi a1, t3, 25
L550:
    sw   t3, 0(s3)
    andi t5, s2, 32
    beqz t5, L551
    addi t2, t4, 1
L551:
    andi t5, s2, 8
    beqz t5, L552
    addi a1, a5, 1
L552:
    lw   t2, 0(s0)
    lw   a1, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L553
    xor  a1, t1, t0
L553:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L554
    xor  t4, t1, t2
L554:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L555
    xor  t1, a1, t3
L555:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L556
    addi t0, a3, -8
L556:
    sh   a3, 0(s3)
    andi t5, s2, 1024
    bnez t5, L557
    addi a2, t3, 1
L557:
    lw   t2, 0(s0)
    lw   a4, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L558
    xor  t4, a3, a5
L558:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L559
    xor  a2, a2, a4
L559:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L560
    xor  a2, a2, a1
L560:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L561
    xor  t2, t2, t2
L561:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L562
    addi t3, t0, -16
L562:
    andi t5, s2, 1024
    beqz t5, L563
    addi t2, a5, -5
L563:
    andi t5, s2, 1024
    beqz t5, L564
    addi a2, a3, 87
L564:
    sb   t1, 0(s3)
    andi t5, s2, 256
    bnez t5, L565
    addi t3, a2, 1
L565:
    lhu   a2, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L566
    xor  t3, t1, t0
L566:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L567
    xor  a3, t2, a4
L567:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L568
    xor  a3, a1, a3
L568:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L569
    addi t2, t1, -47
L569:
    sw   t1, 0(s3)
    andi t5, s2, 16
    beqz t5, L570
    addi a3, t2, 1
L570:
    andi t5, s2, 1024
    beqz t5, L571
    addi a3, t4, 1
L571:
    lw   a1, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L572
    xor  a5, t0, a3
L572:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L573
    xor  a2, a5, a3
L573:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L574
    xor  t1, t4, a1
L574:
    sw   t1, 28(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L575
    addi t4, t4, 9
L575:
    sb   t4, 0(s3)
    andi t5, s2, 16
    bnez t5, L576
    addi t3, t4, 1
L576:
    andi t5, s2, 16
    bnez t5, L577
    addi t3, a2, 1
L577:
    lhu   a2, 0(s0)
    lb   a4, 7(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L578
    xor  t3, a4, t4
L578:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L579
    xor  t3, a2, a1
L579:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L580
    addi a1, a1, -94
L580:
    andi t5, s2, 64
    beqz t5, L581
    addi t3, t0, 57
L581:
    andi t5, s2, 1024
    bnez t5, L582
    addi t1, a4, -51
L582:
    sh   a4, 0(s3)
    andi t5, s2, 32
    bnez t5, L583
    addi a5, a2, 1
L583:
    andi t5, s2, 1024
    beqz t5, L584
    addi a2, a5, 1
L584:
    lw   a4, 24(s0)
    lw   t2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L585
    xor  a2, a4, a3
L585:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L586
    xor  t0, a3, a1
L586:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L587
    xor  a5, a5, t2
L587:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L588
    xor  t2, a2, t4
L588:
    sw   a2, 28(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L589
    addi a4, a5, 6
L589:
    andi t5, s2, 2
    bnez t5, L590
    addi t2, t4, -15
L590:
    andi t5, s2, 1
    beqz t5, L591
    addi a2, t1, -43
L591:
    sb   a2, 0(s3)
    andi t5, s2, 1
    beqz t5, L592
    addi a1, t1, 1
L592:
    lw   t2, 0(s0)
    lb   a4, 13(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L593
    xor  a3, t3, t3
L593:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L594
    xor  a1, t3, t2
L594:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L595
    xor  t0, t2, t0
L595:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L596
    addi a2, t2, -93
L596:
    andi t5, s2, 32
    bnez t5, L597
    addi a4, t2, -18
L597:
    andi t5, s2, 256
    beqz t5, L598
    addi t1, t3, 28
L598:
    sh   t2, 0(s3)
    andi t5, s2, 256
    bnez t5, L599
    addi t2, t4, 1
L599:
    andi t5, s2, 32
    bnez t5, L600
    addi a2, a3, 1
L600:
    lw   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L601
    xor  a4, a2, t0
L601:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L602
    xor  t0, t1, a3
L602:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L603
    xor  a5, t2, t2
L603:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L604
    xor  a3, a5, a5
L604:
    sw   a5, 12(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L605
    addi a5, a2, 98
L605:
    andi t5, s2, 256
    bnez t5, L606
    addi t0, a5, -63
L606:
    andi t5, s2, 8
    bnez t5, L607
    addi t4, t4, 43
L607:
    sh   t0, 0(s3)
    andi t5, s2, 128
    beqz t5, L608
    addi a4, a4, 1
L608:
    lhu   t0, 20(s0)
    lw   a4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L609
    xor  a5, a4, a5
L609:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L610
    xor  a5, a2, t3
L610:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L611
    xor  t4, t2, t1
L611:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L612
    addi t4, a4, -59
L612:
    sh   t0, 0(s3)
    andi t5, s2, 8
    beqz t5, L613
    addi t2, a2, 1
L613:
    lw   t4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L614
    xor  a4, t4, a1
L614:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L615
    xor  t1, t4, t4
L615:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L616
    xor  a4, a2, t0
L616:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L617
    xor  t0, t3, a1
L617:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L618
    addi t1, t0, 65
L618:
    andi t5, s2, 512
    beqz t5, L619
    addi t2, t1, -10
L619:
    sw   t4, 0(s3)
    andi t5, s2, 512
    bnez t5, L620
    addi a1, a5, 1
L620:
    lw   t4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L621
    xor  t2, a5, a3
L621:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L622
    xor  a3, t1, a5
L622:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L623
    addi t4, a4, -73
L623:
    andi t5, s2, 512
    beqz t5, L624
    addi a1, t4, 26
L624:
    sw   t1, 0(s3)
    andi t5, s2, 128
    bnez t5, L625
    addi t0, a1, 1
L625:
    lb   t3, 18(s0)
    lb   a2, 7(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L626
    xor  a3, t2, a3
L626:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L627
    xor  a5, t2, t3
L627:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L628
    xor  t0, t4, t2
L628:
    sw   a4, 12(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L629
    addi a3, a3, 75
L629:
    andi t5, s2, 2
    bnez t5, L630
    addi t4, t0, 94
L630:
    andi t5, s2, 64
    bnez t5, L631
    addi a5, t2, -86
L631:
    sh   t1, 0(s3)
    andi t5, s2, 1
    bnez t5, L632
    addi t1, t2, 1
L632:
    lhu   a1, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L633
    xor  a3, a1, a1
L633:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L634
    xor  t2, t2, t0
L634:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L635
    xor  t3, a1, a4
L635:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L636
    xor  a4, a4, a1
L636:
    sw   a2, 4(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L637
    addi a2, t0, 3
L637:
    sw   t1, 0(s3)
    andi t5, s2, 1024
    beqz t5, L638
    addi t1, a4, 1
L638:
    lw   a1, 4(s0)
    lb   a3, 27(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L639
    xor  t4, t0, a3
L639:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L640
    xor  a2, t4, t2
L640:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L641
    xor  t2, t3, a5
L641:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L642
    addi t3, t4, 29
L642:
    sh   a5, 0(s3)
    andi t5, s2, 16
    beqz t5, L643
    addi t0, a1, 1
L643:
    andi t5, s2, 2
    beqz t5, L644
    addi a4, a2, 1
L644:
    lb   a3, 22(s0)
    lb   a1, 5(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L645
    xor  a1, t2, t0
L645:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L646
    xor  a1, t1, t2
L646:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L647
    xor  t4, t2, a3
L647:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L648
    xor  a2, t3, a3
L648:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L649
    addi t3, t4, 42
L649:
    andi t5, s2, 512
    beqz t5, L650
    addi a5, a3, 85
L650:
    sb   t1, 0(s3)
    andi t5, s2, 2
    beqz t5, L651
    addi a4, t1, 1
L651:
    lw   t1, 20(s0)
    lw   a3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L652
    xor  t4, a1, t4
L652:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L653
    xor  t2, t0, t1
L653:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L654
    xor  t3, t4, t3
L654:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L655
    addi t1, t1, -51
L655:
    andi t5, s2, 32
    bnez t5, L656
    addi a3, t0, 82
L656:
    sh   t2, 0(s3)
    andi t5, s2, 2
    beqz t5, L657
    addi t4, t1, 1
L657:
    andi t5, s2, 32
    beqz t5, L658
    addi a1, t3, 1
L658:
    lw   t3, 4(s0)
    lhu   t4, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L659
    xor  a5, t0, a1
L659:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L660
    xor  t0, t2, t3
L660:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L661
    addi a1, t1, -5
L661:
    andi t5, s2, 512
    beqz t5, L662
    addi t3, t1, -34
L662:
    sb   a3, 0(s3)
    andi t5, s2, 1024
    bnez t5, L663
    addi t3, a5, 1
L663:
    andi t5, s2, 4
    bnez t5, L664
    addi t4, t3, 1
L664:
    lhu   a2, 30(s0)
    lw   t2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L665
    xor  t1, a1, t3
L665:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L666
    xor  a5, t1, t2
L666:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L667
    addi t1, t3, 12
L667:
    andi t5, s2, 32
    bnez t5, L668
    addi t2, t1, 61
L668:
    andi t5, s2, 1
    beqz t5, L669
    addi a2, a1, -51
L669:
    sh   a5, 0(s3)
    andi t5, s2, 1024
    beqz t5, L670
    addi a4, a5, 1
L670:
    lw   t4, 12(s0)
    lhu   t4, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L671
    xor  t0, t2, t3
L671:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L672
    xor  t3, t3, t3
L672:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L673
    xor  a5, t3, t2
L673:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L674
    addi a2, a2, -10
L674:
    andi t5, s2, 1024
    beqz t5, L675
    addi a4, a1, 74
L675:
    sh   t1, 0(s3)
    andi t5, s2, 16
    beqz t5, L676
    addi t1, a1, 1
L676:
    lw   t3, 16(s0)
    lhu   a4, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L677
    xor  t3, a3, t0
L677:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L678
    xor  t1, a5, t2
L678:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L679
    addi t1, t0, -69
L679:
    andi t5, s2, 1024
    bnez t5, L680
    addi a3, t2, 98
L680:
    andi t5, s2, 8
    bnez t5, L681
    addi t1, a4, 38
L681:
    sh   t0, 0(s3)
    andi t5, s2, 1024
    beqz t5, L682
    addi t4, t1, 1
L682:
    andi t5, s2, 4
    beqz t5, L683
    addi a1, a2, 1
L683:
    lhu   t1, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L684
    xor  a5, t1, a4
L684:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L685
    xor  a5, a2, a1
L685:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L686
    xor  t0, t3, t2
L686:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L687
    xor  a3, t4, a3
L687:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L688
    addi a2, a5, 21
L688:
    sh   a3, 0(s3)
    andi t5, s2, 512
    bnez t5, L689
    addi a5, a4, 1
L689:
    lb   a4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L690
    xor  a2, t4, a3
L690:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L691
    xor  a5, t2, a1
L691:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L692
    xor  a5, a2, a3
L692:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L693
    xor  a4, a2, t4
L693:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L694
    addi a3, t4, -65
L694:
    andi t5, s2, 4
    bnez t5, L695
    addi a1, a1, 74
L695:
    andi t5, s2, 64
    bnez t5, L696
    addi a5, a5, -84
L696:
    sw   t3, 0(s3)
    andi t5, s2, 1
    beqz t5, L697
    addi t2, t3, 1
L697:
    andi t5, s2, 256
    beqz t5, L698
    addi t3, t1, 1
L698:
    lw   a4, 0(s0)
    lw   t4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L699
    xor  a3, a4, t1
L699:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L700
    xor  t1, a2, t0
L700:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L701
    xor  t1, t1, t1
L701:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L702
    addi t0, a4, -31
L702:
    sb   t0, 0(s3)
    andi t5, s2, 4
    bnez t5, L703
    addi a5, a5, 1
L703:
    andi t5, s2, 64
    beqz t5, L704
    addi t0, t4, 1
L704:
    lw   a2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L705
    xor  t4, t0, a5
L705:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L706
    xor  t4, a2, t2
L706:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L707
    xor  t0, a2, a1
L707:
    sw   t0, 0(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L708
    addi t0, t1, -37
L708:
    andi t5, s2, 1
    beqz t5, L709
    addi a2, a3, -89
L709:
    andi t5, s2, 16
    bnez t5, L710
    addi a1, a3, -65
L710:
    sh   a3, 0(s3)
    andi t5, s2, 64
    beqz t5, L711
    addi t4, a4, 1
L711:
    andi t5, s2, 32
    bnez t5, L712
    addi t4, t2, 1
L712:
    lw   t1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L713
    xor  a3, t1, t2
L713:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L714
    xor  t0, t3, t4
L714:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L715
    xor  t2, t1, t3
L715:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L716
    xor  a2, t2, a2
L716:
    sw   a3, 0(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L717
    addi a1, a4, 92
L717:
    sw   t3, 0(s3)
    andi t5, s2, 1
    beqz t5, L718
    addi t0, a5, 1
L718:
    andi t5, s2, 2
    bnez t5, L719
    addi a5, a5, 1
L719:
    lw   t3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L720
    xor  a4, t0, a2
L720:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L721
    xor  t1, t4, a5
L721:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L722
    addi a1, t2, 23
L722:
    andi t5, s2, 4
    bnez t5, L723
    addi t4, t0, -73
L723:
    sb   t3, 0(s3)
    andi t5, s2, 256
    beqz t5, L724
    addi a1, a4, 1
L724:
    andi t5, s2, 2
    bnez t5, L725
    addi a2, t1, 1
L725:
    lb   a2, 27(s0)
    lhu   a2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L726
    xor  a2, a1, t3
L726:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L727
    xor  a4, a2, t1
L727:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L728
    addi t1, a5, 99
L728:
    sb   a2, 0(s3)
    andi t5, s2, 2
    bnez t5, L729
    addi t0, t3, 1
L729:
    andi t5, s2, 16
    beqz t5, L730
    addi a3, a3, 1
L730:
    lhu   a2, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L731
    xor  a1, a5, a4
L731:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L732
    xor  t4, a2, t1
L732:
    sw   a3, 0(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L733
    addi a1, t1, 93
L733:
    andi t5, s2, 128
    bnez t5, L734
    addi a4, a5, 74
L734:
    sb   a1, 0(s3)
    andi t5, s2, 4
    beqz t5, L735
    addi a1, t1, 1
L735:
    lw   a3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L736
    xor  t1, a5, a4
L736:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L737
    xor  a5, t4, t3
L737:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L738
    xor  a1, a1, a1
L738:
    sw   a4, 4(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L739
    addi t0, a4, -4
L739:
    andi t5, s2, 2
    beqz t5, L740
    addi t1, a2, -19
L740:
    andi t5, s2, 32
    bnez t5, L741
    addi t4, t3, -29
L741:
    sh   t3, 0(s3)
    andi t5, s2, 2
    bnez t5, L742
    addi a3, a5, 1
L742:
    lhu   a5, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L743
    xor  a1, a4, a1
L743:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L744
    xor  t3, t2, t3
L744:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L745
    addi a2, a2, 41
L745:
    andi t5, s2, 32
    beqz t5, L746
    addi t0, t4, -42
L746:
    sw   t1, 0(s3)
    andi t5, s2, 64
    beqz t5, L747
    addi a4, a3, 1
L747:
    lhu   a5, 14(s0)
    lhu   a3, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L748
    xor  a2, t3, a4
L748:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L749
    xor  a5, t2, t2
L749:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L750
    addi t3, t3, 15
L750:
    andi t5, s2, 16
    beqz t5, L751
    addi a5, a5, -83
L751:
    sw   a4, 0(s3)
    andi t5, s2, 128
    bnez t5, L752
    addi a3, t4, 1
L752:
    andi t5, s2, 512
    beqz t5, L753
    addi a5, t3, 1
L753:
    lb   a2, 0(s0)
    lw   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L754
    xor  t0, a2, a3
L754:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L755
    xor  a1, a2, t0
L755:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L756
    addi a4, a2, 52
L756:
    andi t5, s2, 8
    beqz t5, L757
    addi t3, t4, 76
L757:
    sb   t1, 0(s3)
    andi t5, s2, 2
    beqz t5, L758
    addi a4, a2, 1
L758:
    andi t5, s2, 128
    beqz t5, L759
    addi t2, a1, 1
L759:
    lhu   a1, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L760
    xor  a3, a5, a4
L760:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L761
    xor  t1, t1, a2
L761:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L762
    xor  t0, t4, a1
L762:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L763
    addi a2, a1, -3
L763:
    sw   t3, 0(s3)
    andi t5, s2, 128
    beqz t5, L764
    addi t2, a1, 1
L764:
    andi t5, s2, 8
    beqz t5, L765
    addi t4, t2, 1
L765:
    lw   a1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L766
    xor  a2, a4, t1
L766:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L767
    xor  a1, t0, a2
L767:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L768
    addi t0, a2, 65
L768:
    sh   a3, 0(s3)
    andi t5, s2, 64
    bnez t5, L769
    addi a5, a5, 1
L769:
    andi t5, s2, 1024
    beqz t5, L770
    addi t2, t1, 1
L770:
    lb   a4, 7(s0)
    lhu   t1, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L771
    xor  a5, t3, t4
L771:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L772
    xor  t4, a3, t3
L772:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L773
    xor  a5, t2, a4
L773:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L774
    xor  t2, a4, a3
L774:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L775
    addi t2, a2, -16
L775:
    andi t5, s2, 1024
    bnez t5, L776
    addi t1, t0, -73
L776:
    andi t5, s2, 256
    beqz t5, L777
    addi t1, t0, 44
L777:
    sw   t4, 0(s3)
    andi t5, s2, 32
    bnez t5, L778
    addi t0, a3, 1
L778:
    andi t5, s2, 16
    bnez t5, L779
    addi a3, t1, 1
L779:
    lw   t3, 20(s0)
    lhu   t0, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L780
    xor  t2, t4, t1
L780:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L781
    xor  a1, t3, t4
L781:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L782
    xor  a5, t1, t2
L782:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L783
    xor  a3, t1, t1
L783:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L784
    addi a1, a2, -53
L784:
    andi t5, s2, 32
    bnez t5, L785
    addi t2, t4, -55
L785:
    sb   t4, 0(s3)
    andi t5, s2, 16
    bnez t5, L786
    addi a2, a4, 1
L786:
    lb   a2, 15(s0)
    lhu   a4, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L787
    xor  a2, a1, t3
L787:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L788
    xor  t4, a1, a1
L788:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L789
    xor  t0, t4, t3
L789:
    sw   a2, 4(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L790
    addi t4, a3, 68
L790:
    sh   a2, 0(s3)
    andi t5, s2, 256
    beqz t5, L791
    addi t2, t2, 1
L791:
    andi t5, s2, 8
    beqz t5, L792
    addi a5, t2, 1
L792:
    lw   a4, 12(s0)
    lhu   t3, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L793
    xor  t3, a1, a4
L793:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L794
    xor  t2, a2, t2
L794:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L795
    xor  t3, t3, t1
L795:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L796
    addi a5, t0, -99
L796:
    andi t5, s2, 16
    beqz t5, L797
    addi a2, t3, 18
L797:
    andi t5, s2, 1024
    bnez t5, L798
    addi t2, t4, 14
L798:
    sw   a5, 0(s3)
    andi t5, s2, 2
    bnez t5, L799
    addi t0, t1, 1
L799:
    lw   t0, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L800
    xor  a3, t0, t4
L800:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L801
    xor  t1, a5, t3
L801:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L802
    xor  t4, t2, t2
L802:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L803
    xor  a4, a2, t3
L803:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L804
    addi a1, a5, -21
L804:
    sh   a3, 0(s3)
    andi t5, s2, 16
    beqz t5, L805
    addi t4, t3, 1
L805:
    andi t5, s2, 32
    bnez t5, L806
    addi a1, a3, 1
L806:
    lw   a1, 12(s0)
    lw   t3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L807
    xor  t2, t0, a2
L807:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L808
    xor  a2, a4, t0
L808:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L809
    xor  a5, a4, a4
L809:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L810
    addi t2, a4, 56
L810:
    andi t5, s2, 64
    beqz t5, L811
    addi t3, t1, -20
L811:
    sw   t2, 0(s3)
    andi t5, s2, 32
    bnez t5, L812
    addi t3, a4, 1
L812:
    lhu   a4, 14(s0)
    lw   a5, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L813
    xor  t1, a5, t4
L813:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L814
    xor  a5, a3, t4
L814:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L815
    xor  a1, t2, a1
L815:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L816
    xor  a1, a1, t3
L816:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L817
    addi a3, t3, -33
L817:
    sb   t1, 0(s3)
    andi t5, s2, 128
    bnez t5, L818
    addi a2, t3, 1
L818:
    andi t5, s2, 128
    bnez t5, L819
    addi a5, t1, 1
L819:
    lhu   t1, 20(s0)
    lb   a3, 23(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L820
    xor  a2, a3, a5
L820:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L821
    xor  a3, t0, a2
L821:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L822
    addi t4, a4, -94
L822:
    sw   t2, 0(s3)
    andi t5, s2, 16
    bnez t5, L823
    addi a1, a5, 1
L823:
    lhu   a5, 12(s0)
    lb   a1, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L824
    xor  t0, a4, a2
L824:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L825
    xor  a5, t3, t2
L825:
    sw   t0, 8(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L826
    addi a4, a1, -14
L826:
    sh   t2, 0(s3)
    andi t5, s2, 2
    beqz t5, L827
    addi t3, t0, 1
L827:
    andi t5, s2, 8
    bnez t5, L828
    addi t1, t4, 1
L828:
    lb   t4, 10(s0)
    lw   a2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L829
    xor  t2, a3, t1
L829:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L830
    xor  a1, t2, t0
L830:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L831
    xor  a3, t1, a4
L831:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L832
    xor  a2, t0, a5
L832:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L833
    addi a1, a5, -28
L833:
    andi t5, s2, 16
    bnez t5, L834
    addi a5, t1, -26
L834:
    andi t5, s2, 2
    beqz t5, L835
    addi a4, t1, -67
L835:
    sh   a4, 0(s3)
    andi t5, s2, 512
    bnez t5, L836
    addi a4, a4, 1
L836:
    andi t5, s2, 1
    bnez t5, L837
    addi a2, a2, 1
L837:
    lhu   a2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L838
    xor  t1, a4, t1
L838:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L839
    xor  a2, t4, t0
L839:
    sw   t2, 16(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L840
    addi a5, a1, 26
L840:
    sb   t2, 0(s3)
    andi t5, s2, 8
    beqz t5, L841
    addi a4, a4, 1
L841:
    lb   t4, 18(s0)
    lw   t1, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L842
    xor  a5, a4, t4
L842:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L843
    xor  t2, a3, t3
L843:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L844
    xor  t2, t4, a2
L844:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L845
    addi a2, t0, 16
L845:
    sh   t1, 0(s3)
    andi t5, s2, 2
    bnez t5, L846
    addi a5, a2, 1
L846:
    lw   t2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L847
    xor  t4, t2, t2
L847:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L848
    xor  a1, a2, a3
L848:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L849
    xor  t0, t0, t2
L849:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L850
    xor  t0, t3, a4
L850:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L851
    addi a1, t1, -16
L851:
    sh   a3, 0(s3)
    andi t5, s2, 8
    bnez t5, L852
    addi t3, t2, 1
L852:
    andi t5, s2, 4
    beqz t5, L853
    addi a3, a3, 1
L853:
    lb   t0, 20(s0)
    lw   t0, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L854
    xor  t2, t0, t2
L854:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L855
    xor  a3, a2, a5
L855:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L856
    addi t2, t2, -87
L856:
    andi t5, s2, 1024
    beqz t5, L857
    addi a4, t3, 42
L857:
    sw   t1, 0(s3)
    andi t5, s2, 512
    beqz t5, L858
    addi t4, t4, 1
L858:
    lw   t1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L859
    xor  t0, t4, t3
L859:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L860
    xor  t1, a4, t0
L860:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L861
    addi t0, a1, -100
L861:
    andi t5, s2, 128
    beqz t5, L862
    addi a3, a2, -43
L862:
    andi t5, s2, 256
    bnez t5, L863
    addi a5, t3, 55
L863:
    sb   a5, 0(s3)
    andi t5, s2, 4
    bnez t5, L864
    addi t4, a5, 1
L864:
    lhu   a5, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L865
    xor  a5, t0, a4
L865:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L866
    xor  t2, a4, a1
L866:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L867
    xor  a3, t4, t2
L867:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L868
    xor  a2, a1, a1
L868:
    sw   t1, 28(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L869
    addi a2, t2, 52
L869:
    sw   t4, 0(s3)
    andi t5, s2, 128
    bnez t5, L870
    addi a1, t4, 1
L870:
    lb   a2, 6(s0)
    lw   a3, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L871
    xor  t4, t1, t3
L871:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L872
    xor  t1, a2, t0
L872:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L873
    addi t0, t1, 35
L873:
    sh   a4, 0(s3)
    andi t5, s2, 256
    bnez t5, L874
    addi a5, t4, 1
L874:
    andi t5, s2, 4
    beqz t5, L875
    addi a3, a4, 1
L875:
    lw   t0, 0(s0)
    lw   a4, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L876
    xor  t2, t2, a4
L876:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L877
    xor  t2, a5, t1
L877:
    sw   a2, 28(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L878
    addi t2, t0, -26
L878:
    andi t5, s2, 16
    bnez t5, L879
    addi t0, t3, -64
L879:
    sh   t0, 0(s3)
    andi t5, s2, 32
    bnez t5, L880
    addi a4, t1, 1
L880:
    andi t5, s2, 2
    beqz t5, L881
    addi a1, t3, 1
L881:
    lw   t1, 12(s0)
    lw   t0, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L882
    xor  t4, a3, t4
L882:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L883
    xor  a1, t3, a1
L883:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L884
    xor  a3, t2, t0
L884:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L885
    xor  t0, a5, t2
L885:
    sw   t1, 0(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L886
    addi t1, a1, 63
L886:
    sw   a2, 0(s3)
    andi t5, s2, 1
    bnez t5, L887
    addi t0, t3, 1
L887:
    lw   a1, 20(s0)
    lw   t4, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L888
    xor  t4, a2, t2
L888:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L889
    xor  a1, t0, a4
L889:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L890
    xor  t3, a1, a2
L890:
    sw   a1, 24(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L891
    addi t3, a4, -97
L891:
    andi t5, s2, 1024
    beqz t5, L892
    addi a4, a2, 29
L892:
    andi t5, s2, 2
    bnez t5, L893
    addi t0, a3, -23
L893:
    sw   a1, 0(s3)
    andi t5, s2, 2
    beqz t5, L894
    addi t4, t0, 1
L894:
    andi t5, s2, 2
    bnez t5, L895
    addi a2, a1, 1
L895:
    lb   t1, 21(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L896
    xor  a5, a3, t1
L896:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L897
    xor  a1, t0, t0
L897:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L898
    xor  t2, a2, t2
L898:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L899
    xor  a3, a4, a3
L899:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L900
    addi a3, a1, 63
L900:
    sb   t2, 0(s3)
    andi t5, s2, 2
    beqz t5, L901
    addi a3, t0, 1
L901:
    andi t5, s2, 4
    bnez t5, L902
    addi t3, a3, 1
L902:
    lhu   a5, 8(s0)
    lb   t4, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L903
    xor  a3, a5, t1
L903:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L904
    xor  a5, a5, a4
L904:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L905
    xor  a2, a3, a3
L905:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L906
    addi a2, a1, -51
L906:
    andi t5, s2, 4
    beqz t5, L907
    addi t4, a3, 69
L907:
    andi t5, s2, 1024
    beqz t5, L908
    addi t0, t3, -81
L908:
    sb   a4, 0(s3)
    andi t5, s2, 1024
    beqz t5, L909
    addi t2, t1, 1
L909:
    lb   a3, 2(s0)
    lhu   a3, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L910
    xor  t0, t2, t1
L910:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L911
    xor  t1, t3, a5
L911:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L912
    xor  t2, t2, t1
L912:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L913
    addi a4, a1, -49
L913:
    andi t5, s2, 256
    beqz t5, L914
    addi a1, a2, 42
L914:
    sb   a4, 0(s3)
    andi t5, s2, 4
    beqz t5, L915
    addi t2, t1, 1
L915:
    andi t5, s2, 16
    beqz t5, L916
    addi t0, t3, 1
L916:
    lb   t2, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L917
    xor  a4, a4, a1
L917:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L918
    xor  t3, a4, t0
L918:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L919
    xor  t2, a3, a3
L919:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L920
    xor  t2, t4, t2
L920:
    sw   t1, 8(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L921
    addi a3, t0, -95
L921:
    andi t5, s2, 512
    bnez t5, L922
    addi a3, a3, 19
L922:
    andi t5, s2, 256
    beqz t5, L923
    addi a4, a5, 61
L923:
    sb   t0, 0(s3)
    andi t5, s2, 64
    beqz t5, L924
    addi t1, t2, 1
L924:
    andi t5, s2, 4
    beqz t5, L925
    addi a1, t3, 1
L925:
    lw   t1, 28(s0)
    lhu   a2, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L926
    xor  t0, t1, a2
L926:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L927
    xor  t0, t4, a1
L927:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L928
    xor  t4, a2, a1
L928:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L929
    xor  t1, t3, a3
L929:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L930
    addi a1, a2, -31
L930:
    andi t5, s2, 1
    bnez t5, L931
    addi t2, a4, -88
L931:
    sb   a2, 0(s3)
    andi t5, s2, 16
    bnez t5, L932
    addi t0, a1, 1
L932:
    andi t5, s2, 1
    beqz t5, L933
    addi t3, a1, 1
L933:
    lw   a1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L934
    xor  t1, t4, a4
L934:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L935
    xor  t0, a1, t3
L935:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L936
    xor  t3, a3, a1
L936:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L937
    xor  a1, a4, a2
L937:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L938
    addi t3, t2, 39
L938:
    sb   t2, 0(s3)
    andi t5, s2, 256
    bnez t5, L939
    addi a3, t4, 1
L939:
    lhu   t4, 12(s0)
    lw   t3, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L940
    xor  t1, t2, a3
L940:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L941
    xor  a5, t4, a4
L941:
    sw   t4, 4(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L942
    addi t1, t3, -9
L942:
    andi t5, s2, 8
    bnez t5, L943
    addi t0, a3, -90
L943:
    sh   t2, 0(s3)
    andi t5, s2, 256
    bnez t5, L944
    addi t4, a2, 1
L944:
    lw   t2, 4(s0)
    lhu   t1, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L945
    xor  a4, t4, t1
L945:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L946
    xor  t2, a5, t1
L946:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L947
    xor  t0, a3, t3
L947:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L948
    addi a3, a2, -59
L948:
    sw   t2, 0(s3)
    andi t5, s2, 64
    bnez t5, L949
    addi a2, a3, 1
L949:
    lhu   t1, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L950
    xor  a4, t2, t4
L950:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L951
    xor  t1, a2, a4
L951:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L952
    addi a5, t4, 2
L952:
    sw   t2, 0(s3)
    andi t5, s2, 64
    beqz t5, L953
    addi a2, t4, 1
L953:
    lb   t3, 12(s0)
    lw   t1, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L954
    xor  a1, a2, t4
L954:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L955
    xor  a4, a1, t0
L955:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L956
    xor  t4, a1, a4
L956:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L957
    addi t0, t2, 10
L957:
    andi t5, s2, 512
    bnez t5, L958
    addi a5, a2, 6
L958:
    sw   a3, 0(s3)
    andi t5, s2, 16
    bnez t5, L959
    addi t2, a1, 1
L959:
    lw   t2, 16(s0)
    lb   t2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L960
    xor  t2, a5, t1
L960:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L961
    xor  a2, a5, a5
L961:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L962
    addi a3, t3, -54
L962:
    andi t5, s2, 256
    bnez t5, L963
    addi a1, t3, -63
L963:
    sw   t1, 0(s3)
    andi t5, s2, 1
    beqz t5, L964
    addi a5, a3, 1
L964:
    andi t5, s2, 8
    beqz t5, L965
    addi a5, a4, 1
L965:
    lw   t2, 8(s0)
    lb   t3, 21(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L966
    xor  a4, t2, t4
L966:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L967
    xor  t2, t4, t1
L967:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L968
    xor  t1, a3, t3
L968:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L969
    addi a1, a4, 66
L969:
    andi t5, s2, 16
    bnez t5, L970
    addi a4, a2, -11
L970:
    andi t5, s2, 4
    bnez t5, L971
    addi t4, t4, 44
L971:
    sb   t1, 0(s3)
    andi t5, s2, 1
    beqz t5, L972
    addi a3, a5, 1
L972:
    lb   a1, 23(s0)
    lb   t4, 13(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L973
    xor  t0, t0, t2
L973:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L974
    xor  t2, a5, a2
L974:
    sw   a1, 12(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L975
    addi t1, t2, -90
L975:
    andi t5, s2, 1
    bnez t5, L976
    addi a3, a1, 54
L976:
    sw   t4, 0(s3)
    andi t5, s2, 512
    beqz t5, L977
    addi t4, t4, 1
L977:
    andi t5, s2, 1024
    bnez t5, L978
    addi a4, t1, 1
L978:
    lhu   a1, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L979
    xor  t0, a1, t3
L979:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L980
    xor  t2, t1, t4
L980:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L981
    addi t4, a1, -39
L981:
    sb   t3, 0(s3)
    andi t5, s2, 16
    beqz t5, L982
    addi a5, t1, 1
L982:
    andi t5, s2, 256
    bnez t5, L983
    addi a3, a5, 1
L983:
    lw   a5, 8(s0)
    lw   a2, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L984
    xor  t0, t0, t2
L984:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L985
    xor  t4, t0, t1
L985:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L986
    xor  t3, t1, a4
L986:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L987
    addi a3, a2, -17
L987:
    andi t5, s2, 32
    bnez t5, L988
    addi t3, t2, 87
L988:
    sw   t2, 0(s3)
    andi t5, s2, 256
    bnez t5, L989
    addi t0, a5, 1
L989:
    andi t5, s2, 1
    beqz t5, L990
    addi a5, a2, 1
L990:
    lw   t1, 4(s0)
    lw   t1, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L991
    xor  a3, a2, a4
L991:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L992
    xor  a5, t1, a2
L992:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L993
    addi a4, a5, -17
L993:
    andi t5, s2, 1
    bnez t5, L994
    addi a3, a1, 89
L994:
    sw   t3, 0(s3)
    andi t5, s2, 1
    beqz t5, L995
    addi t0, t4, 1
L995:
    andi t5, s2, 128
    beqz t5, L996
    addi a2, a5, 1
L996:
    lw   a4, 24(s0)
    lhu   t2, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L997
    xor  t3, t2, t1
L997:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L998
    xor  t4, a2, t2
L998:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L999
    xor  a1, t2, t3
L999:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L1000
    addi a4, t3, -19
L1000:
    andi t5, s2, 512
    bnez t5, L1001
    addi a5, t1, -40
L1001:
    sw   a2, 0(s3)
    andi t5, s2, 256
    bnez t5, L1002
    addi t2, t4, 1
L1002:
    andi t5, s2, 32
    beqz t5, L1003
    addi a4, a5, 1
L1003:
    lw   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1004
    xor  a4, a5, t3
L1004:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1005
    xor  t0, a1, t0
L1005:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1006
    xor  a2, t0, a4
L1006:
    sw   a4, 24(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1007
    addi a5, t4, -74
L1007:
    andi t5, s2, 8
    beqz t5, L1008
    addi t3, t1, 75
L1008:
    andi t5, s2, 2
    beqz t5, L1009
    addi a4, a4, -84
L1009:
    sb   t2, 0(s3)
    andi t5, s2, 256
    bnez t5, L1010
    addi a2, a4, 1
L1010:
    andi t5, s2, 64
    bnez t5, L1011
    addi t2, a2, 1
L1011:
    lw   t0, 28(s0)
    lw   t4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1012
    xor  a1, a3, a4
L1012:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1013
    xor  t2, a3, t3
L1013:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1014
    addi t3, t2, -29
L1014:
    sw   a5, 0(s3)
    andi t5, s2, 256
    beqz t5, L1015
    addi t1, a5, 1
L1015:
    lhu   a5, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1016
    xor  a2, a5, t2
L1016:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1017
    xor  a5, t3, a1
L1017:
    sw   a3, 0(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1018
    addi a5, a1, -95
L1018:
    sw   a2, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1019
    addi t3, t4, 1
L1019:
    andi t5, s2, 128
    beqz t5, L1020
    addi a2, t4, 1
L1020:
    lb   a2, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1021
    xor  t4, t4, t3
L1021:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1022
    xor  a1, t1, t0
L1022:
    sw   a1, 24(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1023
    addi a4, t3, 33
L1023:
    andi t5, s2, 2
    bnez t5, L1024
    addi a3, t2, -98
L1024:
    sb   t3, 0(s3)
    andi t5, s2, 8
    beqz t5, L1025
    addi t0, a1, 1
L1025:
    andi t5, s2, 4
    bnez t5, L1026
    addi t1, t3, 1
L1026:
    lw   a5, 0(s0)
    lhu   t3, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1027
    xor  t2, a5, t1
L1027:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1028
    xor  t3, t3, a5
L1028:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1029
    xor  t2, t0, a4
L1029:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1030
    xor  t4, a1, t2
L1030:
    sw   t1, 12(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1031
    addi a5, a3, 86
L1031:
    sw   a4, 0(s3)
    andi t5, s2, 1
    beqz t5, L1032
    addi a1, a2, 1
L1032:
    lw   a4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1033
    xor  t1, a5, t1
L1033:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1034
    xor  t0, t0, a3
L1034:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1035
    xor  t0, t1, t2
L1035:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1036
    addi a2, t1, -72
L1036:
    sb   a5, 0(s3)
    andi t5, s2, 32
    bnez t5, L1037
    addi a2, a5, 1
L1037:
    andi t5, s2, 16
    beqz t5, L1038
    addi a4, t4, 1
L1038:
    lb   t1, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1039
    xor  t4, t2, a2
L1039:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1040
    xor  a1, t3, t3
L1040:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1041
    addi a5, t3, -46
L1041:
    andi t5, s2, 1
    beqz t5, L1042
    addi t2, t0, -75
L1042:
    andi t5, s2, 512
    beqz t5, L1043
    addi a5, t3, -93
L1043:
    sw   t2, 0(s3)
    andi t5, s2, 8
    beqz t5, L1044
    addi t3, t4, 1
L1044:
    andi t5, s2, 32
    beqz t5, L1045
    addi t3, a4, 1
L1045:
    lhu   a4, 16(s0)
    lhu   t1, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1046
    xor  t4, a3, a3
L1046:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1047
    xor  t4, a1, a3
L1047:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1048
    xor  a2, a3, t3
L1048:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1049
    addi t1, a3, -94
L1049:
    andi t5, s2, 256
    beqz t5, L1050
    addi a1, a1, 66
L1050:
    andi t5, s2, 2
    beqz t5, L1051
    addi a5, a4, -96
L1051:
    sh   t3, 0(s3)
    andi t5, s2, 4
    beqz t5, L1052
    addi a1, t4, 1
L1052:
    lw   a4, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1053
    xor  t1, a1, a2
L1053:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1054
    xor  t1, t0, a1
L1054:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1055
    xor  t4, a4, a4
L1055:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1056
    xor  t0, t1, a3
L1056:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L1057
    addi t2, t1, -28
L1057:
    andi t5, s2, 128
    beqz t5, L1058
    addi t4, a3, -60
L1058:
    andi t5, s2, 8
    beqz t5, L1059
    addi a2, a4, -92
L1059:
    sh   t1, 0(s3)
    andi t5, s2, 1024
    bnez t5, L1060
    addi a5, t0, 1
L1060:
    andi t5, s2, 1024
    beqz t5, L1061
    addi t3, t3, 1
L1061:
    lb   t2, 5(s0)
    lhu   a2, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1062
    xor  t4, t3, a3
L1062:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1063
    xor  a4, t1, a4
L1063:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1064
    xor  a1, a1, a3
L1064:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L1065
    addi t1, a1, -42
L1065:
    andi t5, s2, 256
    bnez t5, L1066
    addi t4, a4, -92
L1066:
    sw   t2, 0(s3)
    andi t5, s2, 512
    beqz t5, L1067
    addi t3, t0, 1
L1067:
    andi t5, s2, 1
    beqz t5, L1068
    addi a1, a4, 1
L1068:
    lw   a5, 24(s0)
    lhu   t0, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1069
    xor  t2, t4, t3
L1069:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1070
    xor  t1, a5, t4
L1070:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1071
    xor  t0, t2, t4
L1071:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1072
    xor  a5, t2, t4
L1072:
    sw   a1, 0(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1073
    addi a4, t0, -35
L1073:
    andi t5, s2, 32
    beqz t5, L1074
    addi a1, t3, -100
L1074:
    andi t5, s2, 16
    beqz t5, L1075
    addi t2, t0, -59
L1075:
    sb   t0, 0(s3)
    andi t5, s2, 4
    bnez t5, L1076
    addi t2, a4, 1
L1076:
    andi t5, s2, 512
    bnez t5, L1077
    addi t4, t3, 1
L1077:
    lb   a4, 14(s0)
    lb   t0, 17(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1078
    xor  t4, t1, a4
L1078:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1079
    xor  t3, a3, t2
L1079:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1080
    xor  a2, a4, a3
L1080:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1081
    xor  t0, a5, t0
L1081:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1082
    addi a4, t4, 21
L1082:
    sw   a5, 0(s3)
    andi t5, s2, 64
    bnez t5, L1083
    addi a2, a3, 1
L1083:
    lb   t4, 3(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1084
    xor  t3, a3, t2
L1084:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1085
    xor  a1, a3, a1
L1085:
    sw   a3, 12(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L1086
    addi t4, t2, -81
L1086:
    andi t5, s2, 1
    beqz t5, L1087
    addi a2, t1, -36
L1087:
    andi t5, s2, 128
    beqz t5, L1088
    addi t2, a2, 12
L1088:
    sw   t0, 0(s3)
    andi t5, s2, 64
    bnez t5, L1089
    addi t3, a5, 1
L1089:
    lw   t2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1090
    xor  t1, t4, a2
L1090:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1091
    xor  t3, t0, a5
L1091:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1092
    xor  t1, a2, t4
L1092:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1093
    xor  t3, a4, t1
L1093:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1094
    addi t0, t0, 2
L1094:
    andi t5, s2, 512
    beqz t5, L1095
    addi t0, t4, 29
L1095:
    sw   t2, 0(s3)
    andi t5, s2, 64
    beqz t5, L1096
    addi a2, t0, 1
L1096:
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1097
    xor  a1, a1, a5
L1097:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1098
    xor  a2, a5, t1
L1098:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1099
    xor  t1, t2, t2
L1099:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L1100
    addi a2, a1, 56
L1100:
    andi t5, s2, 4
    beqz t5, L1101
    addi t2, t4, -74
L1101:
    sh   t3, 0(s3)
    andi t5, s2, 256
    beqz t5, L1102
    addi a5, t3, 1
L1102:
    lw   t4, 8(s0)
    lb   t1, 9(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1103
    xor  t3, a1, a2
L1103:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1104
    xor  a1, a2, a2
L1104:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1105
    xor  a1, t3, a1
L1105:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1106
    addi a2, a2, -48
L1106:
    andi t5, s2, 2
    beqz t5, L1107
    addi t0, a4, 5
L1107:
    andi t5, s2, 1
    beqz t5, L1108
    addi t3, t4, 90
L1108:
    sw   t2, 0(s3)
    andi t5, s2, 128
    beqz t5, L1109
    addi t1, t0, 1
L1109:
    andi t5, s2, 8
    beqz t5, L1110
    addi a4, t4, 1
L1110:
    lhu   a1, 30(s0)
    lw   a1, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1111
    xor  a5, a5, t2
L1111:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1112
    xor  t2, t1, t4
L1112:
    sw   a1, 8(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1113
    addi t3, a4, 67
L1113:
    sw   a4, 0(s3)
    andi t5, s2, 512
    beqz t5, L1114
    addi a5, a3, 1
L1114:
    andi t5, s2, 128
    bnez t5, L1115
    addi t4, t4, 1
L1115:
    lhu   t1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1116
    xor  a4, t4, a3
L1116:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1117
    xor  t3, t2, t0
L1117:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1118
    addi t3, a2, -57
L1118:
    andi t5, s2, 8
    beqz t5, L1119
    addi a5, t4, 27
L1119:
    andi t5, s2, 16
    bnez t5, L1120
    addi t0, a2, 89
L1120:
    sb   a4, 0(s3)
    andi t5, s2, 2
    bnez t5, L1121
    addi a3, a5, 1
L1121:
    lb   t3, 27(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1122
    xor  t2, t4, a2
L1122:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1123
    xor  a3, t4, a5
L1123:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1124
    xor  t1, a3, t0
L1124:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1125
    xor  t4, a3, t3
L1125:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1126
    addi a5, t2, -67
L1126:
    sw   a4, 0(s3)
    andi t5, s2, 1024
    bnez t5, L1127
    addi a3, t3, 1
L1127:
    andi t5, s2, 8
    bnez t5, L1128
    addi a5, a5, 1
L1128:
    lb   a3, 17(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1129
    xor  a1, t1, t1
L1129:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1130
    xor  t0, t2, t4
L1130:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1131
    xor  t2, t4, a2
L1131:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1132
    xor  t2, t0, a4
L1132:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L1133
    addi t1, a2, -95
L1133:
    andi t5, s2, 1024
    bnez t5, L1134
    addi t4, t3, 98
L1134:
    andi t5, s2, 2
    beqz t5, L1135
    addi t2, t3, -59
L1135:
    sh   t2, 0(s3)
    andi t5, s2, 256
    beqz t5, L1136
    addi t1, a2, 1
L1136:
    andi t5, s2, 256
    bnez t5, L1137
    addi a1, t2, 1
L1137:
    lb   t2, 21(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1138
    xor  t3, a2, a4
L1138:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1139
    xor  t2, a2, t1
L1139:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1140
    xor  a3, t2, t0
L1140:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1141
    xor  a4, a3, t4
L1141:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1142
    addi a2, a3, 10
L1142:
    andi t5, s2, 256
    beqz t5, L1143
    addi t2, t3, 58
L1143:
    andi t5, s2, 32
    bnez t5, L1144
    addi t4, t1, 98
L1144:
    sb   t2, 0(s3)
    andi t5, s2, 32
    bnez t5, L1145
    addi a5, t3, 1
L1145:
    andi t5, s2, 256
    bnez t5, L1146
    addi t2, t1, 1
L1146:
    lb   a5, 9(s0)
    lw   t4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1147
    xor  t3, a4, a3
L1147:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1148
    xor  a5, a2, a1
L1148:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1149
    xor  a3, a2, a2
L1149:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1150
    xor  a2, t2, a3
L1150:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L1151
    addi t4, a3, 95
L1151:
    sb   t1, 0(s3)
    andi t5, s2, 32
    beqz t5, L1152
    addi a5, t1, 1
L1152:
    lw   t4, 0(s0)
    lhu   a5, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1153
    xor  a3, t1, t4
L1153:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1154
    xor  t0, a1, a5
L1154:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1155
    xor  a2, a1, t4
L1155:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1156
    xor  t2, a3, a5
L1156:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L1157
    addi t2, a2, -13
L1157:
    sw   a2, 0(s3)
    andi t5, s2, 16
    bnez t5, L1158
    addi a3, t1, 1
L1158:
    lw   t2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1159
    xor  t2, t3, a5
L1159:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1160
    xor  a1, t2, a5
L1160:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1161
    xor  a3, t4, a2
L1161:
    sw   a4, 16(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1162
    addi t1, t4, -69
L1162:
    andi t5, s2, 1024
    bnez t5, L1163
    addi t4, t1, -41
L1163:
    andi t5, s2, 64
    bnez t5, L1164
    addi t0, t1, -31
L1164:
    sw   t3, 0(s3)
    andi t5, s2, 16
    beqz t5, L1165
    addi a4, t1, 1
L1165:
    lw   a3, 12(s0)
    lw   a1, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1166
    xor  t4, t3, a5
L1166:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1167
    xor  a1, t4, t1
L1167:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1168
    xor  a3, a1, a3
L1168:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1169
    xor  t0, t3, t2
L1169:
    sw   a2, 12(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1170
    addi a4, t4, -63
L1170:
    andi t5, s2, 1
    beqz t5, L1171
    addi t2, a4, -53
L1171:
    andi t5, s2, 32
    bnez t5, L1172
    addi t1, a2, 47
L1172:
    sb   a3, 0(s3)
    andi t5, s2, 8
    bnez t5, L1173
    addi t4, a4, 1
L1173:
    andi t5, s2, 2
    beqz t5, L1174
    addi t4, a5, 1
L1174:
    lb   t2, 0(s0)
    lw   t3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1175
    xor  t4, t3, a5
L1175:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1176
    xor  t1, t2, a5
L1176:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1177
    xor  a5, t4, t3
L1177:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1178
    addi t4, a5, -7
L1178:
    sb   a5, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1179
    addi t2, a1, 1
L1179:
    andi t5, s2, 32
    beqz t5, L1180
    addi a5, t1, 1
L1180:
    lhu   t0, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1181
    xor  a1, a1, a3
L1181:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1182
    xor  a2, t0, t2
L1182:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1183
    xor  a2, a3, t2
L1183:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1184
    xor  t3, a4, t4
L1184:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1185
    addi a1, a2, 46
L1185:
    sw   a5, 0(s3)
    andi t5, s2, 8
    beqz t5, L1186
    addi a3, t1, 1
L1186:
    lb   t0, 26(s0)
    lw   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1187
    xor  t4, t0, a1
L1187:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1188
    xor  t4, a4, a5
L1188:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1189
    xor  a4, t2, t3
L1189:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L1190
    addi a3, t2, -11
L1190:
    andi t5, s2, 128
    bnez t5, L1191
    addi a3, a5, -14
L1191:
    andi t5, s2, 8
    bnez t5, L1192
    addi t2, t0, -5
L1192:
    sh   t0, 0(s3)
    andi t5, s2, 64
    bnez t5, L1193
    addi t0, a5, 1
L1193:
    lw   t1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1194
    xor  t1, a5, t3
L1194:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1195
    xor  a3, a2, t3
L1195:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1196
    addi a1, t4, -79
L1196:
    sb   a2, 0(s3)
    andi t5, s2, 512
    beqz t5, L1197
    addi a5, t0, 1
L1197:
    andi t5, s2, 512
    bnez t5, L1198
    addi t2, t4, 1
L1198:
    lw   t0, 0(s0)
    lw   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1199
    xor  a4, t0, a5
L1199:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1200
    xor  t1, t1, t0
L1200:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1201
    xor  t1, a1, t2
L1201:
    sw   t4, 12(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1202
    addi t3, t4, -68
L1202:
    andi t5, s2, 128
    beqz t5, L1203
    addi t3, t4, -93
L1203:
    sw   a5, 0(s3)
    andi t5, s2, 4
    beqz t5, L1204
    addi t3, a3, 1
L1204:
    lw   t1, 20(s0)
    lw   t1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1205
    xor  t4, a3, t4
L1205:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1206
    xor  t0, a1, t0
L1206:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1207
    xor  t2, t4, t0
L1207:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1208
    addi a2, a2, -67
L1208:
    sw   t2, 0(s3)
    andi t5, s2, 512
    beqz t5, L1209
    addi a4, t4, 1
L1209:
    andi t5, s2, 2
    bnez t5, L1210
    addi a4, a2, 1
L1210:
    lb   a3, 1(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1211
    xor  t2, a1, a4
L1211:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1212
    xor  t3, t0, t0
L1212:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1213
    xor  a4, a1, t1
L1213:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1214
    xor  t0, a3, t3
L1214:
    sw   a1, 28(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1215
    addi a1, a5, 12
L1215:
    andi t5, s2, 8
    beqz t5, L1216
    addi a1, t0, 1
L1216:
    sw   t1, 0(s3)
    andi t5, s2, 4
    beqz t5, L1217
    addi a4, a1, 1
L1217:
    lhu   t1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1218
    xor  t0, t3, a4
L1218:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1219
    xor  a1, a4, t3
L1219:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1220
    xor  a3, a2, t2
L1220:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1221
    addi a5, t1, -38
L1221:
    andi t5, s2, 32
    bnez t5, L1222
    addi t2, t1, -32
L1222:
    andi t5, s2, 128
    beqz t5, L1223
    addi t3, a2, -35
L1223:
    sw   a4, 0(s3)
    andi t5, s2, 32
    bnez t5, L1224
    addi t2, a2, 1
L1224:
    andi t5, s2, 512
    bnez t5, L1225
    addi t0, a5, 1
L1225:
    lhu   a1, 10(s0)
    lhu   t3, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1226
    xor  a4, a5, t1
L1226:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1227
    xor  a4, a5, t2
L1227:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L1228
    addi t1, t3, -73
L1228:
    andi t5, s2, 32
    bnez t5, L1229
    addi a1, t0, 24
L1229:
    andi t5, s2, 64
    bnez t5, L1230
    addi t2, a4, -3
L1230:
    sw   t0, 0(s3)
    andi t5, s2, 128
    bnez t5, L1231
    addi a1, t3, 1
L1231:
    andi t5, s2, 2
    beqz t5, L1232
    addi a3, a1, 1
L1232:
    lhu   t0, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1233
    xor  a1, a5, t2
L1233:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1234
    xor  a4, a5, a2
L1234:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1235
    xor  a5, a5, t0
L1235:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1236
    xor  t3, t1, a1
L1236:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L1237
    addi a1, t2, 23
L1237:
    sw   a1, 0(s3)
    andi t5, s2, 1024
    bnez t5, L1238
    addi t1, a4, 1
L1238:
    lw   a2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1239
    xor  a5, t4, t3
L1239:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1240
    xor  t2, t3, a1
L1240:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1241
    xor  a2, t4, t4
L1241:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L1242
    addi a2, t2, 29
L1242:
    andi t5, s2, 16
    bnez t5, L1243
    addi a5, a5, 58
L1243:
    sb   a2, 0(s3)
    andi t5, s2, 32
    bnez t5, L1244
    addi t3, a3, 1
L1244:
    andi t5, s2, 256
    bnez t5, L1245
    addi t0, t3, 1
L1245:
    lb   t2, 25(s0)
    lhu   t2, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1246
    xor  a2, t2, a4
L1246:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1247
    xor  a3, t3, t1
L1247:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1248
    addi t2, t2, 35
L1248:
    andi t5, s2, 1
    bnez t5, L1249
    addi a2, a3, -95
L1249:
    sw   a2, 0(s3)
    andi t5, s2, 16
    bnez t5, L1250
    addi t3, a4, 1
L1250:
    lhu   t0, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1251
    xor  a2, t3, a5
L1251:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1252
    xor  t0, t4, t3
L1252:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1253
    xor  t1, a3, t0
L1253:
    sw   t3, 16(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1254
    addi a3, a2, 75
L1254:
    sh   a3, 0(s3)
    andi t5, s2, 4
    beqz t5, L1255
    addi a3, t1, 1
L1255:
    lw   t1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1256
    xor  a2, a3, a3
L1256:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1257
    xor  a4, t2, a5
L1257:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1258
    xor  t4, a4, a1
L1258:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1259
    xor  a3, a1, t2
L1259:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1260
    addi a1, t1, -46
L1260:
    sw   t4, 0(s3)
    andi t5, s2, 512
    bnez t5, L1261
    addi a3, a5, 1
L1261:
    andi t5, s2, 1
    beqz t5, L1262
    addi a3, t3, 1
L1262:
    lhu   t2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1263
    xor  a4, a2, t3
L1263:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1264
    xor  a2, a2, t2
L1264:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1265
    xor  a5, t3, t3
L1265:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1266
    addi a4, a5, 34
L1266:
    andi t5, s2, 4
    bnez t5, L1267
    addi t1, a2, 11
L1267:
    andi t5, s2, 128
    bnez t5, L1268
    addi a5, t0, 47
L1268:
    sh   a5, 0(s3)
    andi t5, s2, 64
    bnez t5, L1269
    addi t1, a1, 1
L1269:
    lhu   a4, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1270
    xor  t0, t3, t1
L1270:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1271
    xor  t2, a4, t0
L1271:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1272
    xor  t2, a3, a2
L1272:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1273
    xor  t0, a1, t0
L1273:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L1274
    addi a4, t3, 55
L1274:
    andi t5, s2, 1024
    bnez t5, L1275
    addi t2, t4, 64
L1275:
    andi t5, s2, 128
    bnez t5, L1276
    addi a1, a3, -22
L1276:
    sw   a2, 0(s3)
    andi t5, s2, 64
    beqz t5, L1277
    addi t3, a3, 1
L1277:
    lhu   t4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1278
    xor  a1, a2, t0
L1278:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1279
    xor  a5, a2, t3
L1279:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1280
    xor  a2, a3, t0
L1280:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1281
    xor  a5, a1, a4
L1281:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1282
    addi a3, t0, -49
L1282:
    andi t5, s2, 16
    beqz t5, L1283
    addi a1, a3, -73
L1283:
    sw   a2, 0(s3)
    andi t5, s2, 1
    beqz t5, L1284
    addi t0, t1, 1
L1284:
    andi t5, s2, 8
    bnez t5, L1285
    addi t4, a3, 1
L1285:
    lw   t0, 28(s0)
    lw   a3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1286
    xor  a3, a2, a3
L1286:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1287
    xor  a4, t3, a3
L1287:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L1288
    addi t0, t3, -50
L1288:
    sw   t2, 0(s3)
    andi t5, s2, 512
    bnez t5, L1289
    addi t2, a3, 1
L1289:
    lw   a2, 0(s0)
    lw   a1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1290
    xor  a4, a4, t0
L1290:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1291
    xor  a4, a5, t2
L1291:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1292
    xor  a5, t0, a4
L1292:
    sw   a2, 12(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1293
    addi a3, a3, -23
L1293:
    andi t5, s2, 8
    bnez t5, L1294
    addi a1, t4, -91
L1294:
    sw   a2, 0(s3)
    andi t5, s2, 1
    bnez t5, L1295
    addi t2, a4, 1
L1295:
    lw   a4, 4(s0)
    lw   a5, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1296
    xor  a4, a4, t1
L1296:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1297
    xor  t2, a3, a5
L1297:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1298
    xor  a4, a5, a2
L1298:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1299
    xor  a2, t1, a4
L1299:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1300
    addi a2, a2, -17
L1300:
    sh   t1, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1301
    addi a3, a4, 1
L1301:
    andi t5, s2, 1024
    beqz t5, L1302
    addi a3, t1, 1
L1302:
    lw   t0, 20(s0)
    lw   t2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1303
    xor  a3, t3, t2
L1303:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1304
    xor  a4, t3, t3
L1304:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1305
    xor  t2, a1, a3
L1305:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1306
    xor  a1, a3, a5
L1306:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L1307
    addi t2, a3, 65
L1307:
    andi t5, s2, 32
    beqz t5, L1308
    addi a5, a5, -1
L1308:
    andi t5, s2, 2
    beqz t5, L1309
    addi t1, t1, 4
L1309:
    sh   t4, 0(s3)
    andi t5, s2, 32
    beqz t5, L1310
    addi a1, a4, 1
L1310:
    andi t5, s2, 128
    bnez t5, L1311
    addi t3, a3, 1
L1311:
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1312
    xor  t0, a4, a5
L1312:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1313
    xor  t3, t0, a2
L1313:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1314
    addi t1, a3, -34
L1314:
    andi t5, s2, 32
    bnez t5, L1315
    addi t1, t3, 67
L1315:
    sw   a1, 0(s3)
    andi t5, s2, 64
    beqz t5, L1316
    addi a1, t1, 1
L1316:
    andi t5, s2, 512
    bnez t5, L1317
    addi t4, a3, 1
L1317:
    lw   a2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1318
    xor  t0, t2, a5
L1318:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1319
    xor  t1, t2, a4
L1319:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1320
    xor  t2, t4, a4
L1320:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1321
    xor  a1, t0, t1
L1321:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L1322
    addi t1, t4, -6
L1322:
    andi t5, s2, 512
    bnez t5, L1323
    addi t4, t1, 0
L1323:
    sb   a2, 0(s3)
    andi t5, s2, 2
    beqz t5, L1324
    addi a2, t4, 1
L1324:
    andi t5, s2, 128
    beqz t5, L1325
    addi t1, t4, 1
L1325:
    lw   a2, 12(s0)
    lw   t3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1326
    xor  t4, t3, a1
L1326:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1327
    xor  t0, t0, a2
L1327:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1328
    xor  a5, a5, t3
L1328:
    sw   t3, 16(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1329
    addi a4, a1, -6
L1329:
    sh   a2, 0(s3)
    andi t5, s2, 2
    beqz t5, L1330
    addi a5, a4, 1
L1330:
    andi t5, s2, 512
    beqz t5, L1331
    addi a3, t3, 1
L1331:
    lw   a4, 28(s0)
    lb   a1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1332
    xor  t2, a4, t0
L1332:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1333
    xor  a5, a4, a2
L1333:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1334
    addi a5, a4, -7
L1334:
    andi t5, s2, 256
    bnez t5, L1335
    addi a4, t3, 78
L1335:
    sb   t2, 0(s3)
    andi t5, s2, 16
    beqz t5, L1336
    addi t3, t3, 1
L1336:
    andi t5, s2, 256
    bnez t5, L1337
    addi a4, a5, 1
L1337:
    lw   t4, 28(s0)
    lb   a2, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1338
    xor  t4, a3, a4
L1338:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1339
    xor  a5, t3, t2
L1339:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1340
    addi t1, a1, -41
L1340:
    sw   t3, 0(s3)
    andi t5, s2, 8
    bnez t5, L1341
    addi a2, t3, 1
L1341:
    andi t5, s2, 16
    beqz t5, L1342
    addi a4, a3, 1
L1342:
    lhu   a1, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1343
    xor  a5, a5, t1
L1343:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1344
    xor  a5, a3, t2
L1344:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1345
    xor  a5, t4, t2
L1345:
    sw   a3, 8(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1346
    addi a2, a1, 82
L1346:
    andi t5, s2, 8
    beqz t5, L1347
    addi t4, a4, 35
L1347:
    sh   a2, 0(s3)
    andi t5, s2, 512
    bnez t5, L1348
    addi t1, t1, 1
L1348:
    andi t5, s2, 512
    bnez t5, L1349
    addi a3, t2, 1
L1349:
    lhu   a5, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1350
    xor  t3, a1, a2
L1350:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1351
    xor  t0, t3, a3
L1351:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1352
    addi a4, a5, 89
L1352:
    andi t5, s2, 4
    bnez t5, L1353
    addi t4, t1, 95
L1353:
    andi t5, s2, 1024
    bnez t5, L1354
    addi t2, t3, 76
L1354:
    sb   a4, 0(s3)
    andi t5, s2, 128
    bnez t5, L1355
    addi t4, t2, 1
L1355:
    lw   t3, 16(s0)
    lhu   t2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1356
    xor  t0, t3, t2
L1356:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1357
    xor  t2, a2, t3
L1357:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1358
    xor  a1, t1, a4
L1358:
    sw   t2, 20(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1359
    addi t1, a3, -30
L1359:
    andi t5, s2, 8
    bnez t5, L1360
    addi t0, a5, -88
L1360:
    sw   t3, 0(s3)
    andi t5, s2, 4
    beqz t5, L1361
    addi a5, t1, 1
L1361:
    andi t5, s2, 16
    bnez t5, L1362
    addi a5, a2, 1
L1362:
    lhu   t4, 30(s0)
    lb   t2, 1(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1363
    xor  a2, t2, a5
L1363:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1364
    xor  a1, t0, t1
L1364:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1365
    addi t3, t2, -71
L1365:
    sb   t3, 0(s3)
    andi t5, s2, 512
    beqz t5, L1366
    addi t2, t4, 1
L1366:
    andi t5, s2, 2
    beqz t5, L1367
    addi t4, a2, 1
L1367:
    lhu   t3, 28(s0)
    lb   a4, 15(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1368
    xor  t4, t0, t4
L1368:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1369
    xor  a1, a1, t0
L1369:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1370
    xor  t4, a2, t3
L1370:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1371
    xor  t2, t0, a3
L1371:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L1372
    addi a2, t0, 32
L1372:
    andi t5, s2, 1
    bnez t5, L1373
    addi a3, a5, -62
L1373:
    andi t5, s2, 4
    beqz t5, L1374
    addi t0, a1, -98
L1374:
    sb   t2, 0(s3)
    andi t5, s2, 256
    beqz t5, L1375
    addi t2, a3, 1
L1375:
    lhu   t1, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1376
    xor  t0, a4, a4
L1376:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1377
    xor  a1, t0, a1
L1377:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1378
    xor  a3, t2, a3
L1378:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1379
    xor  t4, a1, a2
L1379:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1380
    addi a5, t4, 78
L1380:
    sw   t2, 0(s3)
    andi t5, s2, 8
    beqz t5, L1381
    addi t0, t2, 1
L1381:
    andi t5, s2, 64
    beqz t5, L1382
    addi t3, t2, 1
L1382:
    lw   t0, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1383
    xor  t2, t3, t3
L1383:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1384
    xor  t4, t2, a2
L1384:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1385
    xor  t3, a1, a1
L1385:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1386
    xor  a5, t3, a4
L1386:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1387
    addi t2, t1, -14
L1387:
    andi t5, s2, 4
    bnez t5, L1388
    addi t0, t4, -75
L1388:
    sw   a3, 0(s3)
    andi t5, s2, 4
    beqz t5, L1389
    addi t4, t3, 1
L1389:
    andi t5, s2, 16
    beqz t5, L1390
    addi t4, a2, 1
L1390:
    lb   a2, 9(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1391
    xor  t3, a2, a3
L1391:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1392
    xor  a4, a5, a3
L1392:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1393
    xor  a2, a5, a4
L1393:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1394
    xor  a3, a3, t0
L1394:
    sw   t3, 24(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1395
    addi t0, t2, -61
L1395:
    sw   a1, 0(s3)
    andi t5, s2, 16
    bnez t5, L1396
    addi t3, a3, 1
L1396:
    lhu   t1, 8(s0)
    lhu   t2, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1397
    xor  a1, a4, t0
L1397:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1398
    xor  a1, a3, a4
L1398:
    sw   a3, 8(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L1399
    addi t4, a4, -54
L1399:
    andi t5, s2, 2
    bnez t5, L1400
    addi a1, t0, 88
L1400:
    andi t5, s2, 128
    beqz t5, L1401
    addi a4, a3, 8
L1401:
    sw   a4, 0(s3)
    andi t5, s2, 8
    beqz t5, L1402
    addi a3, t4, 1
L1402:
    andi t5, s2, 4
    bnez t5, L1403
    addi t3, t0, 1
L1403:
    lb   a5, 13(s0)
    lb   a5, 19(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1404
    xor  t4, t4, t4
L1404:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1405
    xor  t3, t3, t1
L1405:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1406
    xor  a2, a4, a5
L1406:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1407
    xor  t4, a5, a3
L1407:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1408
    addi a4, t2, -31
L1408:
    andi t5, s2, 1
    beqz t5, L1409
    addi a4, a5, 56
L1409:
    sb   a5, 0(s3)
    andi t5, s2, 8
    beqz t5, L1410
    addi a1, a1, 1
L1410:
    andi t5, s2, 32
    beqz t5, L1411
    addi t1, t2, 1
L1411:
    lw   a5, 28(s0)
    lw   a3, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1412
    xor  a1, a5, a3
L1412:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1413
    xor  t0, t1, t0
L1413:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1414
    addi a5, a5, 69
L1414:
    andi t5, s2, 4
    bnez t5, L1415
    addi t4, t1, 32
L1415:
    sh   a5, 0(s3)
    andi t5, s2, 64
    bnez t5, L1416
    addi a3, t0, 1
L1416:
    andi t5, s2, 1024
    beqz t5, L1417
    addi t0, t4, 1
L1417:
    lw   a5, 0(s0)
    lw   t4, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1418
    xor  a2, a3, t0
L1418:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1419
    xor  t1, t4, t2
L1419:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L1420
    addi a5, a2, -57
L1420:
    andi t5, s2, 1
    bnez t5, L1421
    addi a2, a2, -71
L1421:
    sw   a4, 0(s3)
    andi t5, s2, 2
    bnez t5, L1422
    addi t1, t4, 1
L1422:
    andi t5, s2, 16
    bnez t5, L1423
    addi t4, a5, 1
L1423:
    lb   t3, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1424
    xor  t4, a5, t3
L1424:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1425
    xor  t4, t0, a1
L1425:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1426
    xor  a3, a1, t2
L1426:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L1427
    addi t1, a5, 21
L1427:
    andi t5, s2, 2
    bnez t5, L1428
    addi t1, t0, 41
L1428:
    andi t5, s2, 32
    bnez t5, L1429
    addi a5, t3, -98
L1429:
    sw   t1, 0(s3)
    andi t5, s2, 64
    bnez t5, L1430
    addi a3, t1, 1
L1430:
    lw   a1, 8(s0)
    lw   a1, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1431
    xor  t4, t1, a2
L1431:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1432
    xor  t4, t2, a2
L1432:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1433
    xor  a3, a4, t3
L1433:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L1434
    addi t3, a5, 96
L1434:
    andi t5, s2, 2
    bnez t5, L1435
    addi a2, a5, -86
L1435:
    andi t5, s2, 2
    beqz t5, L1436
    addi t1, a5, -45
L1436:
    sw   a5, 0(s3)
    andi t5, s2, 2
    bnez t5, L1437
    addi a3, t1, 1
L1437:
    andi t5, s2, 8
    beqz t5, L1438
    addi a3, a4, 1
L1438:
    lhu   a1, 8(s0)
    lw   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1439
    xor  t2, a3, t1
L1439:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1440
    xor  a1, t4, t1
L1440:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1441
    addi a2, t1, 36
L1441:
    andi t5, s2, 4
    bnez t5, L1442
    addi a1, a5, -71
L1442:
    andi t5, s2, 128
    bnez t5, L1443
    addi a3, t3, 36
L1443:
    sw   t3, 0(s3)
    andi t5, s2, 4
    bnez t5, L1444
    addi a4, t3, 1
L1444:
    lw   a5, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1445
    xor  a3, t1, t0
L1445:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1446
    xor  a3, t4, t0
L1446:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1447
    xor  t4, a5, t0
L1447:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1448
    addi a3, a5, -32
L1448:
    sw   a4, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1449
    addi a4, a4, 1
L1449:
    lw   a5, 12(s0)
    lw   t3, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1450
    xor  a2, a1, a3
L1450:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1451
    xor  t2, a2, a4
L1451:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1452
    xor  a5, t2, t3
L1452:
    sw   t0, 16(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1453
    addi t4, t1, 64
L1453:
    sw   a3, 0(s3)
    andi t5, s2, 32
    beqz t5, L1454
    addi a5, a5, 1
L1454:
    lw   t3, 16(s0)
    lhu   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1455
    xor  t0, t2, t0
L1455:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1456
    xor  a4, a4, a1
L1456:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1457
    addi a3, a5, 99
L1457:
    sw   t4, 0(s3)
    andi t5, s2, 2
    beqz t5, L1458
    addi a4, a1, 1
L1458:
    lw   a3, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1459
    xor  t4, a2, t3
L1459:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1460
    xor  a5, a1, a4
L1460:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1461
    addi t4, a1, -11
L1461:
    andi t5, s2, 8
    beqz t5, L1462
    addi t4, t1, 11
L1462:
    andi t5, s2, 8
    bnez t5, L1463
    addi a2, a3, 22
L1463:
    sw   t4, 0(s3)
    andi t5, s2, 8
    beqz t5, L1464
    addi t0, t3, 1
L1464:
    andi t5, s2, 64
    bnez t5, L1465
    addi a5, t4, 1
L1465:
    lw   t1, 16(s0)
    lb   t0, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1466
    xor  t3, t2, t4
L1466:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1467
    xor  a1, t1, t2
L1467:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1468
    xor  t2, t3, a3
L1468:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1469
    xor  t1, a3, t3
L1469:
    sw   a1, 4(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1470
    addi t3, a2, -58
L1470:
    andi t5, s2, 1
    beqz t5, L1471
    addi a5, t0, 58
L1471:
    sh   a5, 0(s3)
    andi t5, s2, 16
    bnez t5, L1472
    addi a5, a2, 1
L1472:
    lw   a3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1473
    xor  a1, t3, t4
L1473:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1474
    xor  t0, t3, a1
L1474:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1475
    addi t1, t1, -2
L1475:
    andi t5, s2, 8
    beqz t5, L1476
    addi a2, a1, 79
L1476:
    andi t5, s2, 1024
    bnez t5, L1477
    addi t0, t4, 56
L1477:
    sw   a1, 0(s3)
    andi t5, s2, 1
    bnez t5, L1478
    addi t4, t1, 1
L1478:
    andi t5, s2, 32
    beqz t5, L1479
    addi a5, a3, 1
L1479:
    lw   t3, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1480
    xor  t0, t3, t2
L1480:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1481
    xor  t2, a1, t2
L1481:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1482
    xor  a1, a5, t1
L1482:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1483
    xor  a1, t2, t2
L1483:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1484
    addi a1, t0, -19
L1484:
    andi t5, s2, 512
    beqz t5, L1485
    addi a3, t1, -23
L1485:
    sw   t1, 0(s3)
    andi t5, s2, 1
    bnez t5, L1486
    addi a2, t1, 1
L1486:
    lw   a3, 4(s0)
    lhu   a5, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1487
    xor  t3, a2, a4
L1487:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1488
    xor  t2, a4, t2
L1488:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1489
    xor  a3, a2, a3
L1489:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1490
    xor  t1, t1, a4
L1490:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1491
    addi a4, t3, -56
L1491:
    sw   t4, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1492
    addi a3, a1, 1
L1492:
    lhu   a4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1493
    xor  a3, t1, t0
L1493:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1494
    xor  a4, a5, t0
L1494:
    sw   t3, 12(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1495
    addi t2, t3, 45
L1495:
    andi t5, s2, 128
    beqz t5, L1496
    addi a2, a2, -61
L1496:
    sh   t4, 0(s3)
    andi t5, s2, 1
    beqz t5, L1497
    addi t1, a1, 1
L1497:
    andi t5, s2, 16
    beqz t5, L1498
    addi t1, a4, 1
L1498:
    lw   t1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1499
    xor  a3, t4, t4
L1499:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1500
    xor  t1, a2, a2
L1500:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1501
    xor  t2, t1, t3
L1501:
    sw   a5, 8(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1502
    addi t0, a5, 23
L1502:
    sw   a4, 0(s3)
    andi t5, s2, 128
    bnez t5, L1503
    addi t2, t2, 1
L1503:
    lw   a4, 8(s0)
    lw   a3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1504
    xor  t4, a5, a2
L1504:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1505
    xor  a3, t2, t4
L1505:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1506
    xor  a5, t3, a3
L1506:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1507
    xor  a3, t2, a1
L1507:
    sw   t3, 16(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1508
    addi t0, t1, 19
L1508:
    andi t5, s2, 1024
    bnez t5, L1509
    addi a5, a1, 40
L1509:
    sh   a3, 0(s3)
    andi t5, s2, 8
    beqz t5, L1510
    addi t1, t4, 1
L1510:
    lb   a5, 26(s0)
    lw   a4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1511
    xor  a3, t2, a5
L1511:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1512
    xor  a1, t4, a3
L1512:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1513
    xor  a1, t2, a5
L1513:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1514
    addi a1, t3, 65
L1514:
    sw   t1, 0(s3)
    andi t5, s2, 1
    beqz t5, L1515
    addi a4, t1, 1
L1515:
    andi t5, s2, 8
    bnez t5, L1516
    addi a4, t3, 1
L1516:
    lb   t0, 23(s0)
    lw   t0, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1517
    xor  t0, t0, t2
L1517:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1518
    xor  t0, a2, t2
L1518:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1519
    addi a1, a3, 51
L1519:
    sw   t3, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1520
    addi a1, t2, 1
L1520:
    lb   t3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1521
    xor  a2, a1, a4
L1521:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1522
    xor  t4, a4, a5
L1522:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1523
    addi t4, t2, -24
L1523:
    andi t5, s2, 8
    beqz t5, L1524
    addi a5, a1, 8
L1524:
    andi t5, s2, 512
    bnez t5, L1525
    addi t0, a3, 99
L1525:
    sw   t4, 0(s3)
    andi t5, s2, 256
    bnez t5, L1526
    addi t0, a1, 1
L1526:
    lb   t0, 30(s0)
    lhu   t3, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1527
    xor  a1, t3, a2
L1527:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1528
    xor  a1, t2, t4
L1528:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1529
    addi t1, t4, -64
L1529:
    andi t5, s2, 16
    beqz t5, L1530
    addi t1, a3, -78
L1530:
    andi t5, s2, 1
    bnez t5, L1531
    addi a1, a1, 2
L1531:
    sh   t2, 0(s3)
    andi t5, s2, 2
    beqz t5, L1532
    addi a5, a5, 1
L1532:
    andi t5, s2, 2
    bnez t5, L1533
    addi t0, t3, 1
L1533:
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1534
    xor  a1, a5, a5
L1534:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1535
    xor  a1, t0, t4
L1535:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1536
    xor  a2, a1, t0
L1536:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1537
    xor  t4, a3, a5
L1537:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1538
    addi t4, a4, 26
L1538:
    andi t5, s2, 1024
    bnez t5, L1539
    addi a2, t0, 45
L1539:
    andi t5, s2, 64
    bnez t5, L1540
    addi a1, t1, 21
L1540:
    sw   a4, 0(s3)
    andi t5, s2, 2
    beqz t5, L1541
    addi a1, a1, 1
L1541:
    lb   a1, 26(s0)
    lhu   t0, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1542
    xor  t3, t3, a3
L1542:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1543
    xor  t2, a5, a2
L1543:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1544
    xor  t0, a3, t3
L1544:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1545
    xor  t4, a4, t3
L1545:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1546
    addi t3, a4, 37
L1546:
    andi t5, s2, 256
    bnez t5, L1547
    addi t4, t4, -91
L1547:
    sw   a5, 0(s3)
    andi t5, s2, 512
    beqz t5, L1548
    addi t2, t1, 1
L1548:
    andi t5, s2, 32
    bnez t5, L1549
    addi t3, a4, 1
L1549:
    lhu   a2, 18(s0)
    lw   a1, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1550
    xor  t4, a3, t3
L1550:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1551
    xor  t0, a5, a4
L1551:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1552
    xor  a2, a1, a4
L1552:
    sw   a1, 20(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1553
    addi a5, t2, -100
L1553:
    andi t5, s2, 32
    bnez t5, L1554
    addi a2, t2, 95
L1554:
    andi t5, s2, 4
    bnez t5, L1555
    addi a5, t2, 64
L1555:
    sw   t1, 0(s3)
    andi t5, s2, 512
    bnez t5, L1556
    addi a4, t0, 1
L1556:
    andi t5, s2, 128
    bnez t5, L1557
    addi t0, t2, 1
L1557:
    lw   a1, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1558
    xor  a2, t1, a1
L1558:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1559
    xor  a3, t3, a3
L1559:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1560
    addi a3, t4, -95
L1560:
    andi t5, s2, 16
    beqz t5, L1561
    addi a5, t1, -13
L1561:
    andi t5, s2, 16
    beqz t5, L1562
    addi a5, t0, -93
L1562:
    sw   a2, 0(s3)
    andi t5, s2, 1
    bnez t5, L1563
    addi a4, t2, 1
L1563:
    andi t5, s2, 4
    beqz t5, L1564
    addi a2, a5, 1
L1564:
    lw   a3, 28(s0)
    lw   a1, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1565
    xor  a2, a2, a1
L1565:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1566
    xor  a3, a5, a2
L1566:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1567
    xor  t1, a2, a2
L1567:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1568
    addi t3, a1, -85
L1568:
    sw   t0, 0(s3)
    andi t5, s2, 4
    beqz t5, L1569
    addi a1, t4, 1
L1569:
    andi t5, s2, 1024
    beqz t5, L1570
    addi t4, t0, 1
L1570:
    lhu   t1, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1571
    xor  t3, a2, a5
L1571:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1572
    xor  a3, t1, t3
L1572:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1573
    addi t3, t2, 57
L1573:
    andi t5, s2, 128
    beqz t5, L1574
    addi a5, t4, -99
L1574:
    sb   a2, 0(s3)
    andi t5, s2, 256
    beqz t5, L1575
    addi t4, a4, 1
L1575:
    lhu   t0, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1576
    xor  t3, a2, t2
L1576:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1577
    xor  t2, a5, t0
L1577:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1578
    xor  a2, a2, a4
L1578:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1579
    xor  a1, a5, t2
L1579:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1580
    addi a2, t1, 36
L1580:
    andi t5, s2, 1
    bnez t5, L1581
    addi t3, t3, -93
L1581:
    andi t5, s2, 1024
    beqz t5, L1582
    addi t3, a3, 27
L1582:
    sh   t0, 0(s3)
    andi t5, s2, 8
    bnez t5, L1583
    addi a4, t0, 1
L1583:
    andi t5, s2, 256
    bnez t5, L1584
    addi a2, a2, 1
L1584:
    lw   t1, 0(s0)
    lw   t3, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1585
    xor  t1, t0, t4
L1585:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1586
    xor  a2, a2, a4
L1586:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1587
    xor  t4, t3, a1
L1587:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1588
    xor  a5, a2, a2
L1588:
    sw   a5, 24(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1589
    addi a1, a3, 77
L1589:
    andi t5, s2, 64
    bnez t5, L1590
    addi t4, t3, -68
L1590:
    andi t5, s2, 8
    bnez t5, L1591
    addi t3, a3, 50
L1591:
    sh   a3, 0(s3)
    andi t5, s2, 16
    beqz t5, L1592
    addi a5, t1, 1
L1592:
    andi t5, s2, 2
    bnez t5, L1593
    addi a4, t1, 1
L1593:
    lw   t3, 8(s0)
    lb   t1, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1594
    xor  t1, a2, t0
L1594:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1595
    xor  a1, a3, t4
L1595:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1596
    xor  t0, a3, t3
L1596:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1597
    xor  a4, a4, t2
L1597:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1598
    addi a3, t2, 36
L1598:
    sh   t0, 0(s3)
    andi t5, s2, 4
    bnez t5, L1599
    addi t4, a3, 1
L1599:
    lhu   a1, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1600
    xor  t2, t1, t1
L1600:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1601
    xor  a3, t1, t0
L1601:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1602
    xor  t3, a1, a3
L1602:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1603
    addi a3, a5, 25
L1603:
    andi t5, s2, 1
    beqz t5, L1604
    addi a5, t2, -56
L1604:
    sb   t1, 0(s3)
    andi t5, s2, 8
    beqz t5, L1605
    addi a2, t0, 1
L1605:
    lw   t0, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1606
    xor  t4, t2, t4
L1606:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1607
    xor  a3, t0, t1
L1607:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1608
    xor  a4, a3, t0
L1608:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1609
    xor  a5, t0, t3
L1609:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L1610
    addi t2, a3, 10
L1610:
    andi t5, s2, 256
    bnez t5, L1611
    addi a3, t4, 69
L1611:
    sb   a1, 0(s3)
    andi t5, s2, 2
    beqz t5, L1612
    addi a3, t1, 1
L1612:
    andi t5, s2, 512
    beqz t5, L1613
    addi t1, a3, 1
L1613:
    lw   t0, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1614
    xor  a3, a4, t1
L1614:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1615
    xor  a5, t3, t2
L1615:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1616
    xor  a4, t2, a2
L1616:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1617
    xor  t4, t2, t0
L1617:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L1618
    addi a4, a5, -77
L1618:
    sw   a3, 0(s3)
    andi t5, s2, 128
    beqz t5, L1619
    addi t3, a4, 1
L1619:
    andi t5, s2, 512
    beqz t5, L1620
    addi a4, t0, 1
L1620:
    lw   a3, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1621
    xor  a4, t2, a5
L1621:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1622
    xor  a4, t1, a5
L1622:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1623
    xor  a5, a4, a4
L1623:
    sw   a3, 20(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1624
    addi t2, a2, -45
L1624:
    andi t5, s2, 64
    beqz t5, L1625
    addi a2, a4, 42
L1625:
    sb   t0, 0(s3)
    andi t5, s2, 64
    beqz t5, L1626
    addi a5, t1, 1
L1626:
    lw   a5, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1627
    xor  t3, a4, a4
L1627:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1628
    xor  t0, a3, a1
L1628:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1629
    addi a4, a4, -87
L1629:
    sw   a5, 0(s3)
    andi t5, s2, 16
    beqz t5, L1630
    addi t4, a5, 1
L1630:
    andi t5, s2, 2
    bnez t5, L1631
    addi a1, t2, 1
L1631:
    lb   t3, 9(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1632
    xor  t4, t1, t4
L1632:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1633
    xor  t3, t3, t3
L1633:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1634
    addi t4, t3, 52
L1634:
    sw   t3, 0(s3)
    andi t5, s2, 512
    beqz t5, L1635
    addi a1, t1, 1
L1635:
    andi t5, s2, 32
    bnez t5, L1636
    addi t2, a4, 1
L1636:
    lw   t1, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1637
    xor  t2, t0, t0
L1637:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1638
    xor  t3, a5, a2
L1638:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1639
    xor  a4, t3, a3
L1639:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1640
    xor  t0, t2, a4
L1640:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1641
    addi t2, t4, -60
L1641:
    andi t5, s2, 256
    bnez t5, L1642
    addi a3, a3, -90
L1642:
    andi t5, s2, 256
    beqz t5, L1643
    addi t2, t1, 77
L1643:
    sh   t3, 0(s3)
    andi t5, s2, 128
    beqz t5, L1644
    addi a3, a4, 1
L1644:
    andi t5, s2, 512
    bnez t5, L1645
    addi a1, a5, 1
L1645:
    lhu   a5, 26(s0)
    lw   a2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1646
    xor  a4, a5, t2
L1646:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1647
    xor  a1, a1, a2
L1647:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1648
    xor  a2, a5, a1
L1648:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1649
    xor  a2, a3, a3
L1649:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1650
    addi t0, a2, -6
L1650:
    andi t5, s2, 256
    bnez t5, L1651
    addi t2, a5, -4
L1651:
    sb   a1, 0(s3)
    andi t5, s2, 1
    beqz t5, L1652
    addi a5, t2, 1
L1652:
    andi t5, s2, 512
    beqz t5, L1653
    addi t2, t2, 1
L1653:
    lhu   t4, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1654
    xor  t3, t0, t4
L1654:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1655
    xor  a1, t4, t0
L1655:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1656
    xor  a5, t4, a3
L1656:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1657
    xor  a5, t4, a2
L1657:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1658
    addi a2, t3, -47
L1658:
    sw   a4, 0(s3)
    andi t5, s2, 64
    bnez t5, L1659
    addi a3, t0, 1
L1659:
    lw   a3, 12(s0)
    lb   a1, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1660
    xor  t4, a1, t0
L1660:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1661
    xor  a5, a5, t0
L1661:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1662
    addi a3, t1, 55
L1662:
    andi t5, s2, 128
    bnez t5, L1663
    addi t0, a1, 6
L1663:
    sb   t1, 0(s3)
    andi t5, s2, 256
    beqz t5, L1664
    addi t2, a3, 1
L1664:
    lhu   a3, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1665
    xor  t1, a1, t1
L1665:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1666
    xor  a4, a3, a2
L1666:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1667
    xor  a4, t3, t0
L1667:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1668
    addi a3, a2, 17
L1668:
    sw   t1, 0(s3)
    andi t5, s2, 2
    beqz t5, L1669
    addi t0, t3, 1
L1669:
    andi t5, s2, 4
    beqz t5, L1670
    addi a4, a5, 1
L1670:
    lw   a5, 20(s0)
    lw   a1, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1671
    xor  a2, t0, a2
L1671:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1672
    xor  t3, t1, a4
L1672:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1673
    xor  a3, a3, a5
L1673:
    sw   t3, 4(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1674
    addi t1, t3, 55
L1674:
    sw   t2, 0(s3)
    andi t5, s2, 1
    bnez t5, L1675
    addi a1, t3, 1
L1675:
    andi t5, s2, 128
    beqz t5, L1676
    addi t0, t4, 1
L1676:
    lhu   t3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1677
    xor  a2, a1, t4
L1677:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1678
    xor  a3, t4, a2
L1678:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1679
    xor  a2, a5, t1
L1679:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1680
    addi a5, a5, 4
L1680:
    andi t5, s2, 1
    bnez t5, L1681
    addi a5, a4, -29
L1681:
    sh   t3, 0(s3)
    andi t5, s2, 256
    bnez t5, L1682
    addi t3, a5, 1
L1682:
    andi t5, s2, 512
    beqz t5, L1683
    addi a1, a4, 1
L1683:
    lw   t1, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1684
    xor  t2, a5, t0
L1684:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1685
    xor  t0, a3, a3
L1685:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1686
    xor  t0, a5, t2
L1686:
    sw   t3, 28(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1687
    addi t1, t2, -92
L1687:
    sw   t0, 0(s3)
    andi t5, s2, 32
    beqz t5, L1688
    addi a2, t0, 1
L1688:
    lb   t1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1689
    xor  a2, t1, t0
L1689:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1690
    xor  t4, a3, a2
L1690:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1691
    addi a2, a1, 51
L1691:
    andi t5, s2, 2
    beqz t5, L1692
    addi a4, t1, -67
L1692:
    sw   a3, 0(s3)
    andi t5, s2, 32
    bnez t5, L1693
    addi t0, a3, 1
L1693:
    lb   t4, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1694
    xor  t1, t2, t0
L1694:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1695
    xor  a2, t4, t1
L1695:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1696
    xor  a2, a4, t0
L1696:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1697
    xor  a2, t4, a1
L1697:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1698
    addi a3, t3, 46
L1698:
    sb   a4, 0(s3)
    andi t5, s2, 256
    bnez t5, L1699
    addi t0, t1, 1
L1699:
    lhu   t2, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1700
    xor  a3, t0, t0
L1700:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1701
    xor  a4, t1, a1
L1701:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1702
    xor  a2, t4, t4
L1702:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1703
    xor  a4, t2, t1
L1703:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1704
    addi t0, a4, 57
L1704:
    andi t5, s2, 4
    bnez t5, L1705
    addi t0, t4, 34
L1705:
    sw   t0, 0(s3)
    andi t5, s2, 2
    bnez t5, L1706
    addi a5, a4, 1
L1706:
    lb   a4, 29(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1707
    xor  a2, t3, a4
L1707:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1708
    xor  a4, a4, a3
L1708:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1709
    xor  t3, t2, t0
L1709:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1710
    xor  a2, a4, a1
L1710:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1711
    addi t1, a1, -51
L1711:
    andi t5, s2, 2
    beqz t5, L1712
    addi a1, t4, 44
L1712:
    sw   a5, 0(s3)
    andi t5, s2, 64
    beqz t5, L1713
    addi a3, t2, 1
L1713:
    andi t5, s2, 128
    bnez t5, L1714
    addi a1, a3, 1
L1714:
    lw   a1, 4(s0)
    lw   a5, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1715
    xor  a2, a1, t0
L1715:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1716
    xor  a2, a5, a4
L1716:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1717
    xor  a4, t1, a2
L1717:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L1718
    addi t3, a4, 11
L1718:
    andi t5, s2, 1
    bnez t5, L1719
    addi t4, a4, -19
L1719:
    sh   a2, 0(s3)
    andi t5, s2, 64
    bnez t5, L1720
    addi t3, t1, 1
L1720:
    lw   t0, 28(s0)
    lhu   t3, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1721
    xor  t1, a5, a5
L1721:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1722
    xor  t4, a3, t4
L1722:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1723
    xor  t0, t4, t0
L1723:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1724
    xor  a1, a1, a3
L1724:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1725
    addi t1, a4, -71
L1725:
    andi t5, s2, 16
    bnez t5, L1726
    addi t3, a1, 43
L1726:
    andi t5, s2, 4
    bnez t5, L1727
    addi t2, t2, -44
L1727:
    sh   a1, 0(s3)
    andi t5, s2, 1
    bnez t5, L1728
    addi t1, t4, 1
L1728:
    lb   t0, 31(s0)
    lw   t0, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1729
    xor  t2, a2, t1
L1729:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1730
    xor  t2, t0, a2
L1730:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1731
    xor  a1, a5, a3
L1731:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1732
    addi a2, a3, -59
L1732:
    sw   a1, 0(s3)
    andi t5, s2, 1
    bnez t5, L1733
    addi a4, a1, 1
L1733:
    andi t5, s2, 1024
    beqz t5, L1734
    addi t3, t0, 1
L1734:
    lw   t3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1735
    xor  a5, t4, t1
L1735:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1736
    xor  a5, t0, a3
L1736:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1737
    xor  a2, a3, a4
L1737:
    sw   t2, 12(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L1738
    addi a4, t0, 41
L1738:
    sb   t1, 0(s3)
    andi t5, s2, 1
    bnez t5, L1739
    addi t4, a5, 1
L1739:
    andi t5, s2, 32
    beqz t5, L1740
    addi a3, t4, 1
L1740:
    lw   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1741
    xor  t1, t3, t3
L1741:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1742
    xor  a4, t1, t3
L1742:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1743
    xor  a3, a5, t0
L1743:
    sw   a4, 24(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L1744
    addi t1, a4, -35
L1744:
    andi t5, s2, 2
    beqz t5, L1745
    addi a3, t4, -86
L1745:
    andi t5, s2, 128
    bnez t5, L1746
    addi t1, a2, 56
L1746:
    sw   t3, 0(s3)
    andi t5, s2, 512
    bnez t5, L1747
    addi t4, t3, 1
L1747:
    andi t5, s2, 1
    beqz t5, L1748
    addi a3, a3, 1
L1748:
    lb   t1, 20(s0)
    lw   t1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1749
    xor  t4, t4, t3
L1749:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1750
    xor  t3, a1, a5
L1750:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1751
    xor  t2, t3, t2
L1751:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L1752
    addi t1, a3, 50
L1752:
    sh   t1, 0(s3)
    andi t5, s2, 128
    bnez t5, L1753
    addi t4, a4, 1
L1753:
    lw   t1, 28(s0)
    lhu   t1, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1754
    xor  a2, t2, a4
L1754:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1755
    xor  t1, t1, t2
L1755:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1756
    xor  t2, t4, t4
L1756:
    sw   t2, 12(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1757
    addi a1, a5, -42
L1757:
    andi t5, s2, 2
    beqz t5, L1758
    addi a2, t1, 10
L1758:
    sw   t3, 0(s3)
    andi t5, s2, 8
    bnez t5, L1759
    addi a2, t2, 1
L1759:
    andi t5, s2, 1
    bnez t5, L1760
    addi t1, t1, 1
L1760:
    lhu   t3, 30(s0)
    lb   a1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1761
    xor  a1, t2, t3
L1761:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1762
    xor  a3, a4, t2
L1762:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1763
    xor  a3, a2, t3
L1763:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1764
    xor  t2, t3, a5
L1764:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1765
    addi t4, a3, -96
L1765:
    sb   t2, 0(s3)
    andi t5, s2, 2
    bnez t5, L1766
    addi a3, t4, 1
L1766:
    lb   t1, 17(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1767
    xor  t2, t2, t3
L1767:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1768
    xor  a4, t0, t1
L1768:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1769
    xor  a1, a5, a1
L1769:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1770
    xor  t0, a4, a2
L1770:
    sw   t1, 4(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1771
    addi a3, a2, -55
L1771:
    sw   a5, 0(s3)
    andi t5, s2, 512
    beqz t5, L1772
    addi t4, t3, 1
L1772:
    andi t5, s2, 512
    beqz t5, L1773
    addi t0, a5, 1
L1773:
    lw   a3, 16(s0)
    lw   t3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1774
    xor  t0, t4, a1
L1774:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1775
    xor  t1, t4, a3
L1775:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1776
    xor  t4, t1, a5
L1776:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1777
    addi a5, a4, 84
L1777:
    andi t5, s2, 128
    beqz t5, L1778
    addi a4, a2, -10
L1778:
    sh   t2, 0(s3)
    andi t5, s2, 8
    beqz t5, L1779
    addi a1, t1, 1
L1779:
    lw   a2, 0(s0)
    lw   a3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1780
    xor  a5, a4, a3
L1780:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1781
    xor  a1, a5, t0
L1781:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1782
    xor  a4, t2, a4
L1782:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1783
    addi a1, t3, -64
L1783:
    andi t5, s2, 1
    beqz t5, L1784
    addi t2, a2, -90
L1784:
    andi t5, s2, 4
    beqz t5, L1785
    addi a4, a2, 18
L1785:
    sw   t4, 0(s3)
    andi t5, s2, 64
    bnez t5, L1786
    addi a1, t1, 1
L1786:
    lb   t3, 29(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1787
    xor  a5, t2, a2
L1787:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1788
    xor  t1, t1, t1
L1788:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1789
    addi t2, a2, 44
L1789:
    andi t5, s2, 256
    beqz t5, L1790
    addi a4, t4, -57
L1790:
    andi t5, s2, 256
    beqz t5, L1791
    addi a5, a5, 35
L1791:
    sw   t4, 0(s3)
    andi t5, s2, 1
    beqz t5, L1792
    addi t3, a1, 1
L1792:
    lw   a1, 12(s0)
    lw   a4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1793
    xor  a5, a1, t2
L1793:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1794
    xor  t4, t3, a1
L1794:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1795
    xor  a4, t4, t1
L1795:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L1796
    addi t3, t4, -88
L1796:
    andi t5, s2, 128
    bnez t5, L1797
    addi a5, t0, -29
L1797:
    sh   a4, 0(s3)
    andi t5, s2, 64
    beqz t5, L1798
    addi t2, a2, 1
L1798:
    lw   a2, 16(s0)
    lw   t4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1799
    xor  a1, t4, t2
L1799:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1800
    xor  t4, a5, t1
L1800:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1801
    xor  a1, t0, a5
L1801:
    sw   t2, 8(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1802
    addi t2, a3, -27
L1802:
    andi t5, s2, 1
    beqz t5, L1803
    addi a1, t4, 15
L1803:
    sb   a4, 0(s3)
    andi t5, s2, 4
    bnez t5, L1804
    addi a4, a4, 1
L1804:
    andi t5, s2, 1024
    beqz t5, L1805
    addi t3, a5, 1
L1805:
    lhu   a2, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1806
    xor  a3, t2, a1
L1806:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1807
    xor  a1, t2, a4
L1807:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1808
    xor  t0, t3, t4
L1808:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1809
    addi t2, a3, -26
L1809:
    sw   t0, 0(s3)
    andi t5, s2, 1024
    bnez t5, L1810
    addi a2, a5, 1
L1810:
    lhu   t1, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1811
    xor  t2, a2, t1
L1811:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1812
    xor  a5, a4, a3
L1812:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1813
    xor  t4, t0, t4
L1813:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1814
    xor  t0, t4, a4
L1814:
    sw   t1, 24(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L1815
    addi a4, t0, -99
L1815:
    sh   a1, 0(s3)
    andi t5, s2, 16
    beqz t5, L1816
    addi a3, a3, 1
L1816:
    andi t5, s2, 512
    bnez t5, L1817
    addi a1, a3, 1
L1817:
    lw   a5, 20(s0)
    lhu   a1, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1818
    xor  a5, a3, a2
L1818:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1819
    xor  t3, a4, a5
L1819:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1820
    xor  a5, t3, a2
L1820:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1821
    addi a1, a2, -30
L1821:
    andi t5, s2, 32
    bnez t5, L1822
    addi a2, a1, -11
L1822:
    sw   a3, 0(s3)
    andi t5, s2, 256
    beqz t5, L1823
    addi t2, t3, 1
L1823:
    lhu   t4, 4(s0)
    lw   a3, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1824
    xor  a4, a3, a4
L1824:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1825
    xor  t0, a1, a1
L1825:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1826
    xor  a1, a4, a1
L1826:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1827
    xor  a3, t2, t0
L1827:
    sw   a1, 24(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1828
    addi t4, a2, 40
L1828:
    andi t5, s2, 128
    bnez t5, L1829
    addi t2, t4, -96
L1829:
    sw   a4, 0(s3)
    andi t5, s2, 256
    bnez t5, L1830
    addi a4, t4, 1
L1830:
    andi t5, s2, 256
    bnez t5, L1831
    addi a5, t2, 1
L1831:
    lhu   t0, 24(s0)
    lhu   t4, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1832
    xor  t4, t2, a5
L1832:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L1833
    xor  a1, a3, a1
L1833:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1834
    xor  t0, a1, a4
L1834:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1835
    xor  a3, t2, a5
L1835:
    sw   t3, 24(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L1836
    addi a1, a1, 51
L1836:
    andi t5, s2, 1024
    bnez t5, L1837
    addi a1, t2, 68
L1837:
    andi t5, s2, 1
    bnez t5, L1838
    addi t0, t0, -28
L1838:
    sw   t4, 0(s3)
    andi t5, s2, 64
    beqz t5, L1839
    addi a3, a2, 1
L1839:
    lhu   t2, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1840
    xor  t3, t4, a5
L1840:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1841
    xor  t1, a5, a1
L1841:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1842
    xor  t3, t4, t3
L1842:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L1843
    addi t3, a2, 40
L1843:
    andi t5, s2, 2
    bnez t5, L1844
    addi a4, a2, 83
L1844:
    sb   t1, 0(s3)
    andi t5, s2, 64
    beqz t5, L1845
    addi t2, t0, 1
L1845:
    andi t5, s2, 1
    beqz t5, L1846
    addi t0, a1, 1
L1846:
    lw   a5, 16(s0)
    lhu   a4, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1847
    xor  t2, t1, a1
L1847:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1848
    xor  a3, a2, a3
L1848:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1849
    addi t0, t3, -93
L1849:
    andi t5, s2, 16
    beqz t5, L1850
    addi t0, t1, 0
L1850:
    sw   t3, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1851
    addi a4, t3, 1
L1851:
    lw   a3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1852
    xor  t2, t2, a1
L1852:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1853
    xor  a2, a1, t0
L1853:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L1854
    addi a3, t0, -16
L1854:
    andi t5, s2, 1
    bnez t5, L1855
    addi t1, a4, 90
L1855:
    andi t5, s2, 1024
    bnez t5, L1856
    addi a1, t0, 88
L1856:
    sb   a3, 0(s3)
    andi t5, s2, 512
    bnez t5, L1857
    addi t0, t3, 1
L1857:
    andi t5, s2, 512
    beqz t5, L1858
    addi a1, a2, 1
L1858:
    lw   t0, 28(s0)
    lw   a1, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1859
    xor  a5, a3, t0
L1859:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1860
    xor  t3, t4, t1
L1860:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1861
    xor  a3, a1, a5
L1861:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1862
    xor  t0, a4, t3
L1862:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L1863
    addi t0, a4, -13
L1863:
    andi t5, s2, 32
    beqz t5, L1864
    addi a1, t2, -100
L1864:
    sh   a1, 0(s3)
    andi t5, s2, 16
    bnez t5, L1865
    addi a2, a4, 1
L1865:
    andi t5, s2, 64
    beqz t5, L1866
    addi a4, t4, 1
L1866:
    lw   a3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1867
    xor  a4, a2, a4
L1867:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1868
    xor  t3, t2, a3
L1868:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1869
    xor  t0, a2, a1
L1869:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1870
    xor  a5, t2, a5
L1870:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1871
    addi t1, t2, -50
L1871:
    andi t5, s2, 512
    beqz t5, L1872
    addi a5, t2, 22
L1872:
    andi t5, s2, 128
    bnez t5, L1873
    addi t4, a4, 10
L1873:
    sh   a4, 0(s3)
    andi t5, s2, 1
    beqz t5, L1874
    addi t2, a4, 1
L1874:
    andi t5, s2, 2
    bnez t5, L1875
    addi a2, a5, 1
L1875:
    lw   a2, 24(s0)
    lhu   a3, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1876
    xor  t0, a3, a2
L1876:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1877
    xor  a3, a2, a4
L1877:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1878
    xor  t2, t0, t4
L1878:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1879
    addi t2, a4, -60
L1879:
    sh   a2, 0(s3)
    andi t5, s2, 32
    bnez t5, L1880
    addi t4, a2, 1
L1880:
    lw   t2, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1881
    xor  a2, t0, a3
L1881:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1882
    xor  t4, t4, t3
L1882:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L1883
    xor  t2, t4, a2
L1883:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L1884
    addi a5, a1, 28
L1884:
    andi t5, s2, 512
    beqz t5, L1885
    addi a3, t0, 84
L1885:
    sw   t0, 0(s3)
    andi t5, s2, 512
    bnez t5, L1886
    addi t3, a2, 1
L1886:
    lw   a2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L1887
    xor  t0, a4, t0
L1887:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1888
    xor  t2, a1, a4
L1888:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1889
    addi a4, a1, 99
L1889:
    andi t5, s2, 64
    bnez t5, L1890
    addi a1, t0, 96
L1890:
    andi t5, s2, 512
    beqz t5, L1891
    addi a3, a3, -41
L1891:
    sh   t1, 0(s3)
    andi t5, s2, 512
    bnez t5, L1892
    addi a4, t0, 1
L1892:
    lw   a3, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1893
    xor  t0, t4, t2
L1893:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1894
    xor  a1, t4, a5
L1894:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1895
    xor  t1, t2, a1
L1895:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1896
    xor  t3, t2, t4
L1896:
    sw   a4, 4(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1897
    addi t3, t4, 78
L1897:
    andi t5, s2, 8
    bnez t5, L1898
    addi a2, t2, -65
L1898:
    sb   t1, 0(s3)
    andi t5, s2, 32
    bnez t5, L1899
    addi a3, a4, 1
L1899:
    lw   t1, 28(s0)
    lw   a3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1900
    xor  a4, t1, a1
L1900:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1901
    xor  t4, t1, a1
L1901:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1902
    xor  a5, t3, t2
L1902:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1903
    xor  t2, a4, a2
L1903:
    sw   a5, 28(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1904
    addi a2, a2, 23
L1904:
    andi t5, s2, 256
    bnez t5, L1905
    addi a4, t3, 36
L1905:
    andi t5, s2, 512
    beqz t5, L1906
    addi t3, a1, -47
L1906:
    sw   a2, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1907
    addi a5, t4, 1
L1907:
    andi t5, s2, 8
    beqz t5, L1908
    addi t0, a1, 1
L1908:
    lb   t1, 5(s0)
    lw   a5, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1909
    xor  t4, t1, t3
L1909:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1910
    xor  t3, t4, t0
L1910:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L1911
    xor  t1, a1, t3
L1911:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1912
    xor  t2, a3, t4
L1912:
    sw   a5, 16(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L1913
    addi t2, t3, -50
L1913:
    sw   a3, 0(s3)
    andi t5, s2, 64
    bnez t5, L1914
    addi t4, t0, 1
L1914:
    andi t5, s2, 4
    beqz t5, L1915
    addi t1, a1, 1
L1915:
    lw   t1, 0(s0)
    lb   t1, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1916
    xor  t3, a4, t4
L1916:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1917
    xor  t1, t1, t2
L1917:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L1918
    addi a4, t1, 67
L1918:
    andi t5, s2, 4
    beqz t5, L1919
    addi t3, a4, -78
L1919:
    sh   t0, 0(s3)
    andi t5, s2, 1
    beqz t5, L1920
    addi a5, t3, 1
L1920:
    lw   a5, 0(s0)
    lw   a2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L1921
    xor  t0, t0, a3
L1921:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1922
    xor  t3, a4, a1
L1922:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1923
    xor  t4, a4, t4
L1923:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1924
    xor  t4, t1, t4
L1924:
    sw   t2, 0(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L1925
    addi a4, a5, 38
L1925:
    sw   t4, 0(s3)
    andi t5, s2, 2
    beqz t5, L1926
    addi a3, a2, 1
L1926:
    lw   a3, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1927
    xor  t4, a5, t4
L1927:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1928
    xor  a4, t2, t3
L1928:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L1929
    xor  t2, t2, t3
L1929:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L1930
    addi a2, t1, 90
L1930:
    andi t5, s2, 1
    bnez t5, L1931
    addi a4, a1, -63
L1931:
    andi t5, s2, 8
    beqz t5, L1932
    addi t2, a1, 23
L1932:
    sh   t2, 0(s3)
    andi t5, s2, 8
    beqz t5, L1933
    addi t1, t2, 1
L1933:
    lw   a4, 4(s0)
    lhu   a4, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1934
    xor  t1, a5, a3
L1934:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1935
    xor  a2, t1, t0
L1935:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1936
    xor  a3, t3, a1
L1936:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1937
    xor  t2, t0, t3
L1937:
    sw   a2, 20(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L1938
    addi a2, a2, 56
L1938:
    andi t5, s2, 1
    bnez t5, L1939
    addi a2, a2, -78
L1939:
    sb   t4, 0(s3)
    andi t5, s2, 8
    beqz t5, L1940
    addi a5, a2, 1
L1940:
    andi t5, s2, 256
    bnez t5, L1941
    addi a2, t0, 1
L1941:
    lhu   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1942
    xor  a1, t1, t1
L1942:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L1943
    xor  t4, t0, a1
L1943:
    sw   t0, 8(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L1944
    addi a1, t0, -18
L1944:
    andi t5, s2, 128
    bnez t5, L1945
    addi a5, t0, 80
L1945:
    andi t5, s2, 2
    bnez t5, L1946
    addi a2, a2, 83
L1946:
    sw   a1, 0(s3)
    andi t5, s2, 64
    bnez t5, L1947
    addi t3, t4, 1
L1947:
    lhu   t0, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L1948
    xor  t3, a5, t3
L1948:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1949
    xor  a3, a3, t2
L1949:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L1950
    xor  a4, a3, a4
L1950:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L1951
    xor  t2, a1, t2
L1951:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L1952
    addi t2, t2, 33
L1952:
    sh   a1, 0(s3)
    andi t5, s2, 4
    bnez t5, L1953
    addi a4, a1, 1
L1953:
    lb   t1, 21(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1954
    xor  t2, t3, t3
L1954:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L1955
    xor  t2, t3, t0
L1955:
    sw   a5, 16(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1956
    addi t0, a1, -79
L1956:
    sw   a4, 0(s3)
    andi t5, s2, 32
    bnez t5, L1957
    addi t4, t3, 1
L1957:
    lw   t2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L1958
    xor  t0, a4, t2
L1958:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L1959
    xor  t0, t2, t4
L1959:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1960
    xor  a3, a2, a1
L1960:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L1961
    addi a2, t0, 46
L1961:
    sw   a4, 0(s3)
    andi t5, s2, 256
    bnez t5, L1962
    addi t3, a1, 1
L1962:
    andi t5, s2, 32
    bnez t5, L1963
    addi t2, a1, 1
L1963:
    lhu   t4, 10(s0)
    lb   a4, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1964
    xor  t1, a1, a4
L1964:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1965
    xor  a5, t4, a5
L1965:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1966
    xor  a3, a2, a4
L1966:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1967
    xor  t1, a1, a1
L1967:
    sw   a5, 8(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L1968
    addi a2, t4, -27
L1968:
    andi t5, s2, 256
    bnez t5, L1969
    addi a3, t1, -76
L1969:
    andi t5, s2, 4
    bnez t5, L1970
    addi a1, a2, -56
L1970:
    sw   a3, 0(s3)
    andi t5, s2, 128
    bnez t5, L1971
    addi t1, t0, 1
L1971:
    andi t5, s2, 1024
    beqz t5, L1972
    addi a5, t1, 1
L1972:
    lw   t3, 16(s0)
    lb   a2, 25(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1973
    xor  t0, a5, t0
L1973:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L1974
    xor  a4, a4, a5
L1974:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L1975
    addi a5, a2, -42
L1975:
    andi t5, s2, 1
    beqz t5, L1976
    addi a4, a1, 47
L1976:
    andi t5, s2, 128
    beqz t5, L1977
    addi t2, a3, -12
L1977:
    sw   a1, 0(s3)
    andi t5, s2, 64
    beqz t5, L1978
    addi t4, a2, 1
L1978:
    lw   t3, 0(s0)
    lb   t2, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L1979
    xor  t3, a3, a1
L1979:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1980
    xor  a3, a4, a1
L1980:
    sw   t4, 24(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L1981
    addi a5, t4, 18
L1981:
    sb   t3, 0(s3)
    andi t5, s2, 1024
    beqz t5, L1982
    addi a1, t1, 1
L1982:
    lb   a5, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L1983
    xor  t0, a2, a4
L1983:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1984
    xor  a5, a1, a2
L1984:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L1985
    xor  t4, a2, a4
L1985:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L1986
    xor  a4, a2, t3
L1986:
    sw   a1, 8(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L1987
    addi t0, a2, 12
L1987:
    andi t5, s2, 512
    beqz t5, L1988
    addi a5, t3, 77
L1988:
    andi t5, s2, 128
    bnez t5, L1989
    addi t4, t1, 66
L1989:
    sb   t3, 0(s3)
    andi t5, s2, 2
    beqz t5, L1990
    addi a2, a5, 1
L1990:
    lhu   t2, 18(s0)
    lhu   t0, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L1991
    xor  t3, a2, a5
L1991:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L1992
    xor  t2, a1, t2
L1992:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L1993
    addi t1, t0, 20
L1993:
    andi t5, s2, 1024
    beqz t5, L1994
    addi t4, a4, 69
L1994:
    sh   t4, 0(s3)
    andi t5, s2, 8
    bnez t5, L1995
    addi t4, t0, 1
L1995:
    lb   a1, 28(s0)
    lw   t0, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L1996
    xor  a4, t3, t1
L1996:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L1997
    xor  a4, t1, t2
L1997:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L1998
    addi a3, t3, -19
L1998:
    andi t5, s2, 256
    beqz t5, L1999
    addi t2, t3, -19
L1999:
    andi t5, s2, 64
    beqz t5, L2000
    addi a2, t0, 27
L2000:
    sh   t2, 0(s3)
    andi t5, s2, 1
    bnez t5, L2001
    addi a2, a3, 1
L2001:
    lw   t0, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2002
    xor  t3, a5, a2
L2002:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2003
    xor  t0, a3, a1
L2003:
    sw   t0, 16(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L2004
    addi a4, a2, 96
L2004:
    sh   a1, 0(s3)
    andi t5, s2, 1024
    beqz t5, L2005
    addi a5, t1, 1
L2005:
    andi t5, s2, 4
    beqz t5, L2006
    addi t2, a3, 1
L2006:
    lb   t2, 23(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2007
    xor  a4, a2, a4
L2007:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2008
    xor  a2, a5, t1
L2008:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2009
    xor  a1, t3, a2
L2009:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2010
    xor  a3, a2, a2
L2010:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L2011
    addi t3, a3, 79
L2011:
    andi t5, s2, 4
    beqz t5, L2012
    addi a4, a5, -25
L2012:
    sh   t1, 0(s3)
    andi t5, s2, 4
    beqz t5, L2013
    addi a5, a2, 1
L2013:
    lw   t1, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2014
    xor  t0, a4, t0
L2014:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2015
    xor  a5, a4, t4
L2015:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L2016
    addi t1, a2, -33
L2016:
    andi t5, s2, 1
    bnez t5, L2017
    addi t3, t1, -95
L2017:
    sw   t2, 0(s3)
    andi t5, s2, 256
    bnez t5, L2018
    addi t1, a1, 1
L2018:
    andi t5, s2, 512
    beqz t5, L2019
    addi t4, a5, 1
L2019:
    lw   t2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2020
    xor  a3, a3, a2
L2020:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2021
    xor  a3, t0, t2
L2021:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L2022
    addi t3, t1, 13
L2022:
    andi t5, s2, 2
    beqz t5, L2023
    addi a5, t0, -93
L2023:
    sh   a2, 0(s3)
    andi t5, s2, 1024
    bnez t5, L2024
    addi t4, a4, 1
L2024:
    lb   t2, 29(s0)
    lw   t2, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2025
    xor  a2, t2, t4
L2025:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2026
    xor  t3, a3, t2
L2026:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2027
    xor  t2, a4, a4
L2027:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2028
    xor  a3, t1, t2
L2028:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L2029
    addi t0, a4, -39
L2029:
    andi t5, s2, 16
    beqz t5, L2030
    addi t4, t3, 92
L2030:
    sb   a1, 0(s3)
    andi t5, s2, 16
    bnez t5, L2031
    addi a3, a3, 1
L2031:
    andi t5, s2, 1
    beqz t5, L2032
    addi t0, t0, 1
L2032:
    lw   t2, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2033
    xor  t0, t4, t4
L2033:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L2034
    xor  t2, t4, t0
L2034:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2035
    xor  a4, t0, t0
L2035:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2036
    xor  a2, t2, t3
L2036:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L2037
    addi a5, a3, 81
L2037:
    andi t5, s2, 512
    bnez t5, L2038
    addi t4, a5, 82
L2038:
    sb   a2, 0(s3)
    andi t5, s2, 128
    beqz t5, L2039
    addi a1, t2, 1
L2039:
    andi t5, s2, 512
    beqz t5, L2040
    addi a5, a2, 1
L2040:
    lb   a1, 26(s0)
    lw   t2, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2041
    xor  a2, a1, a3
L2041:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2042
    xor  t4, t1, a1
L2042:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2043
    xor  t3, a5, a5
L2043:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L2044
    addi t0, t1, 87
L2044:
    andi t5, s2, 128
    beqz t5, L2045
    addi t3, a1, -18
L2045:
    sw   a5, 0(s3)
    andi t5, s2, 64
    beqz t5, L2046
    addi t4, a3, 1
L2046:
    andi t5, s2, 1
    beqz t5, L2047
    addi a4, t1, 1
L2047:
    lw   a1, 4(s0)
    lb   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2048
    xor  t3, t1, t2
L2048:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2049
    xor  t2, a2, t4
L2049:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2050
    addi t1, a3, -52
L2050:
    andi t5, s2, 1
    beqz t5, L2051
    addi t4, a1, 56
L2051:
    andi t5, s2, 8
    bnez t5, L2052
    addi t4, t3, 7
L2052:
    sh   a1, 0(s3)
    andi t5, s2, 4
    beqz t5, L2053
    addi a4, t4, 1
L2053:
    lw   a2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2054
    xor  t2, a2, a4
L2054:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2055
    xor  a3, t0, t4
L2055:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2056
    xor  a3, t2, t2
L2056:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2057
    xor  t1, t1, a2
L2057:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L2058
    addi a1, t3, -26
L2058:
    andi t5, s2, 512
    bnez t5, L2059
    addi t4, t4, 97
L2059:
    sb   a2, 0(s3)
    andi t5, s2, 8
    bnez t5, L2060
    addi t0, t3, 1
L2060:
    lb   t3, 15(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2061
    xor  t1, t4, a4
L2061:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2062
    xor  a5, t4, a3
L2062:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L2063
    xor  a2, a4, t3
L2063:
    sw   a4, 24(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L2064
    addi a1, t2, -53
L2064:
    andi t5, s2, 32
    beqz t5, L2065
    addi t3, t4, -27
L2065:
    andi t5, s2, 4
    beqz t5, L2066
    addi a5, t4, -86
L2066:
    sb   a1, 0(s3)
    andi t5, s2, 2
    beqz t5, L2067
    addi a2, a4, 1
L2067:
    lw   t3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2068
    xor  t1, t0, t3
L2068:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2069
    xor  a2, a5, t2
L2069:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2070
    xor  t3, t1, a2
L2070:
    sw   a2, 20(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L2071
    addi t4, t0, 88
L2071:
    andi t5, s2, 512
    bnez t5, L2072
    addi t3, t4, -39
L2072:
    sw   t1, 0(s3)
    andi t5, s2, 1
    bnez t5, L2073
    addi t0, t4, 1
L2073:
    andi t5, s2, 4
    beqz t5, L2074
    addi t4, t2, 1
L2074:
    lw   a1, 4(s0)
    lw   a2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2075
    xor  t3, t4, a2
L2075:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2076
    xor  t0, t3, a1
L2076:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2077
    xor  t2, t2, t0
L2077:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L2078
    addi a2, a5, -33
L2078:
    andi t5, s2, 1024
    beqz t5, L2079
    addi a4, t3, 16
L2079:
    andi t5, s2, 64
    beqz t5, L2080
    addi a3, t3, -48
L2080:
    sh   t1, 0(s3)
    andi t5, s2, 1
    bnez t5, L2081
    addi t3, t1, 1
L2081:
    andi t5, s2, 256
    bnez t5, L2082
    addi a5, t1, 1
L2082:
    lhu   t4, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2083
    xor  t4, a4, a5
L2083:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2084
    xor  a1, a3, t0
L2084:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2085
    xor  a4, t2, a1
L2085:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L2086
    addi t4, a1, 18
L2086:
    andi t5, s2, 64
    bnez t5, L2087
    addi t1, a1, 41
L2087:
    sh   a5, 0(s3)
    andi t5, s2, 1
    beqz t5, L2088
    addi t0, t2, 1
L2088:
    lhu   t0, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2089
    xor  t4, a4, a4
L2089:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2090
    xor  a3, a4, t2
L2090:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2091
    xor  t0, t3, t2
L2091:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L2092
    addi a4, a4, 42
L2092:
    sw   t2, 0(s3)
    andi t5, s2, 2
    bnez t5, L2093
    addi t1, a2, 1
L2093:
    andi t5, s2, 512
    bnez t5, L2094
    addi t3, t0, 1
L2094:
    lw   t2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2095
    xor  a2, t0, a3
L2095:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2096
    xor  t3, t4, t1
L2096:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2097
    xor  t1, a5, a5
L2097:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2098
    xor  a1, t4, t4
L2098:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L2099
    addi a2, t4, 4
L2099:
    sw   a2, 0(s3)
    andi t5, s2, 4
    bnez t5, L2100
    addi a1, a2, 1
L2100:
    lb   t2, 8(s0)
    lhu   a5, 18(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2101
    xor  a5, t2, t2
L2101:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2102
    xor  a2, t0, a5
L2102:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2103
    xor  a2, a1, a2
L2103:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2104
    xor  a4, t1, a1
L2104:
    sw   a4, 0(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2105
    addi t3, t4, -88
L2105:
    sb   t1, 0(s3)
    andi t5, s2, 512
    beqz t5, L2106
    addi t0, a1, 1
L2106:
    lb   a2, 23(s0)
    lw   t2, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2107
    xor  a5, t4, t1
L2107:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2108
    xor  a3, t0, a4
L2108:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2109
    xor  a5, a1, t1
L2109:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L2110
    addi t3, t2, -37
L2110:
    andi t5, s2, 32
    bnez t5, L2111
    addi a4, t2, -71
L2111:
    andi t5, s2, 8
    beqz t5, L2112
    addi t1, a1, -88
L2112:
    sw   t2, 0(s3)
    andi t5, s2, 32
    beqz t5, L2113
    addi a1, t4, 1
L2113:
    andi t5, s2, 256
    bnez t5, L2114
    addi a4, t1, 1
L2114:
    lw   a4, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2115
    xor  a4, a5, a3
L2115:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2116
    xor  t4, t1, a2
L2116:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2117
    xor  a1, a1, t4
L2117:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L2118
    addi t2, t3, -73
L2118:
    sh   t1, 0(s3)
    andi t5, s2, 8
    bnez t5, L2119
    addi a3, t2, 1
L2119:
    andi t5, s2, 16
    bnez t5, L2120
    addi a3, t1, 1
L2120:
    lw   a3, 20(s0)
    lb   t2, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2121
    xor  a4, a4, t4
L2121:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2122
    xor  t0, a3, a5
L2122:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2123
    xor  a5, t1, a5
L2123:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2124
    addi a4, a4, -96
L2124:
    sw   t4, 0(s3)
    andi t5, s2, 32
    bnez t5, L2125
    addi a3, t3, 1
L2125:
    lw   t2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2126
    xor  a1, t2, a2
L2126:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2127
    xor  t2, t2, t4
L2127:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2128
    xor  a5, t2, t1
L2128:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2129
    xor  a2, a3, t4
L2129:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L2130
    addi t0, a5, 36
L2130:
    andi t5, s2, 8
    beqz t5, L2131
    addi a3, t3, -39
L2131:
    sw   a5, 0(s3)
    andi t5, s2, 256
    bnez t5, L2132
    addi t4, a4, 1
L2132:
    andi t5, s2, 8
    beqz t5, L2133
    addi t0, a2, 1
L2133:
    lhu   t2, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2134
    xor  t2, t2, t0
L2134:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2135
    xor  a2, t1, a2
L2135:
    sw   t2, 8(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L2136
    addi t0, t4, 93
L2136:
    andi t5, s2, 512
    beqz t5, L2137
    addi a5, t0, 16
L2137:
    andi t5, s2, 512
    beqz t5, L2138
    addi t1, t2, -73
L2138:
    sw   a2, 0(s3)
    andi t5, s2, 128
    beqz t5, L2139
    addi t4, t2, 1
L2139:
    lw   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2140
    xor  a3, a4, t4
L2140:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2141
    xor  a3, a4, a2
L2141:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2142
    xor  a3, a5, t3
L2142:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2143
    xor  t4, t3, a2
L2143:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L2144
    addi t4, t2, 58
L2144:
    sh   t3, 0(s3)
    andi t5, s2, 32
    beqz t5, L2145
    addi t1, a2, 1
L2145:
    andi t5, s2, 2
    bnez t5, L2146
    addi a1, t2, 1
L2146:
    lw   t0, 8(s0)
    lb   a1, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L2147
    xor  a2, t2, a3
L2147:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2148
    xor  a4, a5, t2
L2148:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L2149
    addi a4, a4, 7
L2149:
    andi t5, s2, 32
    bnez t5, L2150
    addi a3, a5, 68
L2150:
    sh   a2, 0(s3)
    andi t5, s2, 1
    beqz t5, L2151
    addi a5, t1, 1
L2151:
    lw   t0, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2152
    xor  t4, a4, t3
L2152:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2153
    xor  t3, a4, t2
L2153:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2154
    xor  t3, a3, a2
L2154:
    sw   t2, 28(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L2155
    addi a5, a3, 21
L2155:
    andi t5, s2, 16
    bnez t5, L2156
    addi a5, a1, -59
L2156:
    andi t5, s2, 4
    bnez t5, L2157
    addi a2, t0, 71
L2157:
    sw   t0, 0(s3)
    andi t5, s2, 16
    bnez t5, L2158
    addi a4, a1, 1
L2158:
    andi t5, s2, 2
    bnez t5, L2159
    addi a3, a3, 1
L2159:
    lw   a2, 4(s0)
    lhu   t4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2160
    xor  a3, a5, a2
L2160:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2161
    xor  a3, a3, t2
L2161:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L2162
    addi t2, a4, 14
L2162:
    sw   t0, 0(s3)
    andi t5, s2, 4
    beqz t5, L2163
    addi a1, a5, 1
L2163:
    andi t5, s2, 1024
    beqz t5, L2164
    addi t3, t4, 1
L2164:
    lhu   a2, 4(s0)
    lhu   a2, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2165
    xor  t4, a2, t2
L2165:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2166
    xor  a2, a3, t0
L2166:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2167
    xor  a3, a1, t3
L2167:
    sw   t0, 12(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L2168
    addi a3, a3, -52
L2168:
    sw   a3, 0(s3)
    andi t5, s2, 256
    bnez t5, L2169
    addi t2, t2, 1
L2169:
    lb   a5, 23(s0)
    lw   t4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2170
    xor  t3, t0, a1
L2170:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2171
    xor  t0, t2, a2
L2171:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2172
    xor  t4, t4, t4
L2172:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2173
    xor  a2, a3, t2
L2173:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    beqz t5, L2174
    addi a4, t0, 61
L2174:
    andi t5, s2, 128
    beqz t5, L2175
    addi a1, t0, -61
L2175:
    andi t5, s2, 1024
    bnez t5, L2176
    addi t3, t4, 47
L2176:
    sw   t0, 0(s3)
    andi t5, s2, 128
    bnez t5, L2177
    addi a1, t0, 1
L2177:
    lhu   a2, 14(s0)
    lb   a1, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2178
    xor  t0, t4, t2
L2178:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2179
    xor  t1, a4, t0
L2179:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2180
    xor  a3, a1, a2
L2180:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2181
    xor  t3, t0, a3
L2181:
    sw   a1, 24(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L2182
    addi t3, a2, 85
L2182:
    andi t5, s2, 256
    beqz t5, L2183
    addi t4, t4, 71
L2183:
    sw   t4, 0(s3)
    andi t5, s2, 4
    bnez t5, L2184
    addi a2, t3, 1
L2184:
    lw   t1, 4(s0)
    lw   a5, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2185
    xor  t3, t4, a5
L2185:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2186
    xor  a4, a1, t3
L2186:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2187
    xor  t4, a2, a5
L2187:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2188
    xor  a5, a4, a5
L2188:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2189
    addi t3, a4, 28
L2189:
    andi t5, s2, 512
    beqz t5, L2190
    addi t4, a5, 65
L2190:
    andi t5, s2, 512
    bnez t5, L2191
    addi t1, a5, -70
L2191:
    sh   a3, 0(s3)
    andi t5, s2, 2
    bnez t5, L2192
    addi a1, t4, 1
L2192:
    lw   t2, 0(s0)
    lhu   t4, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2193
    xor  a1, a4, a3
L2193:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2194
    xor  a1, t4, t3
L2194:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L2195
    addi t2, t3, 1
L2195:
    andi t5, s2, 16
    beqz t5, L2196
    addi t1, t3, 49
L2196:
    andi t5, s2, 256
    bnez t5, L2197
    addi t3, t1, 88
L2197:
    sw   a5, 0(s3)
    andi t5, s2, 2
    beqz t5, L2198
    addi a1, t0, 1
L2198:
    andi t5, s2, 128
    bnez t5, L2199
    addi t2, a3, 1
L2199:
    lhu   a3, 14(s0)
    lhu   a3, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2200
    xor  t1, a3, t4
L2200:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2201
    xor  t1, t3, t0
L2201:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2202
    xor  t1, a2, t1
L2202:
    sw   a4, 28(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2203
    addi t4, a1, 51
L2203:
    sw   t2, 0(s3)
    andi t5, s2, 512
    beqz t5, L2204
    addi a5, a5, 1
L2204:
    andi t5, s2, 512
    bnez t5, L2205
    addi t2, t0, 1
L2205:
    lw   a2, 16(s0)
    lhu   a1, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2206
    xor  t0, t1, a3
L2206:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2207
    xor  a1, t0, a4
L2207:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L2208
    addi a1, t0, -5
L2208:
    sw   t4, 0(s3)
    andi t5, s2, 8
    bnez t5, L2209
    addi a4, t0, 1
L2209:
    lhu   t3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2210
    xor  a4, t0, a4
L2210:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2211
    xor  a2, t1, t3
L2211:
    sw   a4, 28(s0)
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L2212
    addi t3, t0, 86
L2212:
    sw   t2, 0(s3)
    andi t5, s2, 16
    beqz t5, L2213
    addi a2, t3, 1
L2213:
    lb   a4, 25(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2214
    xor  a1, t3, a3
L2214:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2215
    xor  t1, t1, t2
L2215:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L2216
    addi a5, t0, 57
L2216:
    sw   a1, 0(s3)
    andi t5, s2, 128
    beqz t5, L2217
    addi a2, t2, 1
L2217:
    andi t5, s2, 2
    bnez t5, L2218
    addi t0, a4, 1
L2218:
    lhu   a4, 2(s0)
    lw   a1, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2219
    xor  t4, a2, a1
L2219:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2220
    xor  t1, a4, t4
L2220:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2221
    xor  t2, t0, t0
L2221:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2222
    xor  a5, t1, a2
L2222:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L2223
    addi a4, t4, -87
L2223:
    sb   a5, 0(s3)
    andi t5, s2, 4
    beqz t5, L2224
    addi t2, a5, 1
L2224:
    andi t5, s2, 2
    beqz t5, L2225
    addi a5, t4, 1
L2225:
    lw   t1, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2226
    xor  a3, t4, t3
L2226:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2227
    xor  t4, t3, t0
L2227:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2228
    xor  t0, t4, a3
L2228:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L2229
    addi a5, a5, -67
L2229:
    andi t5, s2, 64
    bnez t5, L2230
    addi a2, t2, 59
L2230:
    sb   a5, 0(s3)
    andi t5, s2, 4
    bnez t5, L2231
    addi t2, a4, 1
L2231:
    lb   t4, 23(s0)
    lw   t2, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2232
    xor  t3, t3, a1
L2232:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2233
    xor  t2, a3, a2
L2233:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L2234
    addi a5, a5, 84
L2234:
    sw   a1, 0(s3)
    andi t5, s2, 1
    beqz t5, L2235
    addi a3, t0, 1
L2235:
    lb   a2, 18(s0)
    lw   t3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2236
    xor  a3, a4, a5
L2236:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2237
    xor  t4, a3, t1
L2237:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2238
    xor  a1, a4, a5
L2238:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2239
    xor  t4, a2, t4
L2239:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L2240
    addi a5, a1, -79
L2240:
    andi t5, s2, 64
    beqz t5, L2241
    addi t4, t3, 92
L2241:
    andi t5, s2, 1024
    bnez t5, L2242
    addi t0, a2, -98
L2242:
    sw   a1, 0(s3)
    andi t5, s2, 8
    beqz t5, L2243
    addi a1, t0, 1
L2243:
    andi t5, s2, 2
    beqz t5, L2244
    addi a5, a1, 1
L2244:
    lw   a2, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2245
    xor  a5, t1, a2
L2245:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2246
    xor  t3, t0, t1
L2246:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2247
    xor  t0, t1, a4
L2247:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    bnez t5, L2248
    addi t0, a2, 8
L2248:
    andi t5, s2, 1024
    bnez t5, L2249
    addi t2, t1, -7
L2249:
    sb   a1, 0(s3)
    andi t5, s2, 256
    bnez t5, L2250
    addi t1, t4, 1
L2250:
    lw   a3, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2251
    xor  a5, a5, a5
L2251:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2252
    xor  a3, t2, a3
L2252:
    sw   t3, 4(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L2253
    addi t0, t4, -71
L2253:
    andi t5, s2, 128
    bnez t5, L2254
    addi t2, a5, -87
L2254:
    andi t5, s2, 32
    bnez t5, L2255
    addi t3, a5, -35
L2255:
    sw   t1, 0(s3)
    andi t5, s2, 4
    beqz t5, L2256
    addi a5, a5, 1
L2256:
    andi t5, s2, 16
    bnez t5, L2257
    addi t2, t2, 1
L2257:
    lb   t3, 26(s0)
    lw   t4, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2258
    xor  t2, t4, a5
L2258:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2259
    xor  a1, t2, a2
L2259:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L2260
    addi a2, t4, 97
L2260:
    andi t5, s2, 256
    beqz t5, L2261
    addi t1, t0, 49
L2261:
    andi t5, s2, 1
    beqz t5, L2262
    addi t2, t4, -29
L2262:
    sw   t4, 0(s3)
    andi t5, s2, 2
    beqz t5, L2263
    addi a2, a2, 1
L2263:
    andi t5, s2, 1
    bnez t5, L2264
    addi a1, t3, 1
L2264:
    lb   t1, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2265
    xor  t2, a3, t0
L2265:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2266
    xor  a3, t3, a4
L2266:
    sw   a1, 8(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L2267
    addi a1, a3, 54
L2267:
    andi t5, s2, 64
    beqz t5, L2268
    addi a1, a1, -95
L2268:
    sb   a4, 0(s3)
    andi t5, s2, 8
    bnez t5, L2269
    addi a5, a4, 1
L2269:
    lw   a5, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2270
    xor  a5, a5, t3
L2270:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2271
    xor  a1, a2, t3
L2271:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L2272
    addi t3, a4, -84
L2272:
    sw   a2, 0(s3)
    andi t5, s2, 4
    bnez t5, L2273
    addi a3, a3, 1
L2273:
    lw   t1, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2274
    xor  t3, a4, a3
L2274:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2275
    xor  t3, a1, t4
L2275:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2276
    xor  t0, a2, t2
L2276:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    beqz t5, L2277
    addi a2, a1, 26
L2277:
    sb   a2, 0(s3)
    andi t5, s2, 32
    bnez t5, L2278
    addi t3, t1, 1
L2278:
    andi t5, s2, 32
    beqz t5, L2279
    addi t4, t4, 1
L2279:
    lb   a3, 6(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2280
    xor  a5, t2, a3
L2280:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2281
    xor  t2, a1, t1
L2281:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L2282
    xor  a4, t3, t0
L2282:
    sw   t3, 16(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L2283
    addi a5, a4, 62
L2283:
    andi t5, s2, 2
    bnez t5, L2284
    addi a4, t2, 62
L2284:
    sw   a5, 0(s3)
    andi t5, s2, 1024
    bnez t5, L2285
    addi a5, t1, 1
L2285:
    lw   t0, 16(s0)
    lb   a1, 15(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2286
    xor  t4, a5, t4
L2286:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2287
    xor  t2, t0, t2
L2287:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L2288
    addi t2, t1, -39
L2288:
    andi t5, s2, 64
    bnez t5, L2289
    addi t0, t0, -8
L2289:
    andi t5, s2, 128
    beqz t5, L2290
    addi t3, t1, -77
L2290:
    sw   a3, 0(s3)
    andi t5, s2, 128
    beqz t5, L2291
    addi t2, a3, 1
L2291:
    andi t5, s2, 256
    beqz t5, L2292
    addi a3, a5, 1
L2292:
    lw   t2, 24(s0)
    lhu   a5, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2293
    xor  t3, a1, a5
L2293:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2294
    xor  a5, a2, a2
L2294:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2295
    xor  a4, t2, a2
L2295:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L2296
    addi a3, a4, -28
L2296:
    andi t5, s2, 1
    bnez t5, L2297
    addi a2, t1, -37
L2297:
    andi t5, s2, 128
    bnez t5, L2298
    addi t3, t1, 39
L2298:
    sw   t2, 0(s3)
    andi t5, s2, 1024
    beqz t5, L2299
    addi a4, t4, 1
L2299:
    andi t5, s2, 2
    beqz t5, L2300
    addi a1, a5, 1
L2300:
    lb   t1, 29(s0)
    lw   a2, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2301
    xor  a2, a5, a1
L2301:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2302
    xor  t1, t2, a3
L2302:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2303
    xor  a2, a4, t2
L2303:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2304
    xor  a1, a3, t1
L2304:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L2305
    addi a3, a4, 66
L2305:
    sw   a4, 0(s3)
    andi t5, s2, 512
    bnez t5, L2306
    addi a1, t3, 1
L2306:
    lw   t0, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2307
    xor  t3, t0, a2
L2307:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2308
    xor  t4, a3, a2
L2308:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2309
    xor  t2, a3, a2
L2309:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L2310
    xor  a4, t0, a1
L2310:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    beqz t5, L2311
    addi t1, a2, -28
L2311:
    sh   a1, 0(s3)
    andi t5, s2, 4
    bnez t5, L2312
    addi t3, a5, 1
L2312:
    lw   t3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2313
    xor  a4, a1, t3
L2313:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2314
    xor  t3, a3, a3
L2314:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2315
    xor  t1, a5, a5
L2315:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2316
    xor  t1, a5, a5
L2316:
    sw   t3, 12(s0)
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L2317
    addi a4, t0, -65
L2317:
    andi t5, s2, 64
    beqz t5, L2318
    addi t3, t3, -83
L2318:
    andi t5, s2, 64
    beqz t5, L2319
    addi t1, a1, -81
L2319:
    sw   t2, 0(s3)
    andi t5, s2, 1
    beqz t5, L2320
    addi t1, a4, 1
L2320:
    andi t5, s2, 8
    bnez t5, L2321
    addi a3, t2, 1
L2321:
    lb   t0, 0(s0)
    lb   a4, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2322
    xor  t1, a4, t3
L2322:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2323
    xor  a2, t1, a3
L2323:
    sw   t3, 12(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L2324
    addi a5, a2, 89
L2324:
    andi t5, s2, 256
    bnez t5, L2325
    addi a4, a4, 55
L2325:
    sw   t4, 0(s3)
    andi t5, s2, 16
    beqz t5, L2326
    addi t4, a3, 1
L2326:
    lw   a1, 16(s0)
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2327
    xor  a4, t1, a1
L2327:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2328
    xor  t4, a4, t4
L2328:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L2329
    addi a1, t2, 21
L2329:
    andi t5, s2, 128
    beqz t5, L2330
    addi t4, t1, -70
L2330:
    sw   a4, 0(s3)
    andi t5, s2, 1024
    beqz t5, L2331
    addi a1, a1, 1
L2331:
    lb   a1, 19(s0)
    lhu   t0, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L2332
    xor  a4, a3, a1
L2332:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2333
    xor  t3, t0, t2
L2333:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2334
    addi t3, t2, 46
L2334:
    sb   t1, 0(s3)
    andi t5, s2, 2
    bnez t5, L2335
    addi a3, a2, 1
L2335:
    andi t5, s2, 16
    bnez t5, L2336
    addi a1, t1, 1
L2336:
    lb   a5, 19(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2337
    xor  t2, t3, a2
L2337:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2338
    xor  t1, t0, t4
L2338:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L2339
    addi t1, a5, 33
L2339:
    sw   t2, 0(s3)
    andi t5, s2, 8
    beqz t5, L2340
    addi t1, t0, 1
L2340:
    lhu   a5, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L2341
    xor  t4, t4, a5
L2341:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2342
    xor  a1, a3, t4
L2342:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2343
    addi t2, a4, 11
L2343:
    sw   a2, 0(s3)
    andi t5, s2, 512
    bnez t5, L2344
    addi a2, a3, 1
L2344:
    andi t5, s2, 1
    beqz t5, L2345
    addi a5, t4, 1
L2345:
    lhu   a4, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2346
    xor  t3, a5, t3
L2346:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2347
    xor  t3, t4, a3
L2347:
    sw   t4, 4(s0)
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L2348
    addi a1, t4, 50
L2348:
    andi t5, s2, 64
    beqz t5, L2349
    addi a2, t0, -93
L2349:
    sh   a4, 0(s3)
    andi t5, s2, 1
    beqz t5, L2350
    addi t4, t4, 1
L2350:
    lw   t0, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2351
    xor  a2, a3, t1
L2351:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2352
    xor  t4, a4, a2
L2352:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2353
    xor  a3, t0, a2
L2353:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2354
    addi t2, t3, 51
L2354:
    andi t5, s2, 256
    bnez t5, L2355
    addi t0, a2, -30
L2355:
    andi t5, s2, 1
    beqz t5, L2356
    addi t2, t4, 33
L2356:
    sh   t4, 0(s3)
    andi t5, s2, 64
    beqz t5, L2357
    addi t1, a3, 1
L2357:
    lw   a2, 20(s0)
    lhu   t2, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2358
    xor  a5, t4, t4
L2358:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2359
    xor  t1, a4, t2
L2359:
    sw   a1, 12(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L2360
    addi t3, a4, 47
L2360:
    andi t5, s2, 4
    beqz t5, L2361
    addi a5, t2, 74
L2361:
    sh   t2, 0(s3)
    andi t5, s2, 64
    beqz t5, L2362
    addi a1, a2, 1
L2362:
    lb   t1, 19(s0)
    lhu   t0, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2363
    xor  a5, a3, a5
L2363:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2364
    xor  a2, t1, t3
L2364:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2365
    xor  a2, a5, a5
L2365:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L2366
    addi t4, t2, 42
L2366:
    andi t5, s2, 1
    bnez t5, L2367
    addi a5, t0, -60
L2367:
    andi t5, s2, 1
    bnez t5, L2368
    addi a1, t1, -10
L2368:
    sb   t4, 0(s3)
    andi t5, s2, 512
    beqz t5, L2369
    addi t0, t0, 1
L2369:
    andi t5, s2, 512
    bnez t5, L2370
    addi a4, a2, 1
L2370:
    lb   t4, 13(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2371
    xor  a3, t3, a5
L2371:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2372
    xor  a4, a2, t2
L2372:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2373
    xor  t3, a3, a1
L2373:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L2374
    addi t3, a4, 13
L2374:
    andi t5, s2, 1
    bnez t5, L2375
    addi t4, t4, 27
L2375:
    sh   t1, 0(s3)
    andi t5, s2, 4
    bnez t5, L2376
    addi a3, a1, 1
L2376:
    lw   a3, 16(s0)
    lw   a5, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2377
    xor  t4, t4, a3
L2377:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2378
    xor  a5, a4, a2
L2378:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2379
    xor  a5, a3, a4
L2379:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    bnez t5, L2380
    addi t3, a4, -78
L2380:
    sb   a3, 0(s3)
    andi t5, s2, 128
    beqz t5, L2381
    addi a5, a4, 1
L2381:
    andi t5, s2, 4
    beqz t5, L2382
    addi a4, t4, 1
L2382:
    lhu   t0, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2383
    xor  t1, a2, a1
L2383:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2384
    xor  a1, t0, a3
L2384:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2385
    xor  t3, t0, a4
L2385:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L2386
    addi a3, t1, -22
L2386:
    andi t5, s2, 256
    beqz t5, L2387
    addi t1, t1, -85
L2387:
    andi t5, s2, 8
    bnez t5, L2388
    addi t0, a4, -94
L2388:
    sw   a1, 0(s3)
    andi t5, s2, 8
    beqz t5, L2389
    addi t2, t4, 1
L2389:
    andi t5, s2, 128
    bnez t5, L2390
    addi t0, a1, 1
L2390:
    lw   a2, 20(s0)
    lw   a1, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2391
    xor  t0, a4, a3
L2391:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2392
    xor  t2, a3, t1
L2392:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2393
    xor  t0, t1, a4
L2393:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2394
    xor  a2, a4, t3
L2394:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L2395
    addi t4, t2, -71
L2395:
    sb   a1, 0(s3)
    andi t5, s2, 16
    bnez t5, L2396
    addi a3, t0, 1
L2396:
    lw   a3, 0(s0)
    lb   t2, 3(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2397
    xor  t0, a2, a2
L2397:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2398
    xor  t2, a5, a3
L2398:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2399
    xor  a1, t2, t1
L2399:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2400
    xor  a4, t4, a2
L2400:
    sw   t0, 20(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2401
    addi t0, a5, -41
L2401:
    andi t5, s2, 32
    beqz t5, L2402
    addi t0, t2, -41
L2402:
    sw   a3, 0(s3)
    andi t5, s2, 4
    beqz t5, L2403
    addi t3, a4, 1
L2403:
    andi t5, s2, 256
    beqz t5, L2404
    addi a5, t3, 1
L2404:
    lw   t0, 28(s0)
    lw   a4, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2405
    xor  a5, a1, t0
L2405:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2406
    xor  t1, t4, t0
L2406:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L2407
    addi a3, t1, 15
L2407:
    andi t5, s2, 16
    beqz t5, L2408
    addi t4, a3, -56
L2408:
    sw   t1, 0(s3)
    andi t5, s2, 1
    bnez t5, L2409
    addi t1, a3, 1
L2409:
    andi t5, s2, 128
    beqz t5, L2410
    addi t0, t4, 1
L2410:
    lhu   a5, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2411
    xor  a1, a2, t1
L2411:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2412
    xor  t2, a3, t2
L2412:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2413
    xor  t1, t4, a3
L2413:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2414
    xor  t0, a1, t2
L2414:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L2415
    addi a1, t0, 39
L2415:
    andi t5, s2, 4
    bnez t5, L2416
    addi t0, a5, 88
L2416:
    andi t5, s2, 8
    beqz t5, L2417
    addi t2, t2, -71
L2417:
    sb   t4, 0(s3)
    andi t5, s2, 1024
    bnez t5, L2418
    addi a4, t3, 1
L2418:
    andi t5, s2, 64
    bnez t5, L2419
    addi a5, t0, 1
L2419:
    lw   t1, 12(s0)
    lb   t3, 19(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2420
    xor  t3, t4, t0
L2420:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2421
    xor  a3, t0, t2
L2421:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    bnez t5, L2422
    xor  t4, a5, a2
L2422:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2423
    xor  t0, t2, t2
L2423:
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    beqz t5, L2424
    addi a1, t0, -10
L2424:
    andi t5, s2, 256
    bnez t5, L2425
    addi t4, a2, -17
L2425:
    sh   t3, 0(s3)
    andi t5, s2, 8
    beqz t5, L2426
    addi t3, t0, 1
L2426:
    lw   t3, 0(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2427
    xor  a4, t0, t3
L2427:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2428
    xor  t1, t1, t3
L2428:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2429
    xor  t1, t2, t4
L2429:
    sw   t4, 16(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L2430
    addi a3, t2, 68
L2430:
    sh   a4, 0(s3)
    andi t5, s2, 16
    beqz t5, L2431
    addi a2, a4, 1
L2431:
    andi t5, s2, 64
    beqz t5, L2432
    addi a1, a2, 1
L2432:
    lw   t1, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2433
    xor  a4, t0, t4
L2433:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2434
    xor  t2, t1, t0
L2434:
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    beqz t5, L2435
    addi t0, t0, -86
L2435:
    andi t5, s2, 128
    beqz t5, L2436
    addi a5, t4, 26
L2436:
    sw   t1, 0(s3)
    andi t5, s2, 512
    bnez t5, L2437
    addi a1, t0, 1
L2437:
    andi t5, s2, 32
    bnez t5, L2438
    addi a2, a4, 1
L2438:
    lw   a3, 24(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2439
    xor  t2, t1, a1
L2439:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2440
    xor  a3, t3, t4
L2440:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1024
    beqz t5, L2441
    addi a4, t1, 47
L2441:
    sb   a3, 0(s3)
    andi t5, s2, 64
    beqz t5, L2442
    addi a1, t0, 1
L2442:
    lb   a1, 3(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2443
    xor  t4, a3, t4
L2443:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2444
    xor  a3, a1, t0
L2444:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2445
    xor  t4, a5, a5
L2445:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2446
    xor  a2, t1, t1
L2446:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L2447
    addi a1, a3, -65
L2447:
    andi t5, s2, 2
    beqz t5, L2448
    addi a4, t4, 16
L2448:
    andi t5, s2, 32
    beqz t5, L2449
    addi t0, t4, -58
L2449:
    sh   t3, 0(s3)
    andi t5, s2, 512
    beqz t5, L2450
    addi a4, t3, 1
L2450:
    lw   t2, 0(s0)
    lb   t1, 22(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2451
    xor  t0, t1, a5
L2451:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2452
    xor  t1, t4, a5
L2452:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    bnez t5, L2453
    addi a5, a2, -65
L2453:
    andi t5, s2, 16
    bnez t5, L2454
    addi t3, t0, 81
L2454:
    sw   t0, 0(s3)
    andi t5, s2, 32
    bnez t5, L2455
    addi t1, t4, 1
L2455:
    andi t5, s2, 64
    beqz t5, L2456
    addi a4, a1, 1
L2456:
    lb   a1, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2457
    xor  a5, t1, t1
L2457:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2458
    xor  a4, t1, t3
L2458:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    bnez t5, L2459
    xor  a5, t4, a5
L2459:
    sw   a1, 24(s0)
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2460
    addi a2, t3, -32
L2460:
    sb   a5, 0(s3)
    andi t5, s2, 8
    bnez t5, L2461
    addi a5, a4, 1
L2461:
    andi t5, s2, 128
    beqz t5, L2462
    addi a4, t3, 1
L2462:
    lb   t3, 31(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2463
    xor  a2, t4, a4
L2463:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2464
    xor  t2, a2, a2
L2464:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2465
    xor  t4, t1, t4
L2465:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2466
    xor  t4, a3, a3
L2466:
    sw   a5, 12(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 32
    beqz t5, L2467
    addi t2, t0, 12
L2467:
    sb   a5, 0(s3)
    andi t5, s2, 256
    beqz t5, L2468
    addi a2, t0, 1
L2468:
    andi t5, s2, 4
    bnez t5, L2469
    addi a3, t2, 1
L2469:
    lw   a2, 12(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1
    beqz t5, L2470
    xor  a3, a4, a1
L2470:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2471
    xor  a2, a1, a1
L2471:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2472
    xor  a5, t4, t4
L2472:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2473
    addi a4, t4, 6
L2473:
    sw   a2, 0(s3)
    andi t5, s2, 8
    bnez t5, L2474
    addi a3, a5, 1
L2474:
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2475
    xor  a3, a1, t0
L2475:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2476
    xor  a2, t2, a2
L2476:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    bnez t5, L2477
    xor  t2, a4, a1
L2477:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2478
    xor  t4, a2, a3
L2478:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L2479
    addi a4, t4, -13
L2479:
    andi t5, s2, 2
    bnez t5, L2480
    addi t2, a2, 76
L2480:
    sh   t3, 0(s3)
    andi t5, s2, 16
    bnez t5, L2481
    addi a1, t0, 1
L2481:
    andi t5, s2, 512
    bnez t5, L2482
    addi a1, t1, 1
L2482:
    lhu   a1, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2483
    xor  t1, t0, t1
L2483:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2484
    xor  a1, a1, t2
L2484:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2485
    xor  a5, t0, a1
L2485:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2486
    xor  t0, t2, a4
L2486:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    bnez t5, L2487
    addi a2, a5, -77
L2487:
    andi t5, s2, 2
    bnez t5, L2488
    addi t0, t0, 28
L2488:
    sh   t4, 0(s3)
    andi t5, s2, 128
    bnez t5, L2489
    addi a3, t3, 1
L2489:
    lw   t3, 16(s0)
    lw   t0, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2490
    xor  t0, t4, a2
L2490:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2491
    xor  a3, t1, t3
L2491:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 128
    beqz t5, L2492
    addi t0, a2, 45
L2492:
    andi t5, s2, 4
    beqz t5, L2493
    addi a5, t0, -35
L2493:
    andi t5, s2, 16
    bnez t5, L2494
    addi a1, t0, 62
L2494:
    sw   a5, 0(s3)
    andi t5, s2, 8
    beqz t5, L2495
    addi a5, t4, 1
L2495:
    andi t5, s2, 1024
    bnez t5, L2496
    addi a2, t4, 1
L2496:
    lw   t1, 4(s0)
    lw   a4, 28(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2497
    xor  a3, t0, t2
L2497:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2498
    xor  t3, t2, t2
L2498:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2499
    xor  t2, t3, a4
L2499:
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 512
    bnez t5, L2500
    addi a4, t3, -89
L2500:
    andi t5, s2, 64
    bnez t5, L2501
    addi a1, t0, -23
L2501:
    andi t5, s2, 2
    bnez t5, L2502
    addi a2, t3, -74
L2502:
    sw   t2, 0(s3)
    andi t5, s2, 64
    bnez t5, L2503
    addi t4, a1, 1
L2503:
    lb   t0, 26(s0)
    lw   a4, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2504
    xor  t4, a3, t3
L2504:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2505
    xor  a5, a3, a5
L2505:
    sw   a2, 16(s0)
    lw   s3, 28(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    bnez t5, L2506
    addi t0, t4, 87
L2506:
    andi t5, s2, 128
    beqz t5, L2507
    addi t2, t0, 14
L2507:
    andi t5, s2, 8
    bnez t5, L2508
    addi a4, a3, 90
L2508:
    sh   a1, 0(s3)
    andi t5, s2, 4
    bnez t5, L2509
    addi t0, a4, 1
L2509:
    lhu   a2, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2510
    xor  a5, t1, a4
L2510:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2511
    xor  a5, a3, a2
L2511:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    beqz t5, L2512
    xor  a3, t3, t3
L2512:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2513
    xor  t4, t3, t0
L2513:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 16
    bnez t5, L2514
    addi t2, t2, 80
L2514:
    andi t5, s2, 128
    bnez t5, L2515
    addi a1, a3, -89
L2515:
    andi t5, s2, 1024
    bnez t5, L2516
    addi a3, t0, -100
L2516:
    sw   t1, 0(s3)
    andi t5, s2, 1024
    bnez t5, L2517
    addi t3, a1, 1
L2517:
    andi t5, s2, 1024
    beqz t5, L2518
    addi t0, a5, 1
L2518:
    lw   a4, 4(s0)
    lw   t4, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2519
    xor  a5, t2, a1
L2519:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2520
    xor  a1, a5, a4
L2520:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2521
    xor  a2, a1, t2
L2521:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2522
    xor  t2, a3, t1
L2522:
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 1
    bnez t5, L2523
    addi a3, t3, -51
L2523:
    andi t5, s2, 256
    beqz t5, L2524
    addi a3, a4, 42
L2524:
    sb   t0, 0(s3)
    andi t5, s2, 32
    beqz t5, L2525
    addi t0, a5, 1
L2525:
    lb   t2, 27(s0)
    lw   a3, 8(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2526
    xor  a3, t2, t3
L2526:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2527
    xor  t0, a1, t1
L2527:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2528
    xor  t1, t2, a4
L2528:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    bnez t5, L2529
    addi a5, t4, -77
L2529:
    andi t5, s2, 8
    bnez t5, L2530
    addi t1, t3, -75
L2530:
    andi t5, s2, 16
    bnez t5, L2531
    addi t4, a1, -48
L2531:
    sw   a2, 0(s3)
    andi t5, s2, 512
    beqz t5, L2532
    addi t1, t3, 1
L2532:
    andi t5, s2, 1024
    bnez t5, L2533
    addi a2, a4, 1
L2533:
    lb   a5, 2(s0)
    lw   a3, 4(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2534
    xor  t2, t1, t1
L2534:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    bnez t5, L2535
    xor  a1, t3, a4
L2535:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2536
    xor  t3, t0, a3
L2536:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2537
    xor  a3, a2, a5
L2537:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2538
    addi a3, a1, -98
L2538:
    andi t5, s2, 32
    bnez t5, L2539
    addi a3, t3, -12
L2539:
    sw   t3, 0(s3)
    andi t5, s2, 4
    beqz t5, L2540
    addi a3, t0, 1
L2540:
    lw   a2, 8(s0)
    lb   a1, 30(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2541
    xor  t3, a3, t4
L2541:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2542
    xor  a3, a2, t1
L2542:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    bnez t5, L2543
    xor  t0, a3, t0
L2543:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 256
    beqz t5, L2544
    addi a5, t2, 50
L2544:
    sb   a2, 0(s3)
    andi t5, s2, 16
    beqz t5, L2545
    addi a5, a2, 1
L2545:
    andi t5, s2, 8
    beqz t5, L2546
    addi a4, a1, 1
L2546:
    lhu   a1, 16(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2547
    xor  t3, a4, t4
L2547:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 16
    beqz t5, L2548
    xor  a1, a5, a1
L2548:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    beqz t5, L2549
    xor  t3, t0, t2
L2549:
    lw   s3, 12(s0)
    xor  s3, s3, s2
    li   s4, 11
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 4
    beqz t5, L2550
    addi a1, t2, -44
L2550:
    andi t5, s2, 64
    beqz t5, L2551
    addi a4, a5, -78
L2551:
    sb   t1, 0(s3)
    andi t5, s2, 4
    beqz t5, L2552
    addi a1, a4, 1
L2552:
    andi t5, s2, 128
    bnez t5, L2553
    addi t4, t1, 1
L2553:
    lb   t1, 2(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2554
    xor  a5, t4, t4
L2554:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 256
    beqz t5, L2555
    xor  a2, t4, a4
L2555:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2556
    xor  a1, t2, t3
L2556:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2557
    xor  t3, a4, t3
L2557:
    lw   s3, 20(s0)
    xor  s3, s3, s2
    li   s4, 5
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L2558
    addi a4, t2, -2
L2558:
    andi t5, s2, 4
    beqz t5, L2559
    addi t1, a3, 11
L2559:
    sw   t2, 0(s3)
    andi t5, s2, 1024
    beqz t5, L2560
    addi a5, a2, 1
L2560:
    andi t5, s2, 256
    bnez t5, L2561
    addi a5, t4, 1
L2561:
    lb   t1, 9(s0)
    lb   a2, 14(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2562
    xor  a5, t4, a2
L2562:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2563
    xor  a5, a3, a1
L2563:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2564
    xor  t0, a3, a5
L2564:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2565
    xor  a5, t3, a1
L2565:
    lw   s3, 16(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2566
    addi t1, t2, 41
L2566:
    andi t5, s2, 16
    beqz t5, L2567
    addi t0, t3, -58
L2567:
    sh   a5, 0(s3)
    andi t5, s2, 4
    beqz t5, L2568
    addi t3, t2, 1
L2568:
    andi t5, s2, 1
    beqz t5, L2569
    addi t2, a1, 1
L2569:
    lb   a4, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2570
    xor  t0, t2, a2
L2570:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2571
    xor  a1, a1, t0
L2571:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2572
    xor  t2, a3, t0
L2572:
    lw   s3, 4(s0)
    xor  s3, s3, s2
    li   s4, 3
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L2573
    addi a5, t4, 22
L2573:
    sw   t2, 0(s3)
    andi t5, s2, 16
    beqz t5, L2574
    addi a5, a5, 1
L2574:
    andi t5, s2, 256
    beqz t5, L2575
    addi t2, a3, 1
L2575:
    lw   a4, 8(s0)
    lw   t4, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    bnez t5, L2576
    xor  t4, t2, t3
L2576:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    beqz t5, L2577
    xor  t4, a2, t1
L2577:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 128
    beqz t5, L2578
    xor  a4, a4, t1
L2578:
    sw   t2, 24(s0)
    lw   s3, 24(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 2
    beqz t5, L2579
    addi t2, a3, -23
L2579:
    andi t5, s2, 256
    beqz t5, L2580
    addi t1, a2, -87
L2580:
    sw   t2, 0(s3)
    andi t5, s2, 1
    beqz t5, L2581
    addi t2, t3, 1
L2581:
    lw   t1, 0(s0)
    lb   a1, 10(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    bnez t5, L2582
    xor  t4, a5, a3
L2582:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    bnez t5, L2583
    xor  a4, t2, a5
L2583:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 2
    bnez t5, L2584
    xor  a2, a1, a3
L2584:
    sw   a2, 8(s0)
    lw   s3, 0(s0)
    xor  s3, s3, s2
    li   s4, 9
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 64
    bnez t5, L2585
    addi a5, a3, 76
L2585:
    andi t5, s2, 256
    bnez t5, L2586
    addi t0, t0, -77
L2586:
    sb   a4, 0(s3)
    andi t5, s2, 16
    beqz t5, L2587
    addi t3, a2, 1
L2587:
    lhu   a5, 12(s0)
    lhu   a4, 26(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 1024
    bnez t5, L2588
    xor  t3, t4, t4
L2588:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 8
    beqz t5, L2589
    xor  a2, t4, t0
L2589:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2590
    xor  t4, t3, t2
L2590:
    sw   a2, 16(s0)
    lw   s3, 8(s0)
    xor  s3, s3, s2
    li   s4, 7
    mul  s3, s3, s4
    mul  s3, s3, s4
    mul  s3, s3, s4
    andi s3, s3, 28
    add  s3, s3, s0
    andi t5, s2, 8
    bnez t5, L2591
    addi a3, a1, 63
L2591:
    andi t5, s2, 8
    bnez t5, L2592
    addi t2, t2, -64
L2592:
    andi t5, s2, 4
    beqz t5, L2593
    addi a1, a1, -77
L2593:
    sw   t4, 0(s3)
    andi t5, s2, 4
    beqz t5, L2594
    addi t0, a3, 1
L2594:
    andi t5, s2, 512
    beqz t5, L2595
    addi a4, a4, 1
L2595:
    lw   t3, 20(s0)
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 4
    beqz t5, L2596
    xor  t3, a1, a1
L2596:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 32
    bnez t5, L2597
    xor  a1, a5, a2
L2597:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 512
    beqz t5, L2598
    xor  t4, a5, t4
L2598:
    srli t6, s2, 3
    xor  s2, s2, t6
    andi t5, s2, 64
    beqz t5, L2599
    xor  a1, a4, t2
L2599:
    sw   t3, 20(s0)
    addi s1, s1, -1
    bnez s1, outer
    li   a0, EXIT
    li   t0, 1
    sw   t0, 0(a0)
9:  j    9b
    .data
    .align 5
buf: .word 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
