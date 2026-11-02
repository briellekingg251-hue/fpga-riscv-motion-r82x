// Minimal RV32IM + Zbc + Zicsr (M-mode) instruction-set simulator.
// Header-only: used by the standalone performance model and by the
// Verilator DPI co-simulation checker. Memory map follows soc_config.vh.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace rv {

enum Cls : uint8_t {
    C_ALU = 0, C_BRANCH, C_JAL, C_JALR, C_LOAD, C_STORE, C_MUL, C_MULH,
    C_DIV, C_CLMUL, C_CSR, C_SYS, C_FENCE, C_ILLEGAL
};

struct Rec {
    uint32_t pc, insn, next_pc;
    uint8_t rd, rs1, rs2;
    bool wr, use1, use2;
    Cls cls;
    bool taken;          // control transfer taken (branch/jal/jalr)
    uint32_t maddr;      // effective address for load/store
    uint8_t msize;       // bytes
    bool mmio;           // access outside RAM
    uint32_t wdata;      // value written to rd (if wr)
    uint32_t sdata;      // store data (aligned to address lane)
    bool trap;           // instruction trapped (no architectural effect besides trap)
};

static inline uint32_t clmul_lo(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    for (int i = 0; i < 32; i++) if ((b >> i) & 1) r ^= a << i;
    return r;
}
static inline uint32_t clmul_hi(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    for (int i = 1; i < 32; i++) if ((b >> i) & 1) r ^= a >> (32 - i);
    return r;
}
static inline uint32_t clmul_r(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    for (int i = 0; i < 32; i++) if ((b >> i) & 1) r ^= a >> (31 - i);
    return r;
}

class Iss {
public:
    static constexpr uint32_t RAM_BASE = 0x80000000u;
    static constexpr uint32_t RAM_BYTES = 0x20000u;
    static constexpr uint32_t UART_BASE = 0x10000000u;
    static constexpr uint32_t GPIO_BASE = 0x10001000u;
    static constexpr uint32_t TIMER_BASE = 0x10002000u;
    static constexpr uint32_t PERF_BASE = 0x10003000u;
    static constexpr uint32_t BEU_BASE = 0x10004000u;
    static constexpr uint32_t EXIT_BASE = 0x20000000u;

    uint32_t x[32] = {0};
    uint32_t pc = RAM_BASE;
    std::vector<uint8_t> ram;
    uint64_t instret = 0;
    uint64_t timer = 0;          // mtime value (driven by caller)
    uint64_t mtimecmp = ~0ull;
    bool exited = false;
    uint32_t exit_code = 0;
    std::string uart;
    bool allow_div = true;       // RV32M divide (else illegal)
    bool allow_mulh = true;
    // CSRs
    uint32_t mstatus = 0x1800u, mie = 0, mtvec = 0, mscratch = 0, mepc = 0, mcause = 0, mtval = 0, mip_sw = 0;
    uint64_t mcycle = 0;
    // MMIO load override (co-simulation): if set, the next MMIO load returns this.
    bool mmio_override_valid = false;
    uint32_t mmio_override_value = 0;
    // Injected bus errors (co-simulation): RAM in [berr_lo, berr_hi) answers
    // reads with an error, so fetches and loads there take access faults.
    // Stores still update the model; the core reports them imprecisely.
    uint32_t berr_lo = 0, berr_hi = 0;

    Iss() : ram(RAM_BYTES, 0xa5) {}

    bool load_hex(const char *path) {
        FILE *f = fopen(path, "r");
        if (!f) return false;
        char line[64];
        uint32_t addr = 0;
        while (fgets(line, sizeof line, f)) {
            if (line[0] == '@') { addr = (uint32_t)strtoul(line + 1, nullptr, 16) * 4; continue; }
            if (line[0] == '/' || line[0] == '\n' || line[0] == '\r') continue;
            uint32_t w = (uint32_t)strtoul(line, nullptr, 16);
            if (addr + 4 <= RAM_BYTES) memcpy(&ram[addr], &w, 4);
            addr += 4;
        }
        fclose(f);
        return true;
    }

