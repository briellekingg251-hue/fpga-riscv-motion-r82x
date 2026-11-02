/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Board platform layer of the PAL-Navy port (loader ABI 3, DDR image). */
#ifndef FPGA_PAL_PORT_H
#define FPGA_PAL_PORT_H
#include <stdint.h>

#define PAL_GAME_ID       0x50414c31u /* "PAL1" */
#define PAL_SAVE_SLOTS    5u
#define PAL_GAME_DIR      "PAL"

/* The 320x200 game is scaled 1.5x to 480x300, filling the height of the
 * 512x300 GPU framebuffer (2x on the 1024x600 LCD); touch buttons overlay it. */
#define PAL_VIEW_W        320
#define PAL_VIEW_H        200
#define PAL_VIEW_X        16
#define PAL_VIEW_Y        0
#define PAL_SCALE_NUM     3   /* display size = source * 3 / 2 */
#define PAL_SCALE_DEN     2

void uart_putc(char c);
void uart_puts(const char *s);
void uart_putu(uint32_t v);

/* Video presenter (pal_video.c). */
void pal_video_init(void);
void pal_video_service(void);          /* flush a deferred frame when the GPU is idle */
void pal_port_fatal_screen(const char *what, uint32_t pc);
void pal_port_message(const char *line1, const char *line2);

/* Saves (pal_syscalls.c). */
int pal_port_storage_init(void);
uint32_t pal_trap_misaligned_count(void);
#endif
