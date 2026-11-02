/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Board-only services of the NES port (GPU drawing, touch, SD catalog). */
#ifndef NES_BOARD_H
#define NES_BOARD_H
#include <stdint.h>
#include "nes_port.h"

/* Healthy multi-contact touch sample in canvas coordinates. */
typedef struct {
    uint32_t sequence;
    int healthy, down;
    unsigned count;
    nes_point_t point[NES_TOUCH_MAX];
} nes_touch_t;
void nes_touch_sample(nes_touch_t *out);

void nes_video_init(void);
void nes_video_wait(void);
void nes_video_message(const char *title, const char *detail);
void nes_video_menu(const nes_menu_t *menu, const char *status);
void nes_video_progress(const char *title, uint32_t done, uint32_t total);

uint32_t nes_trap_misaligned(void);
uint32_t nes_video_texels(void);

/* Board UART (board_fw/uart.c). */
void uart_putc(char c);
void uart_puts(const char *s);
void uart_putu(uint32_t v);
#endif