    bool in_ram(uint32_t a, uint32_t n) const {
        return a >= RAM_BASE && (uint64_t)a + n <= (uint64_t)RAM_BASE + RAM_BYTES;
    }
    bool bus_error(uint32_t a) const { return a >= berr_lo && a < berr_hi; }
    // Word accesses below RAM go to the SoC MMIO router (o2_soc.sv and
    // p2_peripherals.sv); everything it does not decode answers with an error.
    bool mmio_ok(uint32_t a, bool write, uint32_t be) const {
        uint32_t w = a & ~3u, page = w & ~0xfffu, off = w & 0xfffu;
        if (a >= RAM_BASE) return false;
        if (page == UART_BASE) return off == 0 || off == 8 || (off == 4 && !write);
        if (page == GPIO_BASE) return off == 0;
        if (page == TIMER_BASE) return off <= 0x14;
        if (page == PERF_BASE || page == BEU_BASE) return true;
        if (w == EXIT_BASE) return write && be == 0xf;
        return false;
    }
    uint32_t fetch(uint32_t a) const {
        uint32_t w;
        if (!in_ram(a, 4)) return 0;
        memcpy(&w, &ram[a - RAM_BASE], 4);
        return w;
    }
    uint32_t mmio_read(uint32_t a) {
        if (mmio_override_valid) { mmio_override_valid = false; return mmio_override_value; }
        uint32_t w = a & ~3u;
        if (w == UART_BASE + 4) return 0;             // not busy
        if (w == TIMER_BASE + 0) return (uint32_t)timer;
        if (w == TIMER_BASE + 4) return (uint32_t)(timer >> 32);
        if (w == TIMER_BASE + 8) return (uint32_t)mtimecmp;
        if (w == TIMER_BASE + 12) return (uint32_t)(mtimecmp >> 32);
        return 0;
    }
    void mmio_write(uint32_t a, uint32_t v, uint32_t be) {
        uint32_t w = a & ~3u;
        if (w == UART_BASE && (be & 1)) uart.push_back((char)(v & 0xff));
        if (w == EXIT_BASE) { exited = true; exit_code = v; }
        if (w == TIMER_BASE + 8) mtimecmp = (mtimecmp & 0xffffffff00000000ull) | v;
        if (w == TIMER_BASE + 12) mtimecmp = (mtimecmp & 0xffffffffull) | ((uint64_t)v << 32);
    }

    bool csr_read(uint32_t a, uint32_t &v) {
        switch (a) {
            case 0x300: v = mstatus; return true;
            case 0x301: v = 0x40000100u; return true; // RV32I plus Zmmul; no full M.
            case 0x304: v = mie; return true;
            case 0x305: v = mtvec; return true;
            case 0x340: v = mscratch; return true;
            case 0x341: v = mepc; return true;
            case 0x342: v = mcause; return true;
            case 0x343: v = mtval; return true;
            case 0x344: v = mip_sw | ((timer >= mtimecmp) ? 0x80u : 0u); return true;
            case 0xb00: case 0xc00: v = (uint32_t)mcycle; return true;
            case 0xb80: case 0xc80: v = (uint32_t)(mcycle >> 32); return true;
            case 0xb02: case 0xc02: v = (uint32_t)instret; return true;
            case 0xb82: case 0xc82: v = (uint32_t)(instret >> 32); return true;
            case 0xf11: case 0xf12: case 0xf13: case 0xf14: v = 0; return true;
            default: return false;
        }
    }
    void csr_write(uint32_t a, uint32_t v) {
        switch (a) {
            case 0x300: mstatus = (v & 0x88u) | 0x1800u; break;
            case 0x304: mie = v & 0x888u; break;
            case 0x305: mtvec = v & ~3u; break;
            case 0x340: mscratch = v; break;
            case 0x341: mepc = v & ~3u; break;
            case 0x342: mcause = v; break;
            case 0x343: mtval = v; break;
            case 0x344: break;            // mip is read-only (reflects interrupt inputs)
            case 0xb00: mcycle = (mcycle & 0xffffffff00000000ull) | v; break;
            case 0xb80: mcycle = (mcycle & 0xffffffffull) | (uint64_t(v) << 32); break;
            case 0xb02: instret = (instret & 0xffffffff00000000ull) | v; break;
            case 0xb82: instret = (instret & 0xffffffffull) | (uint64_t(v) << 32); break;
            default: break;
        }
    }

    void take_interrupt(uint32_t cause) {
        mepc = pc; mcause = cause; mtval = 0;
        uint32_t mie_bit = (mstatus >> 3) & 1;
        mstatus = (mstatus & ~0x88u) | (mie_bit << 7) | 0x1800u;
        pc = mtvec;
    }
    void take_trap(Rec &r, uint32_t cause, uint32_t tval) {
        r.trap = true; r.wr = false;
        mepc = r.pc; mcause = cause; mtval = tval;
        uint32_t mie_bit = (mstatus >> 3) & 1;
        mstatus = (mstatus & ~0x88u) | (mie_bit << 7) | 0x1800u;
        r.next_pc = mtvec;
    }

