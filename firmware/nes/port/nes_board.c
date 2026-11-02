/* SPDX-License-Identifier: GPL-2.0-or-later */
/* MMIO side of the platform interface: cycle counter, UART log and touch.
 *
 * Touch: the GT911 bridge publishes the first contact in the legacy snapshot
 * registers; the extended ABI (magic at 0x124) adds four more contacts at
 * 0x110..0x11c.  A sample is used only when the controller reports READY
 * without FAULT, DOWN agrees with the contact count, and the sequence has
 * advanced within STALE_MS.  Otherwise no button is reported as held. */
#include "soc.h"
#include "touch.h"
#include "gpu.h"
#include "nes_board.h"
#include "nes_platform.h"

#define TOUCH_EXT_MAGIC_OFFSET 0x124u
#define TOUCH_EXT_MAGIC        0x54435035u
#define TOUCH_EXT_XY_OFFSET    0x10cu   /* + 4 * contact index (1..4) */
#define STALE_MS               200u

uint64_t nes_cycles(void)
{
    uint32_t hi, lo, again;
    do { hi = MTIME_HI; lo = MTIME_LO; again = MTIME_HI; } while (hi != again);
    return (uint64_t)hi << 32 | lo;
}

uint32_t nes_cpu_hz(void) { return CPU_CLOCK_HZ; }
uint32_t nes_display_frame(void) { return GPU_REG_FRAME & 0xffffu; }
void nes_log(const char *text) { uart_puts(text); }
void nes_log_u32(uint32_t value) { uart_putu(value); }

static uint32_t last_sequence;
static uint64_t last_change;
static int seen;

void nes_touch_sample(nes_touch_t *out)
{
    touch_sample_t s = touch_read();
    uint64_t now = nes_cycles();
    uint32_t xy[NES_TOUCH_MAX] = {s.xy, 0, 0, 0, 0};
    unsigned count = (s.status & TOUCH_DOWN) ? 1u : 0u;
    if (!seen || s.sequence != last_sequence) { last_sequence = s.sequence; last_change = now; seen = 1; }
    out->sequence = s.sequence;
    out->healthy = (s.status & (TOUCH_READY | TOUCH_FAULT)) == TOUCH_READY &&
                   now - last_change <= (uint64_t)CPU_CLOCK_HZ / 1000u * STALE_MS;
    if (FN_TOUCH_READ_REG(TOUCH_EXT_MAGIC_OFFSET) == TOUCH_EXT_MAGIC) {
        count = (s.status >> 4) & 15u;
        for (unsigned i = 1; i < NES_TOUCH_MAX; ++i) xy[i] = FN_TOUCH_READ_REG(TOUCH_EXT_XY_OFFSET + 4u * i);
    }
    if (!!(s.status & TOUCH_DOWN) != !!count) out->healthy = 0;
    if (count > NES_TOUCH_MAX) count = NES_TOUCH_MAX;
    out->down = count != 0;
    out->count = 0;
    for (unsigned i = 0; i < count; ++i) {
        int x, y;
        if (!touch_map(xy[i], &x, &y)) { out->healthy = 0; continue; }
        out->point[out->count].x = (int16_t)x;
        out->point[out->count].y = (int16_t)y;
        ++out->count;
    }
    if (!out->healthy) { out->down = 0; out->count = 0; }
}

uint32_t nes_input_read(void)
{
    nes_touch_t t;
    nes_touch_sample(&t);
    return t.healthy ? nes_pad_from_points(t.point, t.count) : 0u;
}
