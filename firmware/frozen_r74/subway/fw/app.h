/* Shared helpers between the arcade shell (main.c) and the games.
 * Coordinates are framebuffer pixels (512 x 300).
 */
#ifndef FN_APP_H
#define FN_APP_H

#include <stdint.h>
#include "control.h"
/* app_input_t stays touch-only; the mode backend uses control_frame_t. */

typedef struct { int x, y, w, h; const char *label; } button_t;

/* One frame of filtered touch input, produced by main.c's touch_poll(). */
typedef struct {
    int x, y;           /* framebuffer position of the first contact */
    int down;           /* healthy, fresh contact present */
    int pressed;        /* new real press (eligible for buttons) */
    int new_stroke;     /* first frame of a contact or a track-ID change */
    int fresh;          /* this frame carries a new controller sample */
    int blocked;        /* a consumed button gesture is waiting for a real lift */
} app_input_t;

uint32_t app_rnd(void);
int  app_rnd_range(int lo, int hi);
void app_fmt_uint(char *dst, const char *prefix, int v);
void app_draw_button(const button_t *b);
void app_draw_center(const char *s, int y, unsigned color, unsigned shadow, int scale);
int  app_button_hit(const app_input_t *in, const button_t *b);
/* Consume the current gesture: no button or swipe until a real lift. */
void app_consume_touch(const char *action);
void app_log(const char *s);

#endif
