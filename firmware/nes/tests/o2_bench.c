/* Headless NES benchmark for the O2 RTL testbench (ooo/sim/o2_tb.sv).
 *
 * Runs the real InfoNES core and the real per-line texel diff on an embedded
 * cartridge with a scripted joypad, as fast as the core allows: no pacing,
 * no frame skip, every frame rendered.  Each changed texel is sent as one
 * 32-bit MMIO store to GPIO_OUT, the same uncached store path the GPU command
 * FIFO uses on the board.  Per-frame cycles come from the platform timer
 * (one tick per CPU clock) and are reported on the UART; the run ends with a
 * store to the testbench exit register.
 *
 * Frames below BENCH_WARMUP are excluded from the statistics (title screen). */
#include <stdint.h>
#include <string.h>
#include "InfoNES.h"
#include "InfoNES_System.h"
#include "nes_port.h"

#define MMIO32(a)      (*(volatile uint32_t *)(uintptr_t)(a))
#define UART_DATA      MMIO32(0x10000000u)
#define UART_STATUS    MMIO32(0x10000004u)
#define GPIO_OUT       MMIO32(0x10001000u)
#define TIMER_LO       MMIO32(0x10002000u)
#define EXIT_REG       MMIO32(0x20000000u)
#ifndef BENCH_FRAMES
#define BENCH_FRAMES   360u
#endif
#define BENCH_WARMUP   60u
#define HIST_BUCKET    250000u   /* cycles per histogram bucket */
#define HIST_BUCKETS   16u

extern const uint8_t bench_rom[];
extern const uint32_t bench_rom_size;

WORD NesPalette[64];
static nes_rom_t rom;
static uint32_t frame, frame_start, texels, frame_texels;
static uint32_t sum, worst, best = 0xffffffffu, hist[HIST_BUCKETS];
static uint32_t texel_sum, texel_worst;

static void putc_(char c) { while (UART_STATUS & 1u) {} UART_DATA = (uint8_t)c; }
static void puts_(const char *s) { while (*s) { if (*s == '\n') putc_('\r'); putc_(*s++); } }
static void putu(uint32_t v)
{
    char b[11]; int n = 0;
    do { b[n++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (n) putc_(b[--n]);
}

static void sink(uint32_t word) { GPIO_OUT = word; ++texels; }

int InfoNES_Menu(void) { return frame >= BENCH_FRAMES ? -1 : 0; }

int InfoNES_ReadRom(const char *name)
{
    (void)name;
    memcpy(&NesHeader, rom.header, sizeof NesHeader);
    memset(SRAM, 0, SRAM_SIZE);
    ROM = (BYTE *)rom.prg;
    VROM = (BYTE *)rom.chr;
    return 0;
}

void InfoNES_ReleaseRom(void) {}
void InfoNES_LoadFrame(void) {}

void InfoNES_LoadLine(void)
{
    unsigned line = PPU_Scanline;
    if (line >= NES_VIEW_TOP && line < NES_VIEW_TOP + NES_VIEW_LINES)
        nes_frame_upload_line(&WorkFrame[line * NES_VIEW_W], line - NES_VIEW_TOP, sink);
}

static void account(void)
{
    uint32_t now = TIMER_LO, spent = now - frame_start;
    frame_start = now;
    frame_texels = texels - frame_texels;
    if (frame >= BENCH_WARMUP) {
        sum += spent;
        if (spent > worst) worst = spent;
        if (spent < best) best = spent;
        ++hist[spent / HIST_BUCKET < HIST_BUCKETS ? spent / HIST_BUCKET : HIST_BUCKETS - 1u];
        texel_sum += frame_texels;
        if (frame_texels > texel_worst) texel_worst = frame_texels;
    }
    frame_texels = texels;
}

/* Scripted joypad: START twice (title, game select), then hold RIGHT with
 * periodic A (jump) and B (run/fire). */
void InfoNES_PadState(DWORD *pad1, DWORD *pad2, DWORD *system)
{
    uint32_t bits = 0;
    account();
    ++frame;
    if ((frame >= 30 && frame < 36) || (frame >= 90 && frame < 96)) bits |= NES_PAD_START;
    if (frame >= 120) bits |= NES_PAD_RIGHT | ((frame / 20u) & 1u ? NES_PAD_B : 0u);
    if (frame >= 120 && frame % 45u < 12u) bits |= NES_PAD_A;
    *pad1 = bits;
    *pad2 = 0;
    *system = frame >= BENCH_FRAMES ? PAD_SYS_QUIT : 0;
}

void *InfoNES_MemoryCopy(void *d, const void *s, int n) { return memcpy(d, s, (size_t)n); }
void *InfoNES_MemorySet(void *d, int c, int n) { return memset(d, c, (size_t)n); }
void InfoNES_DebugPrint(char *m) { puts_(m); }
void InfoNES_Wait(void) {}
void InfoNES_SoundInit(void) {}
int InfoNES_SoundOpen(int a, int b) { (void)a; (void)b; return 0; }
void InfoNES_SoundClose(void) {}
void InfoNES_SoundOutput(int n, BYTE *a, BYTE *b, BYTE *c, BYTE *d, BYTE *e)
{
    (void)n; (void)a; (void)b; (void)c; (void)d; (void)e;
}
void InfoNES_MessageBox(char *m, ...) { puts_(m); }

static void report(void)
{
    uint32_t n = frame - BENCH_WARMUP;
    puts_("NES_BENCH frames="); putu(n);
    puts_(" avg="); putu(sum / n);
    puts_(" min="); putu(best);
    puts_(" max="); putu(worst);
    puts_(" texels_avg="); putu(texel_sum / n);
    puts_(" texels_max="); putu(texel_worst);
    puts_("\nNES_HIST bucket=");
    putu(HIST_BUCKET);
    for (unsigned i = 0; i < HIST_BUCKETS; ++i) { putc_(' '); putu(hist[i]); }
    puts_("\n");
}

int main(void)
{
    for (unsigned i = 0; i < 64; ++i) NesPalette[i] = (WORD)i;
    puts_("NES_BENCH start\n");
    int status = nes_rom_parse(bench_rom, bench_rom_size, &rom);
    if (status != NES_ROM_OK) { puts_(nes_rom_error(status)); EXIT_REG = 2; for (;;) {} }
    nes_frame_invalidate();
    if (InfoNES_Load(NULL)) { puts_("load failed\n"); EXIT_REG = 3; for (;;) {} }
    frame_start = TIMER_LO;
    InfoNES_Main();
    report();
    EXIT_REG = 0;
    for (;;) {}
}
