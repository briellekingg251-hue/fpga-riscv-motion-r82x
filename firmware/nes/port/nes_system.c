/* SPDX-License-Identifier: GPL-2.0-or-later */
/* InfoNES system callbacks: ROM hand-over, frame pacing, joypad, display.
 *
 * Pacing: InfoNES calls InfoNES_PadState once per emulated frame (V-blank).
 * Each emulated frame is given one display frame, so emulation is locked to
 * the panel's refresh (60 Hz; the NES runs at 60.0988 Hz, 0.16 % faster).
 * The GPU shows a swap at the next display frame boundary, so a frame queued
 * right after the boundary is always on screen by the following one; pacing
 * on the CPU timer instead drifts against the panel and loses every other
 * frame to a pending swap.  When the CPU falls behind, InfoNES's FrameSkip is
 * raised so whole frames are emulated without rendering, and lowered again
 * once there is slack. */
#include <string.h>
#include "InfoNES.h"
#include "InfoNES_System.h"
#include "nes_platform.h"

/* NES colour n is carried through InfoNES as the value n. */
WORD NesPalette[64] = {
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
};

#define MENU_HOLD_MS      500u     /* MENU must be held this long to quit */
#define MAX_FRAME_SKIP    3u
#define LATE_TO_SKIP      4u       /* consecutive late frames before skipping more */
#define EARLY_TO_UNSKIP   120u     /* consecutive frames with slack before skipping less */
#define RESYNC_FRAMES     8       /* further behind than this: drop the backlog */
#define STATS_EVERY       3600u    /* frames between UART reports (~1 min); a report
                                     * blocks ~13 ms on the 115200 baud UART */
#define WAIT_LIMIT_FRAMES 3u       /* give up a display-slot wait after this long */
#define TRAINER_OFFSET    0x1000u  /* trainer lands at $7000 */

static const nes_rom_t *rom;
static BYTE no_chr[0x2000];
static uint64_t menu_since;
static uint32_t target_frame;
static unsigned late_run, early_run, menu_pct, quit, paced;
static uint64_t frame_start;
static int frame_rendered, frame_live;
static nes_stats_t stats;

void nes_session_start(const nes_rom_t *r)
{
    rom = r;
    menu_since = 0;
    target_frame = 0;
    late_run = early_run = menu_pct = quit = paced = 0;
    frame_start = 0;
    frame_rendered = 0;
    frame_live = 0;
    memset(&stats, 0, sizeof stats);
    nes_frame_invalidate();
}

void nes_session_stats(nes_stats_t *out) { *out = stats; }

int InfoNES_Menu(void)
{
    /* First call starts the cartridge; after a MENU quit, leave InfoNES_Main. */
    return quit ? -1 : 0;
}

int InfoNES_ReadRom(const char *name)
{
    (void)name;
    if (!rom) return -1;
    memcpy(&NesHeader, rom->header, sizeof NesHeader);
    memset(SRAM, 0, SRAM_SIZE);
    if (rom->trainer) memcpy(&SRAM[TRAINER_OFFSET], rom->trainer, 512);
    ROM = (BYTE *)rom->prg;
    /* CHR-RAM carts: a mapper that maps VROM pages without checking the
     * header must read zeros, never address 0. */
    VROM = rom->chr ? (BYTE *)rom->chr : no_chr;
    return 0;
}

void InfoNES_ReleaseRom(void)
{
    ROM = NULL;
    VROM = NULL;
}

/* A rendered frame goes to the GPU only if the GPU was idle when its first
 * picture row was ready.  Otherwise the previous swap is still waiting for a
 * display boundary and holds the command FIFO: uploading would stall the CPU
 * until then.  A dropped frame sends nothing, so the texel shadow stays equal
 * to GPU sprite memory and the next frame's diff remains exact. */
void InfoNES_LoadFrame(void)
{
    frame_rendered = 1;
    if (!frame_live) { ++stats.skipped_busy; return; }
    frame_live = 0;
    uint64_t start = nes_cycles();
    nes_video_present(nes_input_read(), menu_pct);
    uint32_t spent = (uint32_t)(nes_cycles() - start);
    stats.present_cycles += spent;
    if (spent > stats.present_max) stats.present_max = spent;
    ++stats.presented;
}

void InfoNES_LoadLine(void)
{
    unsigned line = PPU_Scanline;
    if (line < NES_VIEW_TOP || line >= NES_VIEW_TOP + NES_VIEW_LINES) return;
    if (line == NES_VIEW_TOP) frame_live = nes_video_ready();
    if (frame_live) nes_video_line(&WorkFrame[line * NES_VIEW_W], line - NES_VIEW_TOP);
}

