    .equ EXIT, 0x20000000
    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la   sp, __stack_top
    li   s1, 3
    li   t0, -2
    li   t1, 3
    li   t2, 3
    li   t3, 0
    li   t4, -132146088
    li   t5, 932643718
    li   a1, 213164247
    li   a2, -1
    li   a3, -1
    li   a4, 99562544
    li   s2, -1872470703
    li   s3, 391269738
outer:
    clmul t0, t4, a2
    slt a1, s3, a1
    sltu a4, a2, t2
    mulhsu t2, a2, t3
    andi t6, s2, 8
    bnez t6, 11f
    clmulh a1, a4, t5
    clmul a4, a1, a4
    mulh t5, s2, t0
11:
    li   a4, -1
    xor t5, a3, a4
    sra t3, s2, a4
    mulhu t1, a2, s2
    mul t1, a1, t2
    clmul a1, t1, t0
    sltu t0, a1, s3
    add t4, a3, t3
    clmul t1, t1, a4
    clmul t3, a1, t4
    mulhsu s3, t0, t5
    mulhu t2, a1, a1
    li   a1, -2
    clmulr a3, t4, a1
    sra t3, t4, a1
    clmulh a3, t5, t0
    mulhu a4, t5, t0
    sltu s2, t2, t0
    clmulr s2, t5, a4
    mul a2, t0, a4
    andi t6, t5, 32
    bnez t6, 12f
    mulhsu a4, a4, t5
    mulh t5, t2, t5
12:
    slt a4, t4, t4
    clmulr t0, a4, s2
    clmulh a3, t3, s2
    mulhu t5, t2, s2
    sltu t1, t1, a4
    andi t6, t3, 2
    bnez t6, 13f
    mulhsu s3, s2, t3
13:
    li   a2, 1
    mulh t3, t5, a4
    li   t5, 3
    clmul t2, a1, t4
    slt t4, a2, t5
    mulhu a4, a1, t0
    clmul t0, a2, a4
    clmulr s3, t3, t0
    mulhsu s2, s3, a3
    mulhsu t3, t1, a4
    clmulh t3, t0, t0
    add t3, a1, a4
    clmul s3, t1, t2
    clmul s2, t0, a3
    mulh a4, t1, t5
    mulhsu a3, a2, t0
    mulh t1, a3, t1
    mulhu t4, t2, t0
    sll a1, t0, t4
    mul a3, a3, a1
    mul t0, t0, t2
    clmulh t1, a2, t0
    sltu a3, a3, a2
    clmulr t1, t5, a1
    mulh t4, t5, t4
    andi t6, t1, 16
    bnez t6, 14f
    clmulr s3, a1, t1
14:
    slt t0, t5, a2
    add t0, a4, a1
    mulhu a2, s3, t5
    andi t6, a2, 2
    bnez t6, 15f
    clmul t4, s3, a4
15:
    mulh a1, t3, a1
    li   t5, -2147483648
    clmulr s3, t1, s3
    li   a3, 1
    add a4, a3, t1
    clmul t3, a1, t0
    mulh t1, s2, a1
    li   t5, 1
    sra s3, t4, a4
    sll t0, a4, a3
    mul s3, t1, a3
    sll a4, t2, t1
    andi t6, t3, 16
    bnez t6, 16f
    clmulh a1, t4, t5
    clmul a1, t5, a3
    mulhu t1, a1, a3
16:
    mulhu a1, s3, t2
    or a4, s2, a3
    mul a1, t2, t2
    mulhu a2, s3, a3
    sll t2, t2, t4
    clmulh a3, t5, t3
    slt t4, s2, s3
    sll a4, a4, t4
    mulh t4, a2, a1
    mulhu t5, t3, t5
    or t2, a1, s3
    add t3, a2, a4
    clmulh s3, t1, a1
    sll t0, a2, t3
    sra s2, t1, t3
    mulh t3, t4, t2
    sub s2, t0, t4
    li   t5, 1
    sra t1, t1, t1
    li   t4, 32768
    add s2, t5, t0
    mul a1, a1, a2
    mulhu a4, s3, a2
    mul t5, t1, t4
    sra t1, a2, a3
    clmulh s3, t5, s2
    clmulr a2, t4, s2
    xor t4, t1, t5
    sra a3, t5, t0
    sub a4, s3, t2
    mul s2, a2, t1
    andi t6, t5, 32
    bnez t6, 17f
    clmul a1, a3, t4
    clmulr t2, a2, a2
    mulhsu t2, s3, t1
17:
    clmul t2, a3, a3
    sra t5, t1, t4
    clmul t2, t0, a2
    mulhsu s3, a3, t5
    andi t6, a3, 4
    bnez t6, 18f
    clmulh t1, t2, t4
    clmul t1, s2, t1
18:
    sll s3, t1, t2
    sub s2, s3, a1
    sub t2, a1, t3
    sra t3, t4, t5
    mulhsu a2, a1, a1
    or a4, t4, s2
    andi t6, s3, 32
    bnez t6, 19f
    mul a4, t3, s3
    clmulr t0, t1, s2
19:
    mulhu t2, a3, s2
    clmulh a3, t3, t0
    clmul s2, a2, t1
    mulhu s2, t2, t2
    sltu a4, t0, t0
    add a3, t1, a2
    andi t6, t5, 32
    bnez t6, 110f
    mulh t1, a4, t0
    clmulr t1, s3, t5
    clmulh t3, t1, t3
110:
    mul t3, a2, t5
    sub a1, t1, t3
    clmul a2, s3, t1
    li   t3, -2147483648
    mulhu a2, s3, a1
    mulhsu t0, s3, t4
    li   a2, 3
    clmulh t0, t3, t4
    mulh a2, a3, t3
    clmul t2, a4, a1
    clmul t0, t2, t1
    clmulh a2, t2, t0
    mul a2, t5, a1
    add t0, t3, a1
    mul t0, t3, t3
    clmul t3, t2, t5
    clmulh t1, a4, t0
    or t4, a2, t4
    clmulr t4, t0, t5
    andi t6, t1, 32
    bnez t6, 111f
    mul a4, a4, t0
    mul t0, s2, t1
111:
    mul a3, t0, a2
    clmulh a3, t5, t3
    mul a2, t5, s2
    mul a4, s2, a1
    andi t6, a1, 16
    bnez t6, 112f
    clmul t5, a3, s2
    clmulh a1, t2, s3
112:
    li   a1, -1
    mulhu a1, a2, t3
    sub a2, t5, t4
    mulhu a4, s3, s3
    andi t6, t2, 32
    bnez t6, 113f
    clmulh a2, t1, s3
113:
    add t1, t5, t3
    li   t0, 65535
    andi t6, t1, 8
    bnez t6, 114f
    mulhsu a4, t4, t1
114:
    clmulr s2, t3, t3
    clmul t2, s2, t2
    andi t6, t3, 2
    bnez t6, 115f
    clmulh a3, a3, a1
115:
    clmulh a4, t5, a3
    mul t2, a4, t1
    li   t1, 1
    mulhu t4, t1, t1
    clmulr s2, a4, t1
    mulhu s2, s3, t5
    or a2, t1, t4
    li   t3, 0
    mulhsu s3, s2, t1
    clmulr a2, t1, a3
    sll a1, s2, t1
    mulhu t0, t5, t3
    mulh t4, t3, t5
    or t3, s3, t3
    andi t6, a1, 2
    bnez t6, 116f
    mulhu a2, a1, a2
    clmul t0, t4, t0
    mulh t1, t0, s3
116:
    clmulr a3, a3, t0
    mulhsu t3, s3, t3
    clmulr t0, t5, a2
    mulhu t4, t2, t1
    mulh a1, a2, t1
    clmulh s3, t4, a1
    li   t5, -2147483648
    andi t6, a3, 2
    bnez t6, 117f
    clmulh t4, t4, t0
    mulhu t5, t5, t4
