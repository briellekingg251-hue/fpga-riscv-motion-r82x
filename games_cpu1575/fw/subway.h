/* Subway Run: three-lane endless runner.  Dodge by swiping left / right,
 * swipe down to duck under overhead bars.  There is no jump.
 */
#ifndef FN_SUBWAY_H
#define FN_SUBWAY_H

#include "app.h"

enum { SW_PLAY, SW_PAUSE, SW_OVER };
enum { SW_STAY = 0, SW_EXIT_MENU = 1 };

/* Palette entries 16..47 (the wood background in Fruit Ninja) hold the
 * subway colours while this game runs; main.c restores them on exit.
 */
void sw_load_palette(void);
void sw_new_run(void);
int  sw_update(const app_input_t *in);   /* SW_EXIT_MENU leaves the game */
void sw_draw(void);
int  sw_state_now(void);
int  sw_score_now(void);
int  sw_best_now(void);

#endif
