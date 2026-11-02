/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "pal_sdl_backend.h"
#include "../soc.h"
#include <sdl-timer.h>

static uint64_t timer_origin;

uint64_t pal_sdl_cpu_cycles(void)
{
    uint32_t high, low, after;
    do {
        high = MTIME_HI;
        low = MTIME_LO;
        after = MTIME_HI;
    } while (high != after);
    return ((uint64_t)high << 32) | low;
}

void pal_sdl_timer_reset(void)
{
    timer_origin = pal_sdl_cpu_cycles();
}

uint32_t SDL_GetTicks(void)
{
    /* Dividing the full counter avoids the 26.5 second MTIME_LO wrap. The
     * SDL result itself wraps normally after approximately 49.7 days. */
    return (uint32_t)((pal_sdl_cpu_cycles() - timer_origin) /
                      (CPU_CLOCK_HZ / 1000u));
}

void SDL_Delay(uint32_t ms)
{
    uint64_t start = pal_sdl_cpu_cycles();
    uint64_t duration = (uint64_t)ms * (CPU_CLOCK_HZ / 1000u);
    /* Use the 64-bit elapsed cycles, including for delays crossing SDL's
     * 32-bit millisecond wrap. The CPU performs this foreground wait. */
    while (pal_sdl_cpu_cycles() - start < duration) {
        if (pal_video_service) pal_video_service();
    }
}