117:
    sub a3, t0, t0
    sub t2, a3, t0
    andi t6, t3, 4
    bnez t6, 118f
    clmul t0, a2, t2
    mulh t0, t4, a1
118:
    andi t6, a4, 1
    bnez t6, 119f
    mulhsu t4, t3, s2
    clmulh a2, a1, s3
119:
    mul t0, t0, a1
    sll s2, t2, a4
    andi t6, a1, 4
    bnez t6, 120f
    mulh t4, t0, t2
    mul t0, a2, s2
    mul a2, a2, a3
120:
    sltu a4, a3, a1
    mul t2, t4, t2
    sltu a3, t1, a1
    mulhsu t4, t4, a2
    andi t6, a4, 2
    bnez t6, 121f
    mul a1, a2, t3
    clmulh a2, a4, a4
    mulhsu t0, t5, a4
121:
    sra t1, a2, t2
    xor t4, t1, a1
    mulhu a3, a2, s2
    mulhu t5, t2, s2
    andi t6, t5, 4
    bnez t6, 122f
    mul t5, t5, a4
122:
    mulhu t4, t0, t2
    mulh t1, a2, t3
    xor s3, a3, t1
    xor t0, t4, s3
    mulhsu a2, a2, t4
    mulhu t0, t2, t3
    andi t6, t2, 2
    bnez t6, 123f
    mulhu s2, a1, s2
    mul t2, a1, t0
    mulh s2, t2, t4
123:
    clmul t2, t2, t0
    andi t6, t3, 1
    bnez t6, 124f
    mulhu t2, t0, t4
    mul t2, t1, t2
124:
    mul a1, t5, a4
    andi t6, t5, 8
    bnez t6, 125f
    mul t5, a3, a2
125:
    clmulr t5, a2, t0
    mulhu s3, a2, a4
    mulh a3, t4, a2
    mulhsu a1, t3, a4
    andi t6, t2, 2
    bnez t6, 126f
    mulhsu t3, t2, t0
    clmul t0, a1, a4
126:
    li   t1, -1
    li   a1, 65535
    clmul t4, t1, a2
    sll t5, t2, a4
    clmulr a3, a4, t5
    clmulh t5, s3, a4
    andi t6, s3, 4
    bnez t6, 127f
    mulhsu t2, t1, a4
    clmul t3, s3, t5
127:
    sra t3, t4, a1
    clmulh a2, t5, a3
    li   a4, 32768
    andi t6, t1, 8
    bnez t6, 128f
    clmulh a4, t4, t0
    mulh a1, a1, t3
    mul t5, a3, t3
128:
    clmulr a2, t1, a1
    li   s3, 0
    mulhu a3, t5, a1
    clmul s2, s2, t1
    mulhsu t5, t3, t0
    mulh t0, t2, t1
    mul t4, t3, t0
    clmulr t5, a3, a2
    mulhsu s3, t3, a2
    sll t1, a3, a1
    mulh t4, t4, a3
    mulhu t2, a4, t1
    mulhu t5, a1, t0
    li   t2, -1
    clmul a3, s2, a1
    sra s2, t4, a1
    mul s3, s3, t1
    clmulh s3, t5, t1
    mul a2, a1, s2
    li   t5, 3
    mulhu t5, t3, s2
    andi t6, s2, 1
    bnez t6, 129f
    clmul t3, a4, t1
    mulh t3, a2, a3
    mulhu t4, t5, a2
129:
    sra a3, t3, t3
    clmul a4, t2, a4
    clmulh a3, t5, t5
    li   a4, -2
    clmulh t0, s3, a1
    mulh t3, a2, t3
    li   a2, 65536
    li   t5, 65535
    mul a1, s2, s3
    mulh t5, a1, t3
    clmulr t5, t4, t0
    andi t6, t1, 2
    bnez t6, 130f
    mulhu t2, a4, t2
    mulh a2, s3, t3
130:
    mulh s2, t5, a4
    clmul a3, a1, a4
    mulhu t2, s2, t4
    mulhu t1, a3, a2
    mulhu t2, t4, a3
    or t3, a1, a3
    mul a4, a2, t2
    sltu t5, s3, t2
    mulhu a3, t2, t4
    or t2, a2, t5
    clmul t5, s2, t3
    clmul a3, a4, t4
    li   t4, 65536
    li   s3, 0
    mulhu a3, s3, t5
    mulhsu a4, t2, t3
    xor a4, a1, s3
    mulhu t2, t5, s3
    mulhu a1, a2, t3
    add t5, t1, s3
    sub s3, t3, t2
    mulhu a3, a3, t1
    li   a3, -2147483648
    mulh t4, s2, t5
    andi t6, t3, 8
    bnez t6, 131f
    mulhu t2, t4, t5
    clmulr t2, t4, a4
131:
    sll t3, s2, t3
    andi t6, s3, 1
    bnez t6, 132f
    clmulh s3, t2, t1
132:
    mulhsu a2, t5, t1
    li   t2, 32768
    clmulh a3, t2, t5
    clmulr a1, a3, a4
    sra a1, t4, t4
    add a1, t2, t0
    clmulh s2, t0, t3
    sltu a3, s3, t3
    clmulr s2, a3, a4
    andi t6, t3, 2
    bnez t6, 133f
    clmulr t1, a2, a1
133:
    sltu t2, t1, a3
    sra a4, s3, t2
    mulh a4, t1, s2
    clmulh s3, t1, s2
    clmulr s3, a2, a3
    add t4, t2, s3
    mulh s2, s3, a1
    mulhsu t5, a3, s3
    li   t5, 2147483647
    clmulr a3, a2, s2
    mulh t3, a2, a2
    li   t5, -1
    clmul t1, a1, t5
    mulhsu s2, a4, t3
    mulhsu a1, t0, a4
    mulhsu a2, a4, a3
    sll a4, a1, s2
    clmulh a1, s2, t4
    mul a2, a3, a3
    mulhu a4, a4, t2
    mulh t4, a3, t2
    mulhu t4, t1, t1
    mul t3, s3, a1
    mul a2, a4, t0
    sltu a2, t0, t0
    sra t4, a2, a2
    xor t2, t4, s2
    clmulr s2, t0, t1
    mulhu t1, t2, s3
    clmulr s3, a3, t2
    clmulh s2, t4, a3
    andi t6, a2, 4
    bnez t6, 134f
    mulhu t1, a1, s2
    clmulr t5, a3, a1
    mulhu a2, t5, a4
134:
    andi t6, t4, 32
    bnez t6, 135f
    mulhsu a2, s3, t4
    mulh t5, t1, s2
    mulhsu s3, a2, a1
135:
    clmul t3, s3, t5
    clmul t3, a4, t0
    mul a1, t2, t5
    slt a3, a2, t4
    li   a4, 65536
    clmulh t0, t5, s3
    sra t5, s3, a1
    clmulh t2, t3, t3
    xor s2, a1, s3
    slt a1, a2, a2
    mulh a3, a1, a4
    clmulr t0, s2, a3
    clmulr t0, t3, a4
    li   s3, 65536
    sll t1, t1, t1
    andi t6, a3, 8
    bnez t6, 136f
    mulh t2, t3, s3
    clmulh s2, a1, a2
136:
    mulhsu a2, a3, t0
    clmul a4, t5, t5
    mul t1, t4, t3
    clmulh a1, t3, t3
    andi t6, s3, 4
    bnez t6, 137f
    mulhsu t3, a3, t3
    clmul s3, a1, t0
    clmul s2, t4, t3
137:
    andi t6, a4, 4
    bnez t6, 138f
    mulh t4, t2, t5
    mulh t3, s2, a3
