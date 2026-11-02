/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Hardware services used by the InfoNES glue (nes_system.c).  The board
 * implements them with MMIO; the host harness implements them with models. */
#ifndef NES_PLATFORM_H
#define NES_PLATFORM_H
#include <stdint.h>
#include "nes_port.h"

uint64_t nes_cycles(void);              /* free-running CPU cycle counter */
uint32_t nes_cpu_hz(void);
uint32_t nes_display_frame(void);       /* display frame counter, wraps at 16 bits */
uint32_t nes_input_read(void);          /* NES_PAD_* bits, 0 when touch is unhealthy */
int nes_video_ready(void);              /* GPU can accept the next frame */
/* Uploads the changed texels of one rendered picture row (0..223). */
void nes_video_line(const uint16_t *line, unsigned y);
/* Queues the whole frame (picture tiles + controls) and a swap. */
void nes_video_present(uint32_t pad, unsigned menu_hold_pct);
void nes_log(const char *text);
void nes_log_u32(uint32_t value);

/* Session lifecycle (nes_system.c). */
void nes_session_start(const nes_rom_t *rom);
typedef struct {
    uint32_t frames, presented, skipped_busy, late_frames, max_skip;
    /* CPU cycles per emulated frame, waits excluded (rendered frames only),
     * and per present call (texel upload + GPU command stream). */
    uint64_t work_cycles, present_cycles;
    uint32_t work_frames, work_max, present_max;
} nes_stats_t;
void nes_session_stats(nes_stats_t *out);
#endif
