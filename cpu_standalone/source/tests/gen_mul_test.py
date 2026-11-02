# gen_mul_test.py [seed]: random MUL/MULH/MULHSU/MULHU/CLMUL/CLMULR/CLMULH with
# dependent chains, edge operands and mispredicted branches (cosim checks values)
import random, sys
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 7)
ops = ["mul", "mulh", "mulhsu", "mulhu", "clmul", "clmulr", "clmulh"]
edge = [0, 1, -1, 0x7fffffff, -0x80000000, 0xffff, 0x10000, 0x8000, -2, 3]
regs = ["t0", "t1", "t2", "t3", "t4", "t5", "a1", "a2", "a3", "a4", "s2", "s3"]
L = ["    .equ EXIT, 0x20000000", "    .section .text.start, \"ax\", @progbits", "    .globl _start", "_start:",
     "    la   sp, __stack_top", "    li   s1, 3"]
for r in regs:
    L.append(f"    li   {r}, {random.choice(edge) if random.random() < 0.5 else random.randrange(-2**31, 2**31)}")
L.append("outer:")
lbl = 0
for i in range(1500):
    x = random.random()
    rd, ra, rb = random.choice(regs), random.choice(regs), random.choice(regs)
    if x < 0.55:
        L.append(f"    {random.choice(ops)} {rd}, {ra}, {rb}")
    elif x < 0.80:
        L.append(f"    {random.choice(['add', 'xor', 'sub', 'sll', 'sra', 'sltu', 'slt', 'or'])} {rd}, {ra}, {rb}")
    elif x < 0.90:
        L.append(f"    li   {rd}, {random.choice(edge)}")
    else:
        lbl += 1
        L.append(f"    andi t6, {ra}, {1 << random.randrange(0, 6)}")
        L.append(f"    bnez t6, 1{lbl}f")
        for _ in range(random.randrange(1, 4)):
            L.append(f"    {random.choice(ops)} {random.choice(regs)}, {random.choice(regs)}, {random.choice(regs)}")
        L.append(f"1{lbl}:")
L += ["    addi s1, s1, -1", "    bnez s1, outer", "    li   a0, EXIT", "    li   t0, 1", "    sw   t0, 0(a0)", "9:  j    9b"]
open("mul_test.S", "w").write("\n".join(L) + "\n")
