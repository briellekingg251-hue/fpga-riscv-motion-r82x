/* Subway Run internals shared by subway.c (rules) and subway_draw.c (view).
 *
 * Pseudo-3D view: a pinhole camera sits at world x = 0, CAM_H units above
 * the track, looking down three lanes.  A world point (x, h, z) at depth z
 * lands on framebuffer pixel
 *     sx = 256 + x * FOCAL / z,   sy = HORIZON + (CAM_H - h) * FOCAL / z
 */
#ifndef FN_SUBWAY_INT_H
#define FN_SUBWAY_INT_H

#include <stdint.h>
#include "app.h"
#include "control.h"

/* ------------------------------------------------------------ view */
#define HORIZON     70
#define FOCAL       240
#define CAM_H       154
#define Z_PLAYER    220          /* player's depth in front of the camera */
#define Z_CLIP      162          /* depth of the bottom framebuffer row */
#define Z_NEAR      70           /* tall trains stay visible beside the camera */
#define Z_FAR       3400
#define LANE_W      100
#define TRACK_HW    165
#define CENTER_X    256

/* ------------------------------------------------------------ world sizes */
#define PLAYER_HW   13
#define HIT_SLACK   4            /* forgiving side overlap */
#define OBJ_HW      46
#define TRAIN_H     136
#define BLOCK_H     60
#define BLOCK_DEPTH 24
#define BAR_LO      44           /* ducking player height is 41 */
#define BAR_HI      62           /* standing player height is 66 */
#define BAR_DEPTH   14
#define COIN_SP     60
#define TRAIN_MIN   360
#define TRAIN_MAX   1000

/* ------------------------------------------------------------ gameplay */
#define SPEED_START_Q4  120          /* 7.5 world units per frame, Q4 */
#define SPEED_MAX_Q4    (18 << 4)
#define SPEED_RAMP      600          /* +1/16 unit/frame per this many units */
#define LANE_STEP       15           /* lateral units per frame (~7 frames) */
#define DUCK_FRAMES     34
#define SWIPE_MIN       18           /* framebuffer pixels */
#define HINT_FRAMES     300
#define BUMP_FRAMES     10
#define FLASH_FRAMES    6
#define FIRST_ROW       1500
#define ROW_GAP_MIN     36           /* frames between obstacle rows */
#define ROW_GAP_MAX     58
#define SW_MAX_OBJ      96
#define HIT_BAND        6            /* player's depth half-thickness */
#define COIN_SCORE      5
#define DIST_PER_POINT  10

enum { K_NONE, K_BLOCK, K_BAR, K_TRAIN, K_COIN };
enum { SWIPE_NONE, SWIPE_LIVE, SWIPE_SPENT };   /* one action per touch */

typedef struct { uint8_t kind, lane, variant; int wz, len; } sw_obj_t;

extern const button_t SW_BTN_PAUSE, SW_BTN_RESUME, SW_BTN_RESTART, SW_BTN_MENU_P;
extern const button_t SW_BTN_RETRY, SW_BTN_MENU_O;
extern const button_t SW_BTN_LANE_STEP, SW_BTN_LANE_ZONE;
enum { SW_ZONE_RETRY_TICKS = 10 };   /* 60 Hz ticks between zone steps */

extern sw_obj_t sw_objs[SW_MAX_OBJ];
extern int sw_zrow[], sw_bed_hw[];
extern int sw_state, sw_frames, sw_dist4, sw_dist, sw_speed4;
extern int sw_coins, sw_score, sw_best, sw_crash_kind;
extern int sw_lane, sw_px, sw_duck, sw_bump, sw_flash, sw_hint;
extern int sw_next_row, sw_safe_lane, sw_busy_until[3];
extern int sw_swipe_live, sw_swipe_ax, sw_swipe_ay;
extern int sw_cam_x;            /* camera x, follows the runner (view only) */

void sw_break_pose_actions(void);
void sw_set_control(control_mode_t mode,uint32_t epoch);
int sw_update_pose(const app_input_t *in,const control_frame_t *pose,int fresh);
void sw_init_tables(void);
void sw_draw_init(void);        /* per-row texture tables, after sw_zrow */

static inline int sw_abs(int v) { return v < 0 ? -v : v; }
static inline int sw_mod(int a, int m) { int r = a % m; return r < 0 ? r + m : r; }
static inline int sw_lane_x(int lane) { return (lane - 1) * LANE_W; }
static inline int sw_rel(int wz) { return wz - sw_dist + Z_PLAYER; }
static inline int sw_k(int z) { return (FOCAL << 8) / z; }           /* Q8 px per unit */
static inline int sw_sx(int xw, int k) { return CENTER_X + (((xw - sw_cam_x) * k) >> 8); }
static inline int sw_sy(int h, int k) { return HORIZON + (((CAM_H - h) * k) >> 8); }

#endif
