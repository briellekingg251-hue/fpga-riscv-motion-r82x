/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef FPGA_PAL_TOUCH_H
#define FPGA_PAL_TOUCH_H
#include <stdint.h>
/* Values match upstream SDLPAL input.h enum PALKEY. */
enum { PAL_MENU=1u, PAL_CONFIRM=2u, PAL_DOWN=4u, PAL_LEFT=8u,
       PAL_UP=16u, PAL_RIGHT=32u, PAL_PAGEUP=64u, PAL_PAGEDOWN=128u,
       PAL_REPEAT=256u, PAL_AUTO=512u, PAL_STATUS=16384u };
typedef struct {uint32_t held,pressed,released;} pal_touch_events_t;
typedef struct {uint32_t held,deadline;} pal_touch_state_t;
typedef struct {int x,y,w,h;const char *label;uint32_t key;} pal_button_t;
extern const pal_button_t pal_buttons[6];
/* Coordinates use the existing 512x300 logical GPU/touch space. Valid=0
 * releases all keys, including stale samples or an unplugged touch panel. */
pal_touch_events_t pal_touch_update(pal_touch_state_t *state,uint32_t ms,
                                  int valid,int down,int x,int y);
#endif