138:
    add a2, a1, t4
    mulhsu a1, t4, a4
    li   a3, 2147483647
    mulhu s2, t1, t1
    li   a1, 3
    clmul s3, t1, a4
    clmul t2, t5, t5
    clmulh t5, t0, t1
    mulhsu a3, t1, a1
    or t0, a2, a2
    andi t6, a2, 1
    bnez t6, 139f
    mulhsu a2, t4, a1
139:
    li   t3, 32768
    clmul t5, s3, t0
    mulhu a4, a2, a3
    mulh t1, s3, t4
    clmulh a3, t1, s2
    mul s3, t4, t5
    mul t0, t3, t5
    andi t6, a1, 1
    bnez t6, 140f
    clmulh a3, a2, t5
    clmulr a2, t0, a2
    clmulr a1, s2, a3
140:
    xor t1, t1, s2
    clmulr t1, t4, t1
    mulhu t3, t0, s3
    mulhsu a3, s3, t3
    sltu s3, a4, t4
    add t0, t3, s3
    clmulr a4, a1, t2
    li   a2, 65536
    sra t2, a4, s3
    li   t4, -1
    mulh t5, a2, a1
    mulhsu s3, a3, t5
    mul t2, t4, t5
    clmul a1, s3, t4
    mul a3, a1, t3
    sltu t0, a4, s3
    mulhu t0, s2, s2
    mulhu a4, t4, a4
    mulh s3, a2, s3
    li   t4, 1
    li   a2, -1
    clmul t4, s3, t2
    andi t6, t0, 2
    bnez t6, 141f
    mulh a2, s2, a4
    mul t4, t5, s2
    mulh a3, s2, t1
141:
    clmul a2, t4, a2
    mulh s2, t5, t4
    sra a4, a4, a2
    li   a3, 2147483647
    clmul a3, t0, t5
    mulhu t0, t2, t0
    clmul t1, t2, t5
    li   a2, -2
    mulhsu a3, t3, s2
    mulhsu t4, a3, t3
    li   t5, -1
    mul s2, s3, a1
    clmulr a1, t0, s2
    sra t1, t4, a1
    mulhu t0, t2, t1
    sll a1, s3, a1
    sltu a1, t0, t4
    clmulr s2, t5, a1
    mulhsu t3, s3, a4
    andi t6, s3, 4
    bnez t6, 142f
    mulhsu t4, a4, t2
    mulh t5, s3, t0
    mulh s2, t2, a2
142:
    clmulh t2, a4, a2
    li   a4, 65536
    li   a1, 1
    clmulh s2, t1, t3
    sra a4, t5, t5
    mulhu s3, s2, s2
    sltu a1, t2, s2
    clmulh t4, t5, a4
    slt s3, t3, t3
    sll t3, s2, s3
    mulhu t5, a4, t4
    clmul t1, s3, t1
    slt t0, s2, a4
    li   t0, 3
    andi t6, a4, 2
    bnez t6, 143f
    clmul t2, t4, t2
    clmulh a2, s2, a1
    mulhsu a3, t3, t2
143:
    sll a4, a2, t1
    li   t0, 32768
    li   a3, 1
    sltu t5, a1, t4
    or a4, a1, t1
    andi t6, s2, 8
    bnez t6, 144f
    mul t4, a3, t1
    clmulh t3, a4, a3
    mulhsu t4, s2, t3
144:
    add s2, t5, a1
    andi t6, t0, 2
    bnez t6, 145f
    mulh s2, t1, t3
    mulhsu t2, a3, t1
    mulh a1, a3, a2
145:
    mulhu t1, t5, t3
    add a1, t3, t1
    mulhsu t1, a3, s3
    sub t3, t2, a2
    clmul t5, t1, a2
    or t2, t3, t3
    clmul s2, t0, t3
    clmulr s2, t5, t1
    mulhu s2, a4, t0
    clmulh t3, t1, t2
    clmul t5, s3, t3
    or t0, t4, t1
    mulhu a2, t3, t1
    andi t6, s2, 16
    bnez t6, 146f
    mulh s2, a3, t4
146:
    clmul a2, a1, t0
    clmulh t3, a3, a1
    add t1, t1, a2
    li   t2, 3
    li   t5, 32768
    clmul t1, t5, a4
    mul t5, t5, t0
    clmulr t1, t0, t4
    slt a2, s2, t0
    sltu a1, t0, t4
    clmulr a3, t5, t3
    slt t5, a4, t4
    clmul t4, t1, s3
    mulhu s2, a3, t1
    clmul t1, a4, s3
    mulh t5, s2, t3
    mulhu s3, a4, a1
    andi t6, t4, 2
    bnez t6, 147f
    clmulr s2, s2, s2
147:
    andi t6, t3, 16
    bnez t6, 148f
    mulhsu s3, s3, a1
    clmul a1, s3, a2
148:
    mulhu t4, a1, a3
    sltu t4, t1, s3
    li   t1, 65536
    mulh a2, t4, t1
    clmulh a4, s3, a4
    clmulr t1, a4, a1
    mul s3, a2, t4
    sra a4, t4, s2
    mul a4, t3, s3
    clmul a1, a3, a1
    li   a1, 0
    mulh a1, a2, t1
    clmulr s3, s2, t2
    clmulr s2, a4, t5
    andi t6, s2, 32
    bnez t6, 149f
    mulhsu t5, s2, t0
149:
    sltu a4, t4, a2
    add t3, a1, s3
    li   t0, 65535
    slt t1, a2, s2
    clmul t0, t4, a2
    mulhu a1, t3, t2
    xor t1, t1, t1
    mulhsu t0, t3, s3
    mulh a3, t0, a1
    andi t6, t1, 32
    bnez t6, 150f
    mulh a1, t2, t5
    mulh t5, t5, a3
    mulhsu t1, t2, a2
150:
    mul t2, t5, t3
    li   t2, -2147483648
    xor a3, t4, a3
    clmulh t3, t1, t1
    sll t4, t5, s2
    clmul s2, s3, a4
    clmulr t2, t3, t5
    andi t6, t1, 2
    bnez t6, 151f
    clmulr t0, t3, t4
    mulhsu t0, t5, a2
151:
    andi t6, t5, 4
    bnez t6, 152f
    clmulh a4, a2, a4
    clmulh t1, t5, s3
152:
    or s3, s2, t4
    mulh a2, t4, s3
    xor t5, t1, a2
    clmulr s2, t2, t5
    mulhsu t5, t0, a4
    mulhsu t3, t4, t5
    mulh a2, s2, t2
    clmul t5, a4, a3
    clmulr t4, t5, a1
    mul a1, t3, a4
    mul t1, t2, a3
    mulh t4, t5, t4
    mul s3, t1, t0
    sub t1, a3, t2
    li   a2, 65535
    sll s3, t0, a1
    mulhsu a3, a3, t4
    add t4, t2, t5
    clmulh t1, t2, t2
    mulhu t1, a1, t0
    mulh s3, a3, a2
    clmul a3, s2, t4
    clmul t3, a4, t3
    or a4, a4, a2
    or s2, s2, t0
    clmulh t5, t2, t5
    clmul t0, t4, a1
    mul t5, a4, t1
    xor t4, t2, a3
    mul t4, a2, a2
    mulhu t4, t0, t5
    mulh t3, s2, t5
    li   a2, 65535
    mulhu t0, t0, a3
    slt t4, s2, a4
    or a1, t4, t5
    slt a4, t0, a3
    mulh t2, a4, t3
    li   t5, -2147483648
    mulhsu a1, t4, t5
    or t0, a3, t0
    clmulh a4, s2, t4
    andi t6, t2, 32
    bnez t6, 153f
    mulhsu t1, t2, t2
153:
    andi t6, s2, 2
    bnez t6, 154f
    mulh s2, a2, s2
    clmulh a2, t4, t3
    clmulr a3, t5, a4