    // Execute one instruction. Returns record.
    Rec step() {
        Rec r{};
        r.pc = pc;
        uint32_t i = fetch(pc);
        r.insn = i;
        uint32_t op = i & 0x7f, rd = (i >> 7) & 31, f3 = (i >> 12) & 7, rs1 = (i >> 15) & 31,
                 rs2 = (i >> 20) & 31, f7 = i >> 25;
        r.rd = rd; r.rs1 = rs1; r.rs2 = rs2;
        int32_t imm_i = (int32_t)i >> 20;
        int32_t imm_s = ((int32_t)i >> 25 << 5) | (int32_t)rd;
        int32_t imm_b = (((int32_t)i >> 31) << 12) | (((i >> 7) & 1) << 11) | (((i >> 25) & 63) << 5) | (((i >> 8) & 15) << 1);
        int32_t imm_j = (((int32_t)i >> 31) << 20) | (((i >> 12) & 255) << 12) | (((i >> 20) & 1) << 11) | (((i >> 21) & 1023) << 1);
        uint32_t a = x[rs1], b = x[rs2];
        uint32_t res = 0;
        r.next_pc = pc + 4;
        r.cls = C_ALU;
        bool illegal = false;
        bool instret_written = false;
        if (!in_ram(pc, 4) || (pc & 3) || bus_error(pc)) {
            take_trap(r, (pc & 3) ? 0 : 1, pc);
            pc = r.next_pc; return r;
        }
        switch (op) {
            case 0x37: r.wr = true; res = i & 0xfffff000u; break;
            case 0x17: r.wr = true; res = pc + (i & 0xfffff000u); break;
            case 0x6f: r.wr = true; res = pc + 4; r.next_pc = pc + imm_j; r.cls = C_JAL; r.taken = true;
                if (r.next_pc & 3) { uint32_t t = r.next_pc; r.next_pc = pc + 4; take_trap(r, 0, t); pc = r.next_pc; return r; }
                break;
            case 0x67:
                if (f3) { illegal = true; break; }
                r.wr = true; r.use1 = true; res = pc + 4; r.next_pc = (a + imm_i) & ~1u; r.cls = C_JALR; r.taken = true;
                if (r.next_pc & 3) { uint32_t t = r.next_pc; r.next_pc = pc + 4; take_trap(r, 0, t); pc = r.next_pc; return r; }
                break;
            case 0x63: {
                r.use1 = r.use2 = true; r.cls = C_BRANCH; bool t = false;
                switch (f3) {
                    case 0: t = a == b; break; case 1: t = a != b; break;
                    case 4: t = (int32_t)a < (int32_t)b; break; case 5: t = (int32_t)a >= (int32_t)b; break;
                    case 6: t = a < b; break; case 7: t = a >= b; break;
                    default: illegal = true;
                }
                r.taken = t; if (t) r.next_pc = pc + imm_b;
                if (!illegal && (r.next_pc & 3)) { uint32_t tg = r.next_pc; r.next_pc = pc + 4; take_trap(r, 0, tg); pc = r.next_pc; return r; }
                break;
            }
            case 0x03: {
                r.use1 = true; r.cls = C_LOAD; r.wr = true;
                uint32_t ea = a + imm_i; r.maddr = ea;
                uint32_t n = (f3 & 3) == 0 ? 1 : (f3 & 3) == 1 ? 2 : 4; r.msize = (uint8_t)n;
                if (f3 == 3 || f3 > 5) { illegal = true; break; }
                if (ea & (n - 1)) { take_trap(r, 4, ea); pc = r.next_pc; return r; }
                uint32_t v;
                if (in_ram(ea, n) && !bus_error(ea)) { v = 0; memcpy(&v, &ram[ea - RAM_BASE], n); }
                else if (mmio_ok(ea, false, 0xf)) {
                    r.mmio = true; uint32_t w = mmio_read(ea); v = w >> ((ea & 3) * 8);
                } else { take_trap(r, 5, ea); pc = r.next_pc; return r; }
                switch (f3) {
                    case 0: res = (uint32_t)(int32_t)(int8_t)v; break;
                    case 1: res = (uint32_t)(int32_t)(int16_t)v; break;
                    case 2: res = v; break;
                    case 4: res = v & 0xff; break;
                    case 5: res = v & 0xffff; break;
                }
                break;
            }
            case 0x23: {
                r.use1 = r.use2 = true; r.cls = C_STORE;
                uint32_t ea = a + imm_s; r.maddr = ea;
                uint32_t n = f3 == 0 ? 1 : f3 == 1 ? 2 : 4; r.msize = (uint8_t)n;
                if (f3 > 2) { illegal = true; break; }
                if (ea & (n - 1)) { take_trap(r, 6, ea); pc = r.next_pc; return r; }
                r.sdata = b << ((ea & 3) * 8);
                uint32_t be = ((1u << n) - 1) << (ea & 3);
                if (in_ram(ea, n)) memcpy(&ram[ea - RAM_BASE], &b, n);
                else if (mmio_ok(ea, true, be)) { r.mmio = true; mmio_write(ea, r.sdata, be); }
                else { take_trap(r, 7, ea); pc = r.next_pc; return r; }
                break;
            }
            case 0x13: {
                r.use1 = true; r.wr = true;
                uint32_t sh = (uint32_t)imm_i & 31;
                switch (f3) {
                    case 0: res = a + imm_i; break;
                    case 2: res = (int32_t)a < imm_i; break;
                    case 3: res = a < (uint32_t)imm_i; break;
                    case 4: res = a ^ imm_i; break;
                    case 6: res = a | imm_i; break;
                    case 7: res = a & imm_i; break;
                    case 1: if (f7) illegal = true; res = a << sh; break;
                    case 5: if (f7 == 0) res = a >> sh; else if (f7 == 0x20) res = (uint32_t)((int32_t)a >> sh); else illegal = true; break;
                }
                break;
            }
            case 0x33: {
                r.use1 = r.use2 = true; r.wr = true;
                if (f7 == 0x01) {
                    if (f3 < 4) {
                        r.cls = f3 == 0 ? C_MUL : C_MULH;
                        if (f3 && !allow_mulh) { illegal = true; break; }
                        int64_t sa = (int32_t)a, sb = (int32_t)b; uint64_t ua = a, ub = b;
                        switch (f3) {
                            case 0: res = a * b; break;
                            case 1: res = (uint32_t)((sa * sb) >> 32); break;
                            case 2: res = (uint32_t)((int64_t)(sa * (int64_t)ub) >> 32); break;
                            case 3: res = (uint32_t)((ua * ub) >> 32); break;
                        }
                    } else {
                        r.cls = C_DIV;
                        if (!allow_div) { illegal = true; break; }
                        switch (f3) {
                            case 4: res = b == 0 ? ~0u : (a == 0x80000000u && b == ~0u) ? a : (uint32_t)((int32_t)a / (int32_t)b); break;
                            case 5: res = b == 0 ? ~0u : a / b; break;
                            case 6: res = b == 0 ? a : (a == 0x80000000u && b == ~0u) ? 0 : (uint32_t)((int32_t)a % (int32_t)b); break;
                            case 7: res = b == 0 ? a : a % b; break;
                        }
                    }
                } else if (f7 == 0x05 && (f3 == 1 || f3 == 2 || f3 == 3)) {
                    r.cls = C_CLMUL;
                    res = f3 == 1 ? clmul_lo(a, b) : f3 == 3 ? clmul_hi(a, b) : clmul_r(a, b);
                } else if (f7 == 0 || (f7 == 0x20 && (f3 == 0 || f3 == 5))) {
                    switch (f3) {
                        case 0: res = f7 ? a - b : a + b; break;
                        case 1: res = a << (b & 31); break;
                        case 2: res = (int32_t)a < (int32_t)b; break;
                        case 3: res = a < b; break;
                        case 4: res = a ^ b; break;
                        case 5: res = f7 ? (uint32_t)((int32_t)a >> (b & 31)) : a >> (b & 31); break;
                        case 6: res = a | b; break;
                        case 7: res = a & b; break;
                    }
                } else illegal = true;
                break;
            }
            case 0x0f: r.cls = C_FENCE; if (f3 > 1) illegal = true; break;
            case 0x73: {
                if (f3 == 0) {
                    r.cls = C_SYS;
                    if (i == 0x00000073u) { take_trap(r, 11, 0); pc = r.next_pc; return r; }
                    if (i == 0x00100073u) { take_trap(r, 3, pc); pc = r.next_pc; return r; }
                    if (i == 0x30200073u) {
                        uint32_t mpie = (mstatus >> 7) & 1;
                        mstatus = (mstatus & ~0x8u) | (mpie << 3) | 0x1880u;
                        r.next_pc = mepc; r.taken = true; break;
                    }
                    if (i == 0x10500073u) break; // wfi
                    illegal = true; break;
                }
                if (f3 == 4) { illegal = true; break; }
                r.cls = C_CSR; r.wr = true;
                uint32_t csr = i >> 20, old;
                uint32_t src = (f3 & 4) ? rs1 : a;
                r.use1 = !(f3 & 4);
                bool wr_csr = (f3 & 3) == 1 || rs1 != 0;
                if (!csr_read(csr, old) || (wr_csr && (csr >> 10) == 3)) { illegal = true; break; }
                uint32_t nv = (f3 & 3) == 1 ? src : (f3 & 3) == 2 ? (old | src) : (old & ~src);
                if (wr_csr) {
                    csr_write(csr, nv);
                    instret_written = csr == 0xb02 || csr == 0xb82;
                }
                res = old;
                break;
            }
            default: illegal = true;
        }
        if (illegal) { take_trap(r, 2, i); pc = r.next_pc; return r; }
        if (r.wr && rd != 0) { x[rd] = res; r.wdata = res; } else { r.wr = false; r.wdata = 0; }
        x[0] = 0;
        pc = r.next_pc;
        if (!instret_written) instret++;
        return r;
    }
};

} // namespace rv
