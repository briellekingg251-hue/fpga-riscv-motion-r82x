# Generates fwd_test.S: random mixes of byte/half/word stores and loads on a
# 32-byte buffer (heavy store-to-load overlap), with data-dependent branches
# so that stores and loads are also killed on mispredicts. The lock-step
# co-simulation checks every load value; exit code 1 = completed.
import random
import sys
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 20261011)
L = []
A = L.append
A("    .equ EXIT, 0x20000000")
A("    .section .text.start, \"ax\", @progbits")
A("    .globl _start")
A("_start:")
A("    la   sp, __stack_top")
A("    la   s0, buf")
A("    li   s1, 6            /* outer iterations */")
A("    li   t0, 0x12345678")
A("    li   t1, 0x9abcdef1")
A("    li   t2, 0x0f1e2d3c")
A("    li   t3, 0x55aa33cc")
A("outer:")
regs = ["t0", "t1", "t2", "t3", "t4", "t5", "a1", "a2", "a3", "a4"]
lbl = 0
for i in range(2500):
    r = random.random()
    rd = random.choice(regs); rs = random.choice(regs)
    if r < 0.06:
        # burst: several overlapping stores to one word, then loads of it
        w = random.randrange(0, 32, 4)
        for _ in range(random.randrange(2, 5)):
            op, sz = random.choice([("sb", 1), ("sh", 2), ("sw", 4)])
            A(f"    {op}   {random.choice(regs)}, {w + random.randrange(0, 4, sz)}(s0)")
        for _ in range(random.randrange(1, 3)):
            op, sz = random.choice([("lb", 1), ("lhu", 2), ("lw", 4), ("lw", 4)])
            A(f"    {op}   {random.choice(regs)}, {w + random.randrange(0, 4, sz)}(s0)")
    elif r < 0.30:
        op, sz = random.choice([("sb", 1), ("sh", 2), ("sw", 4), ("sw", 4)])
        off = random.randrange(0, 32, sz)
        A(f"    {op}   {rs}, {off}(s0)")
    elif r < 0.62:
        op, sz = random.choice([("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4), ("lw", 4)])
        off = random.randrange(0, 32, sz)
        A(f"    {op}   {rd}, {off}(s0)")
    elif r < 0.92:
        op = random.choice(["add", "xor", "sub", "or", "sll", "srl"])
        A(f"    {op}  {rd}, {rd}, {rs}")
        if random.random() < 0.3:
            A(f"    addi {rd}, {rd}, {random.randrange(-2048, 2047)}")
    else:
        # data-dependent forward branch over a few stores/loads
        lbl += 1
        A(f"    andi t6, {rs}, {1 << random.randrange(0, 5)}")
        A(f"    beqz t6, 1{lbl}f")
        for _ in range(random.randrange(1, 4)):
            op, sz = random.choice([("sb", 1), ("sh", 2), ("sw", 4), ("lw", 4), ("lbu", 1)])
            off = random.randrange(0, 32, sz)
            reg = random.choice(regs)
            A(f"    {op}   {reg}, {off}(s0)")
        A(f"1{lbl}:")
        lbl_fix = True
A("    addi s1, s1, -1")
A("    bnez s1, outer")
A("    li   a0, EXIT")
A("    li   t0, 1")
A("    sw   t0, 0(a0)")
A("9:  j    9b")
A("    .data")
A("    .align 5")
A("buf: .space 64")
out = "\n".join(L) + "\n"
# local numeric labels must be < 2^31 and unique per scope; use 1NNNN form
open("fwd_test.S", "w").write(out)
print("ops", len(L))
