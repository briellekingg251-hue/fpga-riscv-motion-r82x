# gen_md_test.py [seed] -> md_test.S
# Memory-dependence speculation stress: stores whose address depends on a slow
# chain (load + MUL), younger loads with an early base that may or may not
# alias them (issued speculatively), and many data-dependent branches between
# them so branch tags are allocated, resolved, killed and reused while
# speculative loads wait in the load queue. Cosim checks every result.
import random
import sys

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
random.seed(seed)
R = ["t0", "t1", "t2", "t3", "t4", "a1", "a2", "a3", "a4", "a5"]
L = []
A = L.append
lbl = [0]


def newl():
    lbl[0] += 1
    return f"L{lbl[0]}"


A("    .equ EXIT, 0x20000000")
A("    .section .text.start, \"ax\", @progbits")
A("    .globl _start")
A("_start:")
A("    la   sp, __stack_top")
A("    la   s0, buf")
A("    li   s1, 12             /* outer iterations */")
A("    li   s2, 0x1234567      /* LFSR */")
for r in R:
    A(f"    li   {r}, {random.randrange(-2**31, 2**31)}")
A("outer:")
# LFSR step (s2), used for data-dependent control and addresses
A("    slli t5, s2, 13")
A("    xor  s2, s2, t5")
A("    srli t5, s2, 17")
A("    xor  s2, s2, t5")
A("    slli t5, s2, 5")
A("    xor  s2, s2, t5")
for blk in range(400):
    # slow store address: load an index word, multiply, mask to the buffer
    A(f"    lw   s3, {4 * random.randrange(0, 8)}(s0)")
    A("    xor  s3, s3, s2")
    A(f"    li   s4, {random.choice([3, 5, 7, 9, 11])}")
    for _ in range(random.randrange(1, 4)):       # 1-3 dependent multiplies
        A("    mul  s3, s3, s4")
    A("    andi s3, s3, 28")
    A("    add  s3, s3, s0")
    # branches between the slow chain and the store
    for _ in range(random.randrange(1, 4)):
        lb = newl()
        A(f"    andi t5, s2, {1 << random.randrange(0, 11)}")
        A(f"    {random.choice(['beqz', 'bnez'])} t5, {lb}")
        A(f"    addi {random.choice(R)}, {random.choice(R)}, {random.randrange(-100, 100)}")
        A(f"{lb}:")
    op = random.choice(["sw", "sw", "sh", "sb"])
    A(f"    {op}   {random.choice(R)}, 0(s3)")
    # an older fast branch that resolves while the younger load executes
    for _ in range(random.randrange(1, 3)):
        lb = newl()
        A(f"    andi t5, s2, {1 << random.randrange(0, 11)}")
        A(f"    {random.choice(['beqz', 'bnez'])} t5, {lb}")
        A(f"    addi {random.choice(R)}, {random.choice(R)}, 1")
        A(f"{lb}:")
    # younger loads with an early base: maybe aliasing the store
    for _ in range(random.randrange(1, 3)):
        lop, sz = random.choice([("lw", 4), ("lw", 4), ("lhu", 2), ("lb", 1)])
        A(f"    {lop}   {random.choice(R)}, {random.randrange(0, 32, sz)}(s0)")
    # younger fast branches (tags reused, often mispredicted) before the store issues
    for _ in range(random.randrange(2, 5)):
        lb = newl()
        A("    srli t6, s2, 3")
        A("    xor  s2, s2, t6")
        A(f"    andi t5, s2, {1 << random.randrange(0, 11)}")
        A(f"    {random.choice(['beqz', 'bnez'])} t5, {lb}")
        A(f"    xor  {random.choice(R)}, {random.choice(R)}, {random.choice(R)}")
        A(f"{lb}:")
    # occasionally refresh the index words from register values
    if random.random() < 0.3:
        A(f"    sw   {random.choice(R)}, {4 * random.randrange(0, 8)}(s0)")
A("    addi s1, s1, -1")
A("    bnez s1, outer")
A("    li   a0, EXIT")
A("    li   t0, 1")
A("    sw   t0, 0(a0)")
A("9:  j    9b")
A("    .data")
A("    .align 5")
A("buf: .word 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12")
open("md_test.S", "w").write("\n".join(L) + "\n")
print("lines", len(L))
