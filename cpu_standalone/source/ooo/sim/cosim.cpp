// Lock-step co-simulation: every RTL commit is checked against the ISS.
// MMIO load values and volatile CSR reads (mcycle, mip) are taken from the RTL.
#include "../../tools/iss/rv_iss.h"
#include <cstdio>
#include <cstdlib>

static rv::Iss *iss = nullptr;
static long long n_commit = 0, n_trap = 0, n_mmio = 0;
static int errors = 0;

static bool volatile_csr(uint32_t insn) {
    uint32_t op = insn & 0x7f, f3 = (insn >> 12) & 7, csr = insn >> 20;
    if (op != 0x73 || f3 == 0 || f3 == 4) return false;
    return csr == 0xb00 || csr == 0xb80 || csr == 0xc00 || csr == 0xc80 || csr == 0x344;
}

extern "C" int cosim_init(const char *hex) {
    iss = new rv::Iss();
    if (!iss->load_hex(hex)) { fprintf(stderr, "COSIM: cannot load %s\n", hex); return 1; }
    iss->allow_div = getenv("COSIM_DIV") != nullptr;
    iss->allow_mulh = true;
    return 0;
}

// The testbench injects read errors for RAM in [lo, hi) (o2_mem_shim).
extern "C" void cosim_bus_error(int lo, int hi) {
    iss->berr_lo = (uint32_t)lo;
    iss->berr_hi = (uint32_t)hi;
}

static void report(const char *what, uint32_t rpc, uint32_t rinsn, uint32_t ipc, uint32_t iinsn,
                   int rwr, int rrd, uint32_t rval, int iwr, int ird, uint32_t ival) {
    fprintf(stderr, "COSIM MISMATCH (%s) at commit %lld\n  RTL: pc=%08x insn=%08x wr=%d rd=%d val=%08x\n  ISS: pc=%08x insn=%08x wr=%d rd=%d val=%08x\n",
            what, n_commit, rpc, rinsn, rwr, rrd, rval, ipc, iinsn, iwr, ird, ival);
    errors++;
}

extern "C" int cosim_commit(int pc, int insn, int wr, int rd, int val, int csr_old) {
    uint32_t upc = (uint32_t)pc, uinsn = (uint32_t)insn, uval = (uint32_t)val;
    n_commit++;
    if (iss->pc != upc) {
        report("pc", upc, uinsn, iss->pc, iss->fetch(iss->pc), wr, rd, uval, 0, 0, 0);
        return 1;
    }
    rv::Rec r = iss->step();
    if (r.trap) {
        report("iss-trap", upc, uinsn, r.pc, r.insn, wr, rd, uval, 0, 0, iss->mcause);
        return 1;
    }
    if (r.insn != uinsn) { report("insn", upc, uinsn, r.pc, r.insn, wr, rd, uval, r.wr, r.rd, r.wdata); return 1; }
    uint32_t op = uinsn & 0x7f;
    bool is_csr = op == 0x73 && ((uinsn >> 12) & 7) != 0;
    if (is_csr) uval = (uint32_t)csr_old;
    if (r.cls == rv::C_LOAD && r.mmio) {
        n_mmio++;
        if (r.wr) { iss->x[r.rd] = uval; r.wdata = uval; }
    }
    if (volatile_csr(uinsn) && r.wr) { iss->x[r.rd] = uval; r.wdata = uval; }
    if ((int)r.wr != (wr ? 1 : 0) || (r.wr && (int)r.rd != rd) || (r.wr && r.wdata != uval)) {
        report("wb", upc, uinsn, r.pc, r.insn, wr, rd, uval, r.wr, r.rd, r.wdata);
        return 1;
    }
    return 0;
}

extern "C" int cosim_trap(int cause, int epc, int is_irq) {
    uint32_t ucause = (uint32_t)cause, uepc = (uint32_t)epc;
    n_trap++;
    if (iss->pc != uepc) {
        fprintf(stderr, "COSIM TRAP PC MISMATCH: RTL epc=%08x cause=%08x  ISS pc=%08x\n", uepc, ucause, iss->pc);
        errors++; return 1;
    }
    if (is_irq) { iss->take_interrupt(ucause); return 0; }
    rv::Rec r = iss->step();
    if (!r.trap || iss->mcause != ucause) {
        fprintf(stderr, "COSIM TRAP MISMATCH: RTL epc=%08x cause=%08x  ISS trap=%d cause=%08x insn=%08x\n",
                uepc, ucause, r.trap, iss->mcause, r.insn);
        errors++; return 1;
    }
    return 0;
}

extern "C" void cosim_final() {
    fprintf(stderr, "COSIM_SUMMARY commits=%lld traps=%lld mmio_loads=%lld errors=%d\n", n_commit, n_trap, n_mmio, errors);
}
