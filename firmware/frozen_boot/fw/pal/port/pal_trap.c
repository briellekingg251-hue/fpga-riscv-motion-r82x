/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Machine trap handler of the PAL image.
 *
 * Misaligned LH/LHU/LW/SH/SW are emulated byte-wise (the s80 core traps on
 * them; a few SDLPAL resource parsers dereference unaligned WORD pointers).
 * Any other trap is reported on UART and on screen, then the CPU halts.
 */
#include <stdint.h>
#include "../../soc.h"
#include "pal_port.h"

static uint32_t read_csr_mcause(void) { uint32_t v; __asm__ volatile("csrr %0, mcause" : "=r"(v)); return v; }
static uint32_t read_csr_mepc(void) { uint32_t v; __asm__ volatile("csrr %0, mepc" : "=r"(v)); return v; }
static uint32_t read_csr_mtval(void) { uint32_t v; __asm__ volatile("csrr %0, mtval" : "=r"(v)); return v; }
static void write_csr_mepc(uint32_t v) { __asm__ volatile("csrw mepc, %0" :: "r"(v)); }

static uint32_t misaligned_count;

uint32_t pal_trap_misaligned_count(void) { return misaligned_count; }

static void put_hex(uint32_t v)
{
    for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789abcdef"[(v >> i) & 15u]);
}

static void halt(const char *what, uint32_t cause, uint32_t epc, uint32_t tval)
{
    uart_puts("\nPAL FATAL ");
    uart_puts(what);
    uart_puts(" mcause=");
    put_hex(cause);
    uart_puts(" mepc=");
    put_hex(epc);
    uart_puts(" mtval=");
    put_hex(tval);
    uart_puts("\n");
    pal_port_fatal_screen(what, epc);
    for (;;) { }
}

void pal_trap_handler(uint32_t *frame)
{
    uint32_t cause = read_csr_mcause(), epc = read_csr_mepc(), tval = read_csr_mtval();
    uint32_t insn, f3, rd, rs2;
    volatile const uint8_t *p = (volatile const uint8_t *)(uintptr_t)tval;
    if (cause != 4 && cause != 6) halt("TRAP", cause, epc, tval);
    insn = *(const uint32_t *)(uintptr_t)epc;
    f3 = (insn >> 12) & 7u;
    rd = (insn >> 7) & 31u;
    rs2 = (insn >> 20) & 31u;
    if (tval < 0x80000000u || tval >= 0x84000000u) halt("MISALIGNED NON-RAM", cause, epc, tval);
    if (cause == 4 && (insn & 0x7fu) == 0x03u) {
        uint32_t v;
        if (f3 == 1 || f3 == 5) {
            v = (uint32_t)p[0] | (uint32_t)p[1] << 8;
            if (f3 == 1) v = (uint32_t)(int32_t)(int16_t)v;
        } else if (f3 == 2) {
            v = (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
        } else halt("BAD MISALIGNED LOAD", cause, epc, tval);
        if (rd) frame[rd] = v;
    } else if (cause == 6 && (insn & 0x7fu) == 0x23u) {
        uint32_t v = rs2 ? frame[rs2] : 0;
        volatile uint8_t *q = (volatile uint8_t *)(uintptr_t)tval;
        if (f3 == 1) { q[0] = (uint8_t)v; q[1] = (uint8_t)(v >> 8); }
        else if (f3 == 2) { q[0] = (uint8_t)v; q[1] = (uint8_t)(v >> 8); q[2] = (uint8_t)(v >> 16); q[3] = (uint8_t)(v >> 24); }
        else halt("BAD MISALIGNED STORE", cause, epc, tval);
    } else halt("MISALIGNED DECODE", cause, epc, tval);
    ++misaligned_count;
    write_csr_mepc(epc + 4);
}
