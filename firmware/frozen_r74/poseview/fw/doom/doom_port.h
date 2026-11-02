/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef FPGA_DOOM_PORT_H
#define FPGA_DOOM_PORT_H
#include <stdint.h>
#define DOOM_GAME_ID 0x444f4f4du
#define DOOM_GAME_DIR "DOOM"
typedef struct { int x, y, w, h; const char *label; unsigned char key; } doom_button_t;
enum { DOOM_INPUT_GAME, DOOM_INPUT_MENU, DOOM_INPUT_MAP };
extern const doom_button_t *doom_buttons;
extern unsigned doom_button_count;
void doom_input_context(unsigned context);
unsigned doom_input_current_context(void);
void doom_input_sample(uint32_t ms, int valid, unsigned count, const uint32_t *xy,
                       const uint8_t *ids);
int doom_input_mouse_delta(void);
int doom_input_event(int *pressed, unsigned char *key);
int doom_input_held(unsigned char key);
void doom_input_reset(void);
void doom_poll_touch(void);
void doom_video_init(void);
void doom_video_frame(const uint8_t *pixels);
void doom_video_palette(const uint32_t *palette);
void doom_message(const char *message);
uint32_t doom_ticks_ms(void);
void doom_platform_main(void);
int doom_storage_init(void);
void doom_trap_handler(uint32_t *frame);
#endif
