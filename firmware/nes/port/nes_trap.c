/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Machine trap handler.  The core traps on misaligned LH/LHU/LW/SH/SW; those
 * are emulated byte-wise inside the DDR window and counted (the build is
 * -mstrict-align, so a non-zero count points at a cast in upstream code).
 * Any other trap is reported on UART and on screen, then the CPU halts. */
#include <stdint.h>
#include "soc.h"
#include "nes_board.h"

#define CAUSE_LOAD_MISALIGNED  4u
#define CAUSE_STORE_MISALIGNED 6u
#define OPCODE_LOAD  0x03u
#define OPCODE_STORE 0x23u
#define DDR_BEGIN 0x80000000u
#define DDR_END   0x83f00000u

static uint32_t misaligned;

uint32_t nes_trap_misaligned(void) { return misaligned; }

static uint32_t csr_mcause(void) { uint32_t v; __asm__ volatile("csrr %0, mcause" : "=r"(v)); return v; }
static uint32_t csr_mepc(void) { uint32_t v; __asm__ volatile("csrr %0, mepc" : "=r"(v)); return v; }
static uint32_t csr_mtval(void) { uint32_t v; __asm__ volatile("csrr %0, mtval" : "=r"(v)); return v; }

static void put_hex(uint32_t v)
{
    for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789abcdef"[(v >> i) & 15u]);
}

static void __attribute__((noreturn)) halt(const char *what, uint32_t cause, uint32_t epc, uint32_t tval)
{
    uart_puts("\nNES FATAL ");
    uart_puts(what);
    uart_puts(" mcause="); put_hex(cause);
    uart_puts(" mepc=");   put_hex(epc);
    uart_puts(" mtval=");  put_hex(tval);
    uart_puts("\n");
    nes_video_message("CPU TRAP - PRESS BOARD RESET", what);
    for (;;) {}
}

static uint32_t load_bytes(volatile const uint8_t *p, uint32_t f3)
{
    if (f3 == 1u || f3 == 5u) {
        uint32_t v = (uint32_t)p[0] | (uint32_t)p[1] << 8;
        return f3 == 1u ? (uint32_t)(int32_t)(int16_t)v : v;
    }
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

void nes_trap_handler(uint32_t *frame)
{
    uint32_t cause = csr_mcause(), epc = csr_mepc(), tval = csr_mtval();
    if (cause != CAUSE_LOAD_MISALIGNED && cause != CAUSE_STORE_MISALIGNED) halt("TRAP", cause, epc, tval);
    if (tval < DDR_BEGIN || tval > DDR_END - 4u) halt("MISALIGNED OUTSIDE DDR", cause, epc, tval);
    uint32_t insn = *(const uint32_t *)(uintptr_t)epc;
    uint32_t f3 = (insn >> 12) & 7u, rd = (insn >> 7) & 31u, rs2 = (insn >> 20) & 31u;
    if (cause == CAUSE_LOAD_MISALIGNED && (insn & 0x7fu) == OPCODE_LOAD && (f3 == 1u || f3 == 2u || f3 == 5u)) {
        uint32_t v = load_bytes((volatile const uint8_t *)(uintptr_t)tval, f3);
        if (rd) frame[rd] = v;
    } else if (cause == CAUSE_STORE_MISALIGNED && (insn & 0x7fu) == OPCODE_STORE && (f3 == 1u || f3 == 2u)) {
        uint32_t v = rs2 ? frame[rs2] : 0u;
        volatile uint8_t *q = (volatile uint8_t *)(uintptr_t)tval;
        for (uint32_t i = 0; i < (f3 == 1u ? 2u : 4u); ++i) q[i] = (uint8_t)(v >> (8u * i));
    } else {
        halt("MISALIGNED DECODE", cause, epc, tval);
    }
    ++misaligned;
    __asm__ volatile("csrw mepc, %0" :: "r"(epc + 4u));
}