154:
    clmul s2, t5, s2
    mulhsu s3, s3, t3
    li   t2, -2147483648
    or a1, a4, t5
    li   a2, 0
    clmulh a2, a2, s3
    or a2, t5, t4
    clmulh s3, t4, t2
    andi t6, t1, 4
    bnez t6, 155f
    mulhu a3, a2, a4
    clmulr s3, t5, t0
155:
    or t0, t3, t4
    mulh s3, a4, a1
    sll t5, a1, t5
    sll a2, s2, t3
    clmulr t3, t2, t1
    clmulh a2, t4, s2
    clmulr a2, t1, a1
    mul a2, t4, t3
    clmulr t4, t1, t3
    mulh t0, s3, a2
    li   s2, 1
    sltu a2, s2, a1
    clmul t4, t1, t0
    mulh a4, t5, t4
    xor a3, t5, a3
    clmul a3, t1, a1
    sra s2, t1, t0
    andi t6, s2, 8
    bnez t6, 156f
    clmulr t2, t4, t5
    mulhsu a4, t3, s3
    clmul a2, t1, t2
156:
    clmulh a4, t3, t5
    sll a4, s2, t5
    mul t3, a3, t2
    andi t6, s3, 16
    bnez t6, 157f
    mulhu a3, a4, t1
    clmul t0, s3, t3
    clmul a4, a2, a1
157:
    slt t5, t5, t3
    clmulh a1, a1, t3
    mulhsu a2, t3, t0
    sltu t0, t0, t5
    mulh a3, s3, a2
    mulhsu t5, a3, t5
    clmulr a1, s2, a3
    slt t2, a1, t4
    mul a4, t4, t0
    mul a3, t1, t1
    andi t6, a2, 16
    bnez t6, 158f
    clmulh t3, a4, t1
    mulhu a4, a2, a3
158:
    or a3, a4, t4
    andi t6, t0, 2
    bnez t6, 159f
    clmulr a1, t5, s2
159:
    sltu s3, a4, t2
    mulh s3, t5, t3
    clmulh a3, a1, t1
    clmulh t2, a1, s3
    mul s3, a1, t0
    clmulr s3, t3, s3
    li   t0, 3
    clmul t1, t1, t4
    andi t6, t3, 32
    bnez t6, 160f
    clmulh a2, t4, a3
160:
    sll t3, t0, t2
    clmulr a3, a1, t1
    add t0, a1, a2
    mulhsu t3, t2, s2
    or a2, s2, t5
    li   t4, 65535
    andi t6, a1, 8
    bnez t6, 161f
    clmul t1, a3, t5
    mulh t0, t4, t3
161:
    clmulr t4, s3, t2
    clmul a3, a4, s2
    mulh a3, s2, s2
    andi t6, a4, 16
    bnez t6, 162f
    clmul t4, a2, a3
162:
    clmulr a3, t0, a2
    mulhu a2, t1, a2
    mulh t5, a2, a3
    xor t1, t3, t1
    mulhu t3, a3, a4
    andi t6, t3, 32
    bnez t6, 163f
    clmulh a4, t2, t4
163:
    mulhu t4, t4, t2
    clmulr t0, t0, t3
    li   a4, 32768
    clmul a4, t4, a1
    clmulr s2, t0, t5
    mulh a1, t1, t2
    xor t2, t5, t4
    sll t1, t2, a2
    sra a1, t1, t0
    clmul a2, a4, s3
    clmulr a4, s3, t0
    clmulr s2, s2, s3
    mulh t2, t5, a3
    slt a4, a1, t2
    or t1, a3, a3
    mulhu t2, t3, t3
    andi t6, t0, 2
    bnez t6, 164f
    mulhu t4, t5, t4
164:
    mulhsu t0, t4, t3
    slt t5, a3, a3
    mulh s2, t5, s3
    sltu a1, s2, t3
    add s2, t2, t5
    xor t1, t4, a2
    clmul t3, t2, s2
    clmulr t3, s3, t0
    mulhu a4, t3, t0
    mulhsu s2, t4, t5
    mulhsu a2, t5, a3
    sra t3, s2, t2
    clmul a2, t5, s3
    slt s2, t5, s2
    mulhsu s3, a1, s2
    mulhu t2, t0, a1
    xor t4, a1, a3
    clmulh a2, s3, s3
    mulh t1, t2, t4
    clmulh t2, t4, t2
    sltu t4, s2, t5
    clmulh t2, a1, s3
    clmulh a3, a4, t4
    mulhu a1, a3, a4
    clmulr t1, t2, t0
    clmulr t2, a4, a2
    li   a1, 2147483647
    mulhsu s3, t3, a4
    mulhsu a1, a1, s3
    li   s3, 0
    andi t6, t4, 16
    bnez t6, 165f
    mulhu a3, t4, t0
165:
    li   a3, 1
    andi t6, a3, 16
    bnez t6, 166f
    clmulr t4, t4, s2
    mulhsu t2, s2, t5
    clmulr t0, t3, t2
166:
    clmul a3, a1, t0
    li   s2, 3
    slt a2, t1, s3
    sll t1, a2, s2
    clmul s3, s2, t3
    mul t2, t5, t1
    mulh t1, t2, t2
    andi t6, a1, 16
    bnez t6, 167f
    mulh t2, a4, a3
    mulh s3, s3, t0
    clmulh t1, a1, s2
167:
    sub a3, t1, a2
    sra a2, t2, t1
    mul t0, a4, t0
    li   s3, 0
    xor t0, a4, s3
    andi t6, a2, 16
    bnez t6, 168f
    clmulh t3, s2, s2
168:
    mulhu t0, t2, s3
    add t1, a2, a3
    clmulr t4, t4, t3
    mulhsu a2, t5, a4
    li   s2, -2
    li   a1, 3
    mulhsu a4, a4, a2
    mulhu t5, a4, t2
    clmul a2, s3, t4
    mulhu a3, t5, a2
    clmul t1, t3, t5
    sll a1, t2, t0
    clmulh s2, t1, t3
    andi t6, a4, 1
    bnez t6, 169f
    clmulr a3, t3, s2
    mul a3, t0, a3
169:
    clmulr t3, t2, t2
    sra s2, t5, a3
    li   a4, 1
    clmulr t3, a1, a3
    mulhu t4, a3, s3
    or t5, a1, s2
    mulh t3, a1, t0
    mul a2, t3, s2
    mulhu t1, a3, a2
    mulhu s3, a2, t0
    clmulh t2, a1, t0
    clmulr a1, t5, s3
    mulhsu a1, a1, t1
    sltu t5, t3, a3
    clmulr t5, a1, t1
    mulhu a1, t2, a2
    clmul a1, t2, t5
    andi t6, a2, 8
    bnez t6, 170f
    mul t4, a3, t4
    clmulh s3, s2, t4
170:
    mulh t5, t1, a2
    mulh t1, a1, t5
    mulh t0, t4, s3
    mulhsu t0, t5, a2
    li   s2, -2147483648
    li   t4, 1
    mulhsu t2, t5, t0
    li   t2, 2147483647
    clmulr a4, a1, s3
    clmul s2, t1, t5
    sltu t1, t0, t0
    mulhu s3, s2, a2
    mulhsu t3, s3, s2
    clmulr t2, t4, a2
    mulhu s3, t3, t2
    clmulh a3, t1, a4
    or t4, a2, a2
    mulhu a3, a3, a1
    mulhsu a2, a4, t5
    mulh t3, t5, t3
    mulhsu a2, t0, s3
    andi t6, t2, 1
    bnez t6, 171f
    mul t0, t1, a1
