/* Shared POSE-mode user interface for the SD games (Fruit Ninja, Subway Run).
 *
 * Display/menu layer only. It reads pose_input_view() (the last snapshot that
 * passed every identity/freshness/body gate) to show a live mini skeleton and
 * two hand cursors, and lets a player who stands away from the screen press
 * on-screen buttons by holding a hand over them (dwell). Gameplay hits, lane
 * events and duck state keep coming exclusively from control_frame_t.
 * Colours use the shared palette entries 0..15 that both games keep.
 */
#ifndef FN_POSE_UI_H
#define FN_POSE_UI_H
#include <stdint.h>
#include "control.h"

#define POSE_UI_DWELL_MS 900u     /* hold time that presses a button */
#define POSE_UI_VIEW_MS 300u      /* skeleton older than this counts as lost */
#define POSE_UI_LOST_MS 1500u     /* lost this long during play -> auto pause */

typedef struct { int x, y, w, h; } pose_ui_rect_t;
typedef struct {
    control_pose_snapshot_t snap;
    int body;                     /* a gated body is currently visible */
    int hand_ok[2], hx[2], hy[2]; /* menu cursors from the wrists, framebuffer px */
    uint32_t now, seen_ms;        /* seen_ms: capture time of the last gated body */
    int have_seen;
    int dwell_btn, dwell_hand, locked;
    uint32_t dwell_start;
    unsigned progress;            /* 0..256 of the current dwell */
} pose_ui_t;

void pose_ui_reset(pose_ui_t *u, uint32_t now_ms);
/* Call once per frame with the game's pose clock (game_control_now). */
void pose_ui_update(pose_ui_t *u, uint32_t now_ms);
/* Player continuously missing for at least ms (only after being seen once). */
int pose_ui_lost_for(const pose_ui_t *u, uint32_t ms);
/* Hold-to-press over rects[0..n-1]. Returns the index pressed this frame or
 * -1. After a press every button stays locked until no hand hovers any. */
int pose_ui_dwell(pose_ui_t *u, const pose_ui_rect_t *rects, unsigned n);
void pose_ui_draw_cursors(const pose_ui_t *u);
/* Mirror-view mini skeleton, 80 x 45 framebuffer pixels at (x, y). */
void pose_ui_draw_panel(const pose_ui_t *u, int x, int y);
/* Large centred "step into view" prompt with a body outline. */
void pose_ui_draw_prompt(const pose_ui_t *u, int y, const char *line1, const char *line2);
#endif
