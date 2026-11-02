/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef FPGA_PAL_SDL_BACKEND_H
#define FPGA_PAL_SDL_BACKEND_H
#include <stdint.h>

/* Single CPU / single foreground thread, matching the bare-metal PAL port. */
#define PAL_SDL_EVENT_CAPACITY 32u
#define PAL_SDL_DEFERRED_CAPACITY 32u
#ifndef PAL_SDL_TOUCH_STALE_MS
#define PAL_SDL_TOUCH_STALE_MS 250u
#endif

/* Call from the future platform SDL_Init, before entering the PAL engine. */
void pal_sdl_events_reset(void);
void pal_sdl_timer_reset(void);
/* Sample the real GT911 MMIO snapshot. Overflow is returned as -1; the
 * transition is retried after space is available, rather than silently lost. */
int pal_sdl_events_pump(void);
const char *pal_sdl_events_error(void);
uint32_t pal_sdl_events_overflows(void);
/* Coherent high/low/high timer read, also used by board diagnostic tests. */
uint64_t pal_sdl_cpu_cycles(void);
/* Optional platform hook run while polling input or waiting (the board video
 * presenter flushes deferred frames here). Weak: component tests omit it. */
void pal_video_service(void) __attribute__((weak));
#endif