171:
    mulh s3, t5, a4
    mulh a1, a1, s3
    li   t2, 3
    mulh s2, t0, s2
    clmulr a4, t4, t0
    xor a2, a2, t4
    clmul a1, a3, s3
    clmul a2, t2, a2
    clmulh s2, t0, t3
    slt t1, t5, t2
    andi t6, t0, 16
    bnez t6, 172f
    mulh a3, t3, t4
    mulhu t5, t1, t0
172:
    mulh s3, a1, t3
    sub t0, a3, t3
    mul a1, a3, t5
    mulh t3, s3, t4
    mul a4, a3, t2
    mulhu t3, t3, t5
    mul t0, t1, t3
    mulh a2, a3, s2
    li   t4, 32768
    mul t1, a3, a2
    add a4, t1, t5
    clmulr s2, s2, t1
    mulh t3, t4, t4
    or t5, t5, t5
    sub s3, t3, t1
    mulh s3, t1, s2
    clmulh s2, t0, s3
    clmulh t0, t3, s3
    mulh s3, t1, a4
    xor t5, a1, s2
    clmulr a1, t5, s2
    andi t6, t1, 4
    bnez t6, 173f
    mulhsu t0, t2, a1
    clmulh t1, s3, a4
    clmul t1, s2, s2
173:
    li   t4, 32768
    andi t6, s2, 1
    bnez t6, 174f
    mulh t0, a4, s2
174:
    li   t2, 3
    mulhu t4, a3, s3
    add a2, a3, t5
    add a4, t4, t2
    mulh t1, t4, a1
    clmulh a4, t5, t4
    sltu t5, a3, a1
    sub a3, a2, s2
    mulhsu a4, a4, t0
    mulhu t3, s2, t4
    clmul t2, t1, t4
    mul s3, s3, s2
    slt s3, t0, t2
    mulhsu t1, t0, t1
    mulhu t4, t5, a1
    clmulh t1, t1, t0
    mulhsu a1, s3, s2
    mulh a1, t4, a4
    mul t5, t2, t0
    andi t6, t2, 16
    bnez t6, 175f
    mulh t5, a4, t5
    clmulh a4, t1, t5
175:
    clmulh t0, a2, a1
    li   a1, -2
    clmul t4, a1, t5
    clmulh t2, a2, s2
    mulhsu t0, a1, t4
    xor t4, a3, a1
    clmulh s2, t4, t3
    li   t0, 3
    mulh a3, t2, t4
    clmul a1, a3, a3
    clmulr t0, s3, s3
    andi t6, a1, 32
    bnez t6, 176f
    mulhu a1, a4, a4
    clmulh a1, a2, t5
176:
    mulh t1, s2, a1
    mulh a2, s2, a3
    li   a3, 32768
    clmul t1, a2, a1
    mulh t4, s2, a3
    mulhsu t2, s3, a1
    li   t2, 0
    xor t4, t4, s2
    li   t5, 32768
    mulhsu t3, a1, t4
    andi t6, a4, 8
    bnez t6, 177f
    clmulh t1, s3, a1
    mulhu a2, s2, a4
177:
    mulhsu t3, a4, a3
    clmulr t5, t5, t2
    mulh a4, s3, t4
    clmulh t0, t0, t4
    li   t5, 3
    mulhu s2, t5, t5
    mulhsu t4, t2, t1
    mulhsu a3, t0, t4
    mulhsu a1, t4, s3
    slt t3, s2, s3
    andi t6, a4, 2
    bnez t6, 178f
    clmulr t3, a4, t4
    clmulr a3, a4, a2
    mulhsu a1, s3, t1
178:
    mulhu a4, t5, t0
    li   a4, 2147483647
    andi t6, t4, 4
    bnez t6, 179f
    mulhu t5, t3, t5
179:
    mulh t3, a4, a2
    clmulr a1, t5, a2
    mul t3, a3, t5
    mul t2, a4, a3
    mul t3, t3, a3
    clmul a3, t1, t0
    mulhu t3, t1, s3
    li   t0, 3
    sltu t4, t2, a1
    clmulr s2, s3, a3
    clmul t3, t3, a2
    mulh a1, s3, a1
    li   t1, 32768
    mulh t2, a2, t5
    mulh a4, a1, t1
    clmulr t0, s3, a4
    mul s2, t2, t3
    sltu t4, a4, a2
    li   a4, -2
    clmulh a2, t4, t5
    mulh t1, a1, a4
    slt a2, a2, t4
    xor t4, s3, t4
    mulhsu t4, t2, a2
    clmulr a3, t3, s2
    mul a1, t1, t2
    mulh t4, a3, s2
    sra s2, a3, t0
    mulh a3, s3, t2
    sltu t0, a2, s2
    xor s2, t3, a1
    sll t1, t4, t4
    li   t5, 0
    mul s3, t1, t5
    clmulh s3, s2, t2
    mulh a2, t4, a3
    mulhsu t2, t0, t1
    clmulr t2, t5, a1
    mulhu t3, t0, t5
    li   s2, 0
    andi t6, t2, 16
    bnez t6, 180f
    mulhsu a1, a3, t0
    clmulh a3, s2, a4
180:
    sll s3, a2, a2
    mulh t1, t0, t3
    clmul t3, t4, s2
    mulhu a4, t5, a4
    li   a4, 2147483647
    add a1, t0, t1
    sll t4, t3, a4
    mul a2, t0, t0
    mulh s3, t5, t2
    mulh t5, t2, t2
    sra a4, t4, t4
    sra s3, t0, t3
    clmulr t5, t4, t0
    or t1, t2, a1
    mulhsu a3, a1, t3
    clmulh t2, t4, a1
    clmul a3, t4, a4
    mulhu s3, a4, a4
    li   t4, -1
    li   a4, 2147483647
    mulh a4, t0, a1
    clmulr t1, t4, t3
    clmulh t5, t3, a4
    andi t6, s3, 1
    bnez t6, 181f
    clmulr t0, a3, a4
    clmulh t5, a3, s2
    clmulr a3, a1, t1
181:
    mul t3, t1, a3
    mulh s3, s3, a3
    andi t6, a2, 32
    bnez t6, 182f
    clmulh t5, a4, a3
182:
    clmul t0, a1, s2
    mulh t3, t3, a2
    andi t6, a2, 8
    bnez t6, 183f
    clmulh t1, a1, t2
183:
    andi t6, t5, 1
    bnez t6, 184f
    mulhsu t3, a1, t0
    mulhsu t0, s3, t2
184:
    li   a1, -2147483648
    mul t4, s2, t1
    li   a1, 65536
    clmulh a3, t5, a1
    li   a1, 2147483647
    mulhu t1, a1, t1
    add t5, t4, t3
    or a4, t1, a1
    clmulr t0, t2, a2
    mulh a2, t3, t4
    li   t2, 65535
    mulh a4, s2, a4
    clmulr s2, a1, a1
    sub t0, t5, a4
    slt t2, t0, a2
    li   t3, 1
    sltu t1, a3, a3
    li   s2, 2147483647
    mulhsu a4, t0, t5
    add t1, t5, t3
    andi t6, t3, 2
    bnez t6, 185f
    clmul t3, t0, s3
    mulh t0, t2, a3
185:
    mulhsu t1, s3, a4
    mulh a3, t4, a3
    andi t6, t0, 8
    bnez t6, 186f
    clmulh a4, t5, t0
    mulh t0, a2, t2
    mulhu a2, t3, a3
186:
    clmulr a3, t1, a3
    clmulh a3, a3, t4
    clmulh a1, t5, a3
    clmulh s2, t2, a3
    mulh s3, t4, a2
    clmulr t2, s2, a2
    li   t3, 0
    clmulr t0, t2, a3
    slt a2, s2, t5
    clmulh s2, t1, s2
    andi t6, a1, 8
    bnez t6, 187f
    mul a3, t5, a2
    mul t1, a2, a1