static void report(void)
{
    nes_log("NES_STAT frames=");   nes_log_u32(stats.frames);
    nes_log(" presented=");        nes_log_u32(stats.presented);
    nes_log(" busy_drop=");        nes_log_u32(stats.skipped_busy);
    nes_log(" late=");             nes_log_u32(stats.late_frames);
    nes_log(" skip=");             nes_log_u32(FrameSkip);
    nes_log(" max_skip=");         nes_log_u32(stats.max_skip);
    nes_log(" work_avg=");         nes_log_u32(stats.work_frames ? (uint32_t)(stats.work_cycles / stats.work_frames) : 0);
    nes_log(" work_max=");         nes_log_u32(stats.work_max);
    nes_log(" present_avg=");      nes_log_u32(stats.presented ? (uint32_t)(stats.present_cycles / stats.presented) : 0);
    nes_log(" present_max=");      nes_log_u32(stats.present_max);
    nes_log("\n");
}

static int16_t frames_until(uint32_t frame) { return (int16_t)(frame - nes_display_frame()); }

/* Called once per emulated frame: wait for this frame's display slot, or
 * adapt FrameSkip when the slot has already passed. */
/* Cost of the frame just emulated, measured from the end of the last wait. */
static void account_work(void)
{
    uint64_t now = nes_cycles();
    if (frame_start && frame_rendered) {
        uint32_t spent = (uint32_t)(now - frame_start);
        stats.work_cycles += spent;
        ++stats.work_frames;
        if (spent > stats.work_max) stats.work_max = spent;
    }
    frame_rendered = 0;
}

static void pace(void)
{
    account_work();
    if (!paced) { target_frame = nes_display_frame() + 1u; paced = 1; }
    int16_t ahead = frames_until(target_frame);
    if (ahead > 0) {
        /* Bounded: a stalled display clock must not hang the emulator (the
         * MENU hold could never be seen).  On timeout, resynchronise. */
        uint64_t limit = nes_cycles() + (uint64_t)nes_cpu_hz() / 60u * WAIT_LIMIT_FRAMES;
        while (frames_until(target_frame) > 0)
            if (nes_cycles() > limit) { target_frame = nes_display_frame(); break; }
        late_run = 0;
        if (++early_run >= EARLY_TO_UNSKIP && FrameSkip) { --FrameSkip; early_run = 0; }
    } else if (ahead < 0) {
        early_run = 0;
        ++stats.late_frames;
        if (++late_run >= LATE_TO_SKIP && FrameSkip < MAX_FRAME_SKIP) { ++FrameSkip; late_run = 0; }
        if (ahead < -RESYNC_FRAMES) target_frame = nes_display_frame();
    }
    if (FrameSkip > stats.max_skip) stats.max_skip = FrameSkip;
    target_frame = (target_frame + 1u) & 0xffffu;
    frame_start = nes_cycles();
}

static void menu_hold(uint32_t pad, DWORD *system)
{
    uint64_t now = nes_cycles(), hold = (uint64_t)nes_cpu_hz() / 1000u * MENU_HOLD_MS;
    if (!(pad & NES_PAD_MENU)) { menu_since = 0; menu_pct = 0; return; }
    if (!menu_since) menu_since = now;
    uint64_t held = now - menu_since;
    menu_pct = held >= hold ? 100u : (unsigned)(held * 100u / hold);
    if (held >= hold) { quit = 1; *system |= PAD_SYS_QUIT; }
}

void InfoNES_PadState(DWORD *pad1, DWORD *pad2, DWORD *system)
{
    uint32_t pad = nes_input_read();
    *pad1 = pad & 0xffu;
    *pad2 = 0;
    *system = 0;
    menu_hold(pad, system);
    pace();
    if (++stats.frames % STATS_EVERY == 0) report();
}

void *InfoNES_MemoryCopy(void *dest, const void *src, int count) { return memcpy(dest, src, (size_t)count); }
void *InfoNES_MemorySet(void *dest, int c, int count) { return memset(dest, c, (size_t)count); }
void InfoNES_DebugPrint(char *message) { nes_log(message); }
void InfoNES_Wait(void) {}
void InfoNES_SoundInit(void) {}
int InfoNES_SoundOpen(int samples_per_sync, int sample_rate)
{
    (void)samples_per_sync; (void)sample_rate;
    return 0;
}
void InfoNES_SoundClose(void) {}
void InfoNES_SoundOutput(int samples, BYTE *wave1, BYTE *wave2, BYTE *wave3, BYTE *wave4, BYTE *wave5)
{
    (void)samples; (void)wave1; (void)wave2; (void)wave3; (void)wave4; (void)wave5;
}

/* InfoNES only reports unsupported mappers and unknown opcodes here; the
 * format string is logged verbatim rather than pulling in a printf. */
void InfoNES_MessageBox(char *message, ...) { nes_log(message); }
