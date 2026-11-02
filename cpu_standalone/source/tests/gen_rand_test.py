# gen_rand_test.py [seed] -> rand_test.S
# Random RV32I + Zmmul + Zbc program for lock-step co-simulation: ALU / MUL /
# CLMUL ops, all load/store sizes on a small buffer, data-dependent forward
# branches, short counted loops, calls through JAL/JALR, CSR reads. The
# co-simulation checks every committed result; exit code 1 = completed.
import random
import sys

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
random.seed(seed)
R = ["t0", "t1", "t2", "t3", "t4", "t5", "a1", "a2", "a3", "a4", "a5", "s2", "s3", "s4", "s5"]
ALU_RR = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and",
          "mul", "mulh", "mulhsu", "mulhu", "clmul", "clmulr", "clmulh"]
ALU_RI = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_RI = ["slli", "srli", "srai"]
LD = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4)]
ST = [("sb", 1), ("sh", 2), ("sw", 4)]
EDGE = [0, 1, -1, 2, 0x7fffffff, -0x80000000, 0x80, 0xff, 0x7fff, 0x8000, 0xffff, 31, 32, -2048, 2047]

out = []
A = out.append
lbl = [0]


def newl():
    lbl[0] += 1
    return f"L{lbl[0]}"


def rnd_op(depth=0):
    x = random.random()
    rd, ra, rb = random.choice(R), random.choice(R), random.choice(R)
    if x < 0.30:
        A(f"    {random.choice(ALU_RR)} {rd}, {ra}, {rb}")
    elif x < 0.45:
        A(f"    {random.choice(ALU_RI)} {rd}, {ra}, {random.randrange(-2048, 2048)}")
    elif x < 0.50:
        A(f"    {random.choice(SH_RI)} {rd}, {ra}, {random.randrange(0, 32)}")
    elif x < 0.53:
        A(f"    lui  {rd}, {random.randrange(0, 1 << 20)}")
    elif x < 0.55:
        A(f"    li   {rd}, {random.choice(EDGE)}")
    elif x < 0.70:
        op, sz = random.choice(LD)
        A(f"    {op}   {rd}, {random.randrange(0, 64, sz)}(s0)")
    elif x < 0.82:
        op, sz = random.choice(ST)
        A(f"    {op}   {ra}, {random.randrange(0, 64, sz)}(s0)")
    elif x < 0.90 and depth < 2:
        # forward data-dependent branch
        L = newl()
        br = random.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"])
        A(f"    {br}  {ra}, {rb}, {L}")
        for _ in range(random.randrange(1, 5)):
            rnd_op(depth + 1)
        A(f"{L}:")
    elif x < 0.94 and depth < 1:
        # short counted loop
        L = newl()
        A(f"    li   s6, {random.randrange(1, 6)}")
        A(f"{L}:")
        for _ in range(random.randrange(2, 7)):
            rnd_op(depth + 1)
        A("    addi s6, s6, -1")
        A(f"    bnez s6, {L}")
    elif x < 0.97 and depth < 1:
        A(f"    call sub{random.randrange(0, 4)}")
    elif x < 0.985:
        A(f"    csrr {rd}, {random.choice(['mscratch', 'minstret', 'mcycle', 'mstatus'])}")
    else:
        A(f"    csrw mscratch, {ra}")


A("    .equ EXIT, 0x20000000")
A("    .section .text.start, \"ax\", @progbits")
A("    .globl _start")
A("_start:")
A("    la   sp, __stack_top")
A("    la   s0, buf")
A("    li   s1, 4")
for r in R:
    A(f"    li   {r}, {random.choice(EDGE) if random.random() < 0.4 else random.randrange(-2**31, 2**31)}")
A("outer:")
for _ in range(1200):
    rnd_op()
A("    addi s1, s1, -1")
A("    bnez s1, outer")
A("    li   a0, EXIT")
A("    li   t0, 1")
A("    sw   t0, 0(a0)")
A("9:  j    9b")
# subroutines: a few ops, maybe an indirect call, return through ra (s7 keeps the caller's ra)
for k in range(4):
    A(f"sub{k}:")
    for _ in range(random.randrange(2, 8)):
        x = random.random()
        rd, ra, rb = random.choice(R), random.choice(R), random.choice(R)
        if x < 0.6:
            A(f"    {random.choice(ALU_RR)} {rd}, {ra}, {rb}")
        else:
            op, sz = random.choice(LD)
            A(f"    {op}   {rd}, {random.randrange(0, 64, sz)}(s0)")
    if k < 3 and random.random() < 0.5:
        A("    mv   s7, ra")
        A("    la   s8, sub3")
        A("    jalr ra, 0(s8)")
        A("    mv   ra, s7")
    A("    ret")
A("    .data")
A("    .align 6")
A("buf: .space 128")
open("rand_test.S", "w").write("\n".join(out) + "\n")
print("lines", len(out))