187:
    li   a3, 65536
    sltu t4, s2, t1
    mulh t1, a1, t3
    sltu a3, a2, t2
    mulhsu s2, t5, t2
    andi t6, t3, 1
    bnez t6, 188f
    mul a4, a4, a3
    clmulh t2, s3, a1
188:
    clmul t3, t2, t5
    mulh t3, t0, t0
    mulhsu s2, a4, t4
    clmulh t5, t5, t1
    mulhsu t3, a2, a4
    xor t2, t0, t1
    clmulh s3, a3, a2
    clmulr a2, t1, s3
    mulhu t5, t0, t4
    sub t5, t1, s2
    clmul s3, a2, a2
    mulhsu t4, s3, a3
    sra t3, a4, s3
    andi t6, t2, 2
    bnez t6, 189f
    clmulh t3, a1, t1
189:
    li   a1, 2147483647
    mulh a4, t5, t3
    mulhsu s3, a4, a4
    sll s3, t1, t4
    sll t3, t3, t0
    li   t0, 2147483647
    sltu a1, t4, s2
    andi t6, t2, 8
    bnez t6, 190f
    clmulh a1, a4, s2
    mulhsu s2, a2, t5
    mulhsu t5, t5, t3
190:
    sub t3, t1, t1
    mulhsu a2, t5, t2
    mulhsu s2, a4, t2
    add s2, a3, t5
    sltu a4, s3, t3
    clmulr a2, t4, a1
    clmul t1, a3, a1
    andi t6, a3, 16
    bnez t6, 191f
    mulh t1, t4, t4
191:
    clmulh a3, a1, t2
    andi t6, t0, 16
    bnez t6, 192f
    clmulh a2, t5, t3
192:
    li   a2, -2147483648
    clmul s2, t4, t0
    andi t6, t1, 4
    bnez t6, 193f
    clmul a2, a2, t0
    clmulr t5, t1, t4
193:
    li   t1, 1
    clmulr t0, t2, t5
    slt a1, t0, t4
    mulhsu s3, a1, t3
    andi t6, a2, 4
    bnez t6, 194f
    mulhu t2, a4, t2
    mulh t1, s3, a1
    mulh a4, t3, t5
194:
    clmulh a3, s2, t1
    li   t2, 1
    clmulh t0, a2, t2
    clmulh t5, s2, s2
    clmulh t0, a3, t3
    mulhu t2, t5, a3
    mulhu a3, a1, t5
    or t1, s3, t1
    andi t6, a2, 32
    bnez t6, 195f
    clmul t2, t2, a1
    mulhsu a1, s2, a3
    mulh a1, a4, t0
195:
    mulh a4, s3, t3
    li   s2, 65536
    li   t2, -2
    mulhsu t4, s2, t5
    mulh a4, t0, t3
    clmul s3, a3, a4
    xor t4, s3, t1
    andi t6, t0, 32
    bnez t6, 196f
    clmulr a2, s2, t1
    clmul a2, a1, t1
196:
    li   a4, 32768
    mulhu t5, s3, t5
    mul t5, s2, t3
    slt a1, t0, t5
    li   s2, -2
    mulhu t2, s2, s3
    andi t6, t0, 8
    bnez t6, 197f
    mulh t4, t5, t5
    clmulh t1, t4, a4
197:
    clmulh s3, t5, t2
    or s3, t4, t3
    mul t0, t4, t4
    li   t1, -2
    clmulh a2, s3, s3
    clmulh t4, t5, a1
    mulhsu s2, t2, a2
    andi t6, s2, 2
    bnez t6, 198f
    clmulr t1, s2, s2
    mulhsu a1, t4, t1
198:
    mul a2, t2, t1
    li   a1, 2147483647
    mul a1, a3, t3
    clmul s2, t3, t5
    mulh t0, t5, t3
    mulhu a2, t5, t4
    clmulh a3, t4, s3
    andi t6, a2, 2
    bnez t6, 199f
    clmulr s2, t5, t2
    clmulr t2, a3, a4
199:
    sub s2, t4, t3
    andi t6, t3, 2
    bnez t6, 1100f
    clmulh t2, t5, t0
1100:
    mulh a4, t1, t0
    mul s3, t5, a2
    mulhu s2, t0, a2
    mulhu t5, s2, a1
    li   t3, -2
    clmulr t0, t2, a1
    andi t6, t1, 1
    bnez t6, 1101f
    mulh t1, a3, s2
    clmulr a3, t2, t4
    mul a2, t3, t4
1101:
    xor a2, t4, t3
    mulhsu t4, a2, a2
    mulhsu t1, s2, a4
    clmulr a1, t5, t0
    clmulr a4, a1, t1
    mulhu t2, t1, t0
    andi t6, t3, 8
    bnez t6, 1102f
    mulh t3, a4, t4
1102:
    or s3, s3, t2
    add s3, t2, s2
    li   s3, 65535
    mulhu s3, s3, s2
    andi t6, t0, 4
    bnez t6, 1103f
    mul s2, t2, t4
    mul a1, t3, s3
1103:
    li   a4, -2
    mul t1, a4, s2
    sub a4, t1, a3
    clmulh a2, a3, a1
    xor s2, t2, t0
    mulhu a2, s2, t2
    li   t5, 2147483647
    or t5, t1, a2
    li   t0, 65536
    sra t3, s3, a1
    sra t2, s3, t5
    mulhu a1, t0, t3
    mulhu t3, t4, t3
    mul s2, t0, a3
    mulh t3, s3, a1
    andi t6, a3, 4
    bnez t6, 1104f
    clmul t4, a2, s3
1104:
    li   s3, 3
    li   t1, 2147483647
    mulhu t4, t5, s2
    clmul t2, a2, t3
    mulhu a1, t0, a4
    clmulh t0, t3, a4
    li   a4, 0
    sll t1, s2, t3
    li   t4, 1
    sltu a1, t2, a4
    clmulr t3, t2, t3
    xor s2, a3, t2
    li   t2, 0
    sub a3, a2, a4
    mulhsu t1, t0, s3
    mulhsu a1, t4, t5
    li   t5, 2147483647
    mulhsu t1, t4, a4
    clmulh s3, t2, a3
    clmulr t4, a4, s2
    andi t6, a1, 16
    bnez t6, 1105f
    mulhu a4, t0, a2
    clmul t3, t3, a1
1105:
    mulhu t5, t5, t5
    mul t5, t2, t5
    mulhsu a3, a3, a4
    sll a2, t4, s3
    add s2, t2, a4
    mulhu t3, s2, a1
    clmulh t4, t0, s2
    andi t6, a1, 16
    bnez t6, 1106f
    clmul t4, t2, s3
    clmulh s3, t1, a4
    mulh t2, t1, t4
1106:
    mulh t5, s3, t5
    sll t4, t0, t2
    li   t0, 65536
    clmul s2, a2, s3
    li   a1, -2
    clmulr t3, a2, t0
    clmulh a4, a4, t2
    andi t6, s2, 4
    bnez t6, 1107f
    mul a3, t2, s3
1107:
    mul t4, t3, s3
    clmulh t5, a1, t3
    andi t6, a4, 2
    bnez t6, 1108f
    mulh t1, a4, s2
    mul s3, t1, a1
    mulhsu t2, t0, s2
1108:
    andi t6, a1, 8
    bnez t6, 1109f
    mulh t0, s2, a3
1109:
    li   t0, -2147483648
    or t4, s2, t0
    mulh a4, t5, t1
    andi t6, a4, 4
    bnez t6, 1110f
    clmul a2, t5, t4
    mulh a4, t3, s2
1110:
    clmulh t4, t3, t1
    clmulr t0, a2, t0
    mul t5, t3, s2
    sub t0, t3, t0
    clmulr s2, a1, a1
    mul a1, t1, a2
    sltu t1, t0, t3
    sub a2, s3, t1
    mulhsu t1, t4, a2
    clmulr a3, t1, t0
    clmulr a1, t2, t4
    mulhsu t3, t0, s3
    mulhsu a4, a1, t4
    sub t3, a3, a2
    clmulr s2, t0, s3
    mulh t1, a3, t0
    add a2, a2, t0
    mul t1, a4, t2
    mulhsu t2, a2, a4
    sltu a2, t1, a1
    sra a1, a3, a3
    li   t3, 65535
    slt s3, a1, t0
    clmulr a4, a1, a3
    andi t6, t4, 8
    bnez t6, 1111f
    mulh t0, a2, t2
    clmul t5, a1, t2
1111:
    mulh t5, t0, t5
    clmulh t4, a2, a2
    clmulh t1, a3, t0
    mulhu s2, a1, a3
    clmulr s2, t3, a3
    clmulr t2, s2, a2
    sll t2, s2, a3
    clmul t2, t5, t1
    sub t5, t4, t1
    or t4, t1, s3
    andi t6, t4, 1
    bnez t6, 1112f
    clmulh t1, t2, a2
    mulhsu a1, a4, t2
    mul s2, s3, a3
1112:
    clmul a4, a1, t5
    add a2, a2, a2
    mul t3, s3, t3
    mulhsu t4, a2, t4
    slt a1, a3, a3
    add a4, a1, a2
    add a1, t0, t4
    mulh a2, t2, t2
    li   a1, 1
    mul t4, t4, a2
    clmul t0, a3, s2
    slt t0, s2, t3
    andi t6, t3, 4
    bnez t6, 1113f
    mulhu t2, t5, t2
1113:
    mulh t2, s3, a2
    sltu t0, t1, t0
    mulh s3, a3, s2
    mul a3, a4, t5
    clmul t4, a1, s2
    slt a2, s3, s2
    clmulr a4, t0, t3
    clmulh t3, s2, t2
    add a4, a4, t1
    slt a3, a1, t0
    andi t6, a1, 32
    bnez t6, 1114f
    mul t1, a4, t2
    mulh a3, t5, t3
1114:
    clmul t2, t2, a4
    clmul a1, a4, s2
    sll a1, t5, t5
    li   a4, 65536
    mulh a3, s3, a3
    mul s3, t4, s2
    sll t4, t3, t1
    andi t6, t4, 4
    bnez t6, 1115f
    clmul t3, s2, a3
    clmulr t3, t1, t4
1115:
    mul t1, t0, s2
    li   t3, -2147483648
    sltu t0, a1, a2
    li   a2, 65535
    andi t6, a2, 1
    bnez t6, 1116f
    clmul t5, a3, t2
    clmul t1, s3, t2
1116:
    sub t2, s2, a4
    li   s2, 65535
    clmul s3, a1, a1
    slt t3, a2, t0
    sltu t3, t1, t0
    clmulr a2, t0, t0
    mulh t0, a3, t5
    mul t4, t3, a3
    sub t3, s2, t2
    mul t0, t4, t0
    andi t6, t2, 1
    bnez t6, 1117f
    clmul t0, t5, t4
    mul a1, a2, t2
1117:
    mulh s3, a3, t1
    sll a2, t1, a1
    sra t4, a2, t4
    li   a1, -2
    mul a2, a1, t2
    sra t1, a4, a3
    li   t1, 65535
    mulh s2, s3, t4
    mul t3, t2, t3
    andi t6, t1, 8
    bnez t6, 1118f
    clmulh a1, a2, t2
1118:
    sltu a2, a3, t2
    andi t6, t5, 8
    bnez t6, 1119f
    clmulr t4, t2, a4
    clmul t2, a3, a4
1119:
    andi t6, t3, 8
    bnez t6, 1120f
    mulh s2, s3, t1
    clmulr a4, a2, a3
1120:
    mul s3, t5, t1
    sra a2, t2, a2
    add s3, t5, s3
    li   a4, -2147483648
    andi t6, s2, 16
    bnez t6, 1121f
    mulh s2, a3, t2
1121:
    andi t6, s3, 4
    bnez t6, 1122f
    mulhu s2, t4, s2
    clmulh a1, t0, a3
1122:
    andi t6, t4, 1
    bnez t6, 1123f
    mulhsu a4, a4, a2
    clmulh t4, a1, a2
    mulh a4, a3, a2
1123:
    slt a1, t1, t5
    andi t6, t3, 16
    bnez t6, 1124f
    mul a4, t2, t5
    clmulh t5, t2, s2
    mulhu a3, s2, a3
1124:
    clmul a4, t1, t4
    mulhu t5, a2, t3
    li   a1, 65535
    li   t2, 32768
    slt a3, t2, t4
    sltu t5, a3, s3
    clmul t4, s3, t0
    mulhu a1, s2, s3
    mulhu t2, t1, t2
    or a4, t5, t0
    mulh a3, t5, a3
    mulhu a3, t3, t3
    mulhsu t5, t3, t3
    mulhu a1, t4, t2
    clmul t3, t4, t0
    clmulh t4, s3, t1
    mulh a4, s3, s2
    sltu a1, s3, t3
    add t0, a3, a3
    sll t0, t0, t2
    clmulh t5, t0, s2
    andi t6, a2, 4
    bnez t6, 1125f
    mulhu t5, a3, s2
1125:
    clmul s3, t2, a1
    mul a1, t3, s3
    clmul t5, t3, t4
    mulhu t4, t2, a4
    mul t3, t2, a3
    mulh a3, a2, t5
    sub s3, t5, a1
    mul t3, t1, s2
    andi t6, a3, 1
    bnez t6, 1126f
    mul a1, t2, t1
    mul t5, s3, t0
    clmulr t2, t5, t5
1126:
    mulhsu a4, t5, t2
    mulhsu t3, a2, a2
    mulh a3, s3, s2
    clmulh s3, a1, a2
    sltu a2, t5, a4
    clmulh s3, a2, a4
    mul s3, a1, t5
    clmul a3, s2, t3
    li   s2, -2
    mulhu a4, t5, a2
    mulhu a3, t5, t3
    mulhu a3, t0, a2
    sra a4, t4, t1
    andi t6, t1, 2
    bnez t6, 1127f
    clmulh t1, t0, a2
    clmulr t5, t2, t3
    clmul s3, t1, a3
1127:
    mulhsu a1, a1, a3
    sub t4, a3, t2
    mul t0, t5, a4
    sra a2, t3, t3
    mulhsu a2, t2, a2
    clmul t1, a3, a2
    clmulr a2, a3, t4
    clmul t5, s2, t5
    clmul t1, t0, t4
    mulhsu t5, s2, a1
    sra t5, t1, t4
    mul a1, t2, t3
    clmulr a2, t4, t2
    add a4, a2, a4
    mulhu t0, a2, a3
    mul a2, t1, a1
    slt t2, a4, t3
    or t2, t4, t2
    clmulr t3, s3, a3
    slt a1, a4, a4
    sll t1, a3, t5
    clmulr s3, t0, t4
    mulhsu s3, t4, t1
    clmulr t2, s3, t4
    mulhu a2, a1, s3
    add t0, a1, t0
    sra t1, t0, a2
    mul t5, t4, a4
    mulh t1, a1, s3
    clmulh a4, a4, t4
    mul s2, t4, a2
    clmulh t5, t3, t2
    mul s3, a1, t0
    sltu t0, t0, a3
    clmul t5, s2, t0
    sub a2, a2, t1
    mulh t2, a1, t3
    mul t4, a3, t0
    clmulh a1, t2, t5
    mulhsu t4, t1, t0
    clmulh a1, t0, t1
    andi t6, t1, 2
    bnez t6, 1128f
    mulhsu t5, a3, t4
    mulhu a2, a1, a2
1128:
    andi t6, t2, 8
    bnez t6, 1129f
    mulh a2, t2, t3
    mulhsu a2, t2, t5
    mul a3, a4, t4
1129:
    clmulh a1, t5, t5
    add t5, a3, a2
    mulhu a2, t3, t4
    li   t5, 2147483647
    mulhu t5, a1, s3
    sub t0, a1, a4
    clmulr s3, t3, s2
    sub s3, t4, t4
    clmulh a3, t3, a1
    mulhu t5, s2, t0
    add t0, s3, s2
    li   s2, 32768
    clmulr t5, a1, t1
    mul t3, s3, a1
    mulh t4, t0, a1
    clmulh t1, s3, t5
    mul a4, t2, t5
    sll t5, t1, t5
    sra t2, t1, t1
    sll t5, s2, a3
    clmul t4, t0, t4
    mulhsu t1, s3, a1
    sll a1, t1, s3
    mulh t1, a2, t5
    clmul t0, a4, t4
    mulhsu t2, s2, a1
    clmul a2, s3, t0
    mulhu a1, t1, t4
    andi t6, t2, 4
    bnez t6, 1130f
    mulh a1, s2, a2
    clmulr a4, t1, a1
    mulhu t1, t3, t5
1130:
    li   a2, 3
    li   t0, 0
    clmul t0, t4, t0
    mulhsu t5, a1, a1
    sltu a3, t3, s2
    mulh a2, t0, s2
    andi t6, s3, 32
    bnez t6, 1131f
    mulh a3, t3, a1
1131:
    add a3, a1, t2
    mulh t1, a1, a1
    clmulr t3, a3, a3
    mulh t4, a1, t0
    li   s2, 65535
    clmul a1, s2, t3
    li   a2, 0
    andi t6, s3, 2
    bnez t6, 1132f
    clmul t3, t2, t1
    mulhu a4, t0, a3
1132:
    mulhu s3, a4, t2
    mulh a3, t0, t4
    sub t0, t5, a4
    mulh a3, t5, s2
    mul t4, a2, t3
    mul t3, a1, a2
    clmul t4, a1, t5
    clmul a1, t5, t3
    mulh t2, t5, s2
    mul a3, t2, s2
    slt s3, a3, s2
    xor t3, t0, a1
    mulh s3, t4, s2
    mulhsu t5, t5, a3
    xor a2, t0, a4
    mulhu t0, a3, t5
    mulhu a3, t2, t5
    mulh t4, s3, s2
    mulh a2, a3, a4
    sra s3, a3, t4
    clmulh a3, a4, t1
    xor a4, s3, a4
    mulh a1, s3, s2
    clmulh t0, a3, t1
    or t4, s2, t5
    clmul t4, t3, a4
    sub s3, s2, t1
    clmul a1, t3, a2
    li   a3, 32768
    li   s3, 65535
    clmulh t1, a3, a1
    add a1, s2, s2
    sub a1, a4, a2
    sltu t3, a1, s2
    mulh t4, t1, a2
    mulhsu a1, a2, t4
    li   s3, -2147483648
    clmul a1, a4, t1
    mulh s2, t2, s3
    mulhu t4, t0, a4
    clmulh t2, t1, a2
    sra t2, t1, a3
    mulh t0, t3, t5
    clmul t2, t3, a4
    clmul t4, t2, a3
    clmulr t4, a1, s3
    sub t5, t4, a1
    li   a2, 1
    slt a3, a4, a4
    xor a3, t2, t4
    sltu t0, a1, t4
    sltu t2, t5, t5
    clmulh a2, t0, a3
    mulhsu a2, t1, t4
    andi t6, a4, 16
    bnez t6, 1133f
    mul a1, t0, t1
1133:
    mul t5, t4, t2
    or a1, a2, a3
    mulh a1, t3, a3
    clmul t0, t4, a4
    mulhu t4, t5, a2
    mulhu a3, a2, t3
    clmul s3, t5, a4
    clmulh t0, a1, t2
    li   t5, -2
    clmulr a4, t4, a4
    mul t4, s3, s3
    clmulh a2, s2, t3
    mulh t3, t0, t2
    slt a1, s2, a1
    sra t3, s2, s2
    mul a4, t3, s3
    li   t3, 65536
    clmul s3, t1, a3
    mulhsu t0, a1, t5
    slt t1, a1, t4
    clmul t3, a1, t4
    clmulr s2, t0, s2
    andi t6, t4, 2
    bnez t6, 1134f
    mul a1, a4, a2
1134:
    clmulh t0, s2, t5
    or t4, t0, t4
    sll t0, t5, t1
    mulhsu a1, s3, t5
    mul a3, t1, t1
    sra s3, a4, a1
    mulh t3, a2, a1
    sra a2, t0, t3
    andi t6, t1, 8
    bnez t6, 1135f
    mulhsu t3, t0, t1
1135:
    mulhsu s2, t5, t4
    mulh a2, t1, s2
    xor s2, t0, t1
    clmul a3, t5, a1
    mulh t1, t5, a4
    clmul a2, t4, t3
    mulh t5, t1, t1
    sra t3, a4, t5
    xor a2, t5, a3
    clmul t0, a3, t1
    li   t1, -1
    mulhu t1, t5, a2
    li   t0, 32768
    mulhu a3, s3, t4
    mulh a4, a1, t1
    sltu s3, t2, a1
    mul t2, a1, t1
    mulhu t3, t5, a2
    add t1, a2, a2
    clmul a2, t2, t2
    mulh t3, s2, a3
    andi t6, t3, 1
    bnez t6, 1136f
    mulhu a4, t5, a2
1136:
    li   t4, 1
    sltu a1, a3, a3
    clmulh a3, a2, t3
    mulh t1, t1, a3
    mulhu a1, t3, t2
    clmul t3, t4, s2
    clmul t0, t3, a4
    mulhsu a4, t3, t3
    mul a2, t3, s3
    or s2, s2, t2
    mulhsu t5, t1, t1
    mulhu t0, a1, a2
    mulhu t0, a4, a3
    andi t6, a3, 4
    bnez t6, 1137f
    clmulh t1, t3, a4
    mulhsu t2, a3, t2
    clmulr a3, t5, s2
1137:
    clmul t3, t1, a4
    andi t6, s3, 32
    bnez t6, 1138f
    mul s3, a4, t1
    mul a3, a4, a4
    mulhu t5, a3, t0
1138:
    mulh t1, t4, a4
    clmulh t4, a1, a3
    clmul t0, t1, t1
    mulh t4, s2, a2
    mul t1, a3, a2
    add s2, t0, t5
    mul a1, a3, a4
    mul t2, t5, a4
    xor t0, a3, t0
    li   s3, 3
    mulh a2, s2, t4
    clmulh t5, t3, a1
    or s2, t5, t3
    xor t3, s3, t2
    andi t6, s3, 16
    bnez t6, 1139f
    mulhu t5, t5, t4
    mul a4, t4, t5
    clmulh t2, t5, s2
1139:
    mulh t0, a4, a2
    slt t0, t5, t0
    add t3, s2, a2
    or s2, a1, t5
    mulhsu a3, a1, s2
    andi t6, t5, 32
    bnez t6, 1140f
    mulhsu t0, a1, t2
    clmul a1, a3, a4
1140:
    sra a2, s3, a1
    andi t6, s2, 16
    bnez t6, 1141f
    mul a2, s2, s3
1141:
    mulh t3, t2, a3
    clmul t1, a4, t3
    clmul s3, s3, a2
    sltu t2, a4, t0
    clmulr t4, a2, t2
    andi t6, t0, 32
    bnez t6, 1142f
    mulh t5, a1, t1
1142:
    mulhu a1, a4, t4
    clmulh a2, t5, s2
    addi s1, s1, -1
    bnez s1, outer
    li   a0, EXIT
    li   t0, 1
    sw   t0, 0(a0)
9:  j    9b
