/* Subway Run rules for the s80 RISC-V CPU + FPGA display engine.
 *
 * Obstacles: concrete blocks and trains must be dodged sideways, overhead
 * bars must be ducked under (or dodged).  The row generator keeps one "safe
 * lane" that never contains a block or train and that only moves to an
 * adjacent lane when that lane has been clear long enough to switch.
 * Rendering lives in subway_draw.c; shared constants in subway_int.h.
 */
#include <stdint.h>
#include "soc.h"
#include "gpu.h"
#include "app.h"
#include "subway.h"
#include "subway_int.h"
#include "pose_input.h"
#define FN_SUBWAY_PALETTE_TABLE
#include "subway_assets.h"

const button_t SW_BTN_PAUSE   = {208,   4,  96, 40, "PAUSE"};
const button_t SW_BTN_RESUME  = {164,  92, 184, 44, "RESUME"};
const button_t SW_BTN_RESTART = {164, 146, 184, 44, "RESTART"};
const button_t SW_BTN_MENU_P  = {164, 200, 184, 44, "MENU"};
const button_t SW_BTN_RETRY   = { 90, 222, 160, 46, "RETRY"};
const button_t SW_BTN_MENU_O  = {262, 222, 160, 46, "MENU"};
/* Pose pause menu only: lane mode switch (same rectangle, two labels). */
const button_t SW_BTN_LANE_STEP = {8, 250, 124, 40, "LANE: STEP"};
const button_t SW_BTN_LANE_ZONE = {8, 250, 124, 40, "LANE: ZONE"};

/* ------------------------------------------------------------ state */
sw_obj_t sw_objs[SW_MAX_OBJ];
int sw_zrow[FB_H], sw_bed_hw[FB_H];
int sw_state, sw_frames, sw_dist4, sw_dist, sw_speed4;
int sw_coins, sw_score, sw_best, sw_crash_kind;
int sw_lane, sw_px, sw_duck, sw_bump, sw_flash, sw_hint;
int sw_next_row, sw_safe_lane, sw_busy_until[3];
int sw_swipe_live, sw_swipe_ax, sw_swipe_ay;
int sw_cam_x;
static int sw_tables_ready;
static control_mode_t sw_mode;
static uint32_t sw_epoch,sw_last_seq,sw_last_event;
static int sw_have_seq,sw_have_event,sw_half_remainder;
void sw_set_control(control_mode_t mode,uint32_t epoch) {
    sw_mode=mode==CONTROL_POSE?CONTROL_POSE:CONTROL_TOUCH;sw_epoch=epoch;
    sw_last_seq=sw_last_event=0;sw_have_seq=sw_have_event=sw_half_remainder=0;
    sw_duck=0;sw_swipe_live=SWIPE_NONE;
}

static int sw_zone_wait;
void sw_break_pose_actions(void) {sw_have_event=0;sw_duck=0;sw_swipe_live=SWIPE_NONE;sw_zone_wait=0;}

int sw_state_now(void) { return sw_state; }
int sw_pose_mode(void) { return sw_mode == CONTROL_POSE; }
void sw_pause(void) { if (sw_state == SW_PLAY) { sw_state = SW_PAUSE; sw_swipe_live = SWIPE_NONE; } }
int sw_score_now(void) { return sw_score; }
int sw_best_now(void) { return sw_best > sw_score ? sw_best : sw_score; }

void sw_load_palette(void)
{
    for (unsigned i = 0; i < 240u; ++i) gpu_palette(16u + i, sw_palette[i]);
}

void sw_init_tables(void)
{
    if (sw_tables_ready) return;
    for (int y = HORIZON + 1; y < FB_H; ++y) {
        sw_zrow[y] = (FOCAL * CAM_H) / (y - HORIZON);
        sw_bed_hw[y] = (TRACK_HW * (y - HORIZON)) / CAM_H;
    }
    sw_draw_init();
    sw_tables_ready = 1;
}

/* ------------------------------------------------------------ spawning */
static sw_obj_t *sw_add(int kind, int lane, int wz, int len, int variant)
{
    for (int i = 0; i < SW_MAX_OBJ; ++i) {
        sw_obj_t *o = &sw_objs[i];
        if (o->kind != K_NONE) continue;
        o->kind = (uint8_t)kind;
        o->lane = (uint8_t)lane;
        o->variant = (uint8_t)variant;
        o->wz = wz;
        o->len = len;
        return o;
    }
    return 0;
}

static int sw_level(void)
{
    int level = (sw_speed4 - SPEED_START_Q4) / 52;
    return level > 3 ? 3 : level;
}

static void sw_block_lane(int lane, int kind, int wz)
{
    int len = BLOCK_DEPTH;
    if (kind == K_TRAIN) len = app_rnd_range(TRAIN_MIN, TRAIN_MAX);
    if (!sw_add(kind, lane, wz, len, (int)(app_rnd() % SW_TRAIN_VARIANTS))) return;
    if (sw_busy_until[lane] < wz + len) sw_busy_until[lane] = wz + len;
}

/* One obstacle row at absolute distance wz; returns the gap to the next row. */
static int sw_spawn_row(int wz)
{
    int speed = sw_speed4 >> 4;
    int level = sw_level();
    int gap = speed * app_rnd_range(ROW_GAP_MIN, ROW_GAP_MAX - level * 4);
    int margin = speed * 16 + 80;              /* room to see and step across */
    int r = (int)(app_rnd() % 4u);
    int cand = sw_safe_lane + (r == 2 ? -1 : (r == 3 ? 1 : 0));
    if (cand >= 0 && cand <= 2 && cand != sw_safe_lane && sw_busy_until[cand] < wz - margin)
        sw_safe_lane = cand;

    int placed = 0;
    for (int l = 0; l < 3; ++l) {
        if (l == sw_safe_lane || sw_busy_until[l] > wz - 40) continue;
        int p = (int)(app_rnd() % 100u);
        if (p < 26 + level * 8)      { sw_block_lane(l, K_TRAIN, wz); placed++; }
        else if (p < 52 + level * 8) { sw_block_lane(l, K_BLOCK, wz); placed++; }
        else if (p < 68 + level * 6) { sw_add(K_BAR, l, wz, BAR_DEPTH, 0); placed++; }
    }
    int p = (int)(app_rnd() % 100u);
    if (!placed || p < 22 + level * 6) {
        sw_add(K_BAR, sw_safe_lane, wz, BAR_DEPTH, 0);
    } else if (p < 70) {
        int n = (gap - 80) / COIN_SP;
        if (n > 8) n = 8;
        for (int i = 0; i < n; ++i) sw_add(K_COIN, sw_safe_lane, wz + 40 + i * COIN_SP, 0, 0);
    }
    return gap;
}

void sw_new_run(void)
{
    sw_init_tables();
    for (int i = 0; i < SW_MAX_OBJ; ++i) sw_objs[i].kind = K_NONE;
    for (int l = 0; l < 3; ++l) sw_busy_until[l] = -100000;
    if (sw_score > sw_best) sw_best = sw_score;
    sw_state = SW_PLAY;
    sw_frames = 0;
    sw_half_remainder = 0;
    sw_dist4 = sw_dist = 0;
    sw_speed4 = SPEED_START_Q4;
    sw_coins = sw_score = 0;
    sw_crash_kind = K_NONE;
    sw_lane = 1;
    sw_px = 0;
    sw_cam_x = 0;
    sw_duck = sw_bump = sw_flash = 0;
    sw_hint = HINT_FRAMES;
    sw_next_row = FIRST_ROW;
    sw_safe_lane = 1;
    sw_swipe_live = SWIPE_NONE;
}

/* ------------------------------------------------------------ rules */
/* Does an obstacle of this kind block lane `lane` at the player's depth? */
static int sw_lane_occupied(int lane)
{
    for (int i = 0; i < SW_MAX_OBJ; ++i) {
        const sw_obj_t *o = &sw_objs[i];
        if ((o->kind != K_TRAIN && o->kind != K_BLOCK) || o->lane != lane) continue;
        int zf = sw_rel(o->wz);
        if (zf <= Z_PLAYER + HIT_BAND + 4 && zf + o->len >= Z_PLAYER - HIT_BAND - 4) return 1;
    }
    return 0;
}

static void sw_try_move(int dir)
{
    int target = sw_lane + dir;
    if (target < 0 || target > 2 || sw_lane_occupied(target)) {
        sw_bump = BUMP_FRAMES;           /* wall or the side of a train */
        return;
    }
    sw_lane = target;
}

static void sw_swipes(const app_input_t *in)
{
    if (!in->down || in->blocked) {
        sw_swipe_live = SWIPE_NONE;
        return;
    }
    if (in->new_stroke || sw_swipe_live == SWIPE_NONE) {
        sw_swipe_live = SWIPE_LIVE;
        sw_swipe_ax = in->x;
        sw_swipe_ay = in->y;
        return;
    }
    if (sw_swipe_live != SWIPE_LIVE || !in->fresh) return;
    int dx = in->x - sw_swipe_ax, dy = in->y - sw_swipe_ay;
    int ax = sw_abs(dx), ay = sw_abs(dy);
    if (ax >= SWIPE_MIN && ax > ay) sw_try_move(dx < 0 ? -1 : 1);
    else if (dy >= SWIPE_MIN && dy > ax) sw_duck = DUCK_FRAMES;
    else return;                         /* small or upward moves do nothing */
    /* One lane change (or duck) per touch, however long the swipe: the
     * finger must lift before the next action.
     */
    sw_swipe_live = SWIPE_SPENT;
}

static void sw_crash(int kind)
{
    sw_score = sw_dist / DIST_PER_POINT + sw_coins * COIN_SCORE;
    sw_state = SW_OVER;
    sw_crash_kind = kind;
    sw_flash = FLASH_FRAMES;
    if (sw_score > sw_best) sw_best = sw_score;
    app_log(kind == K_BAR ? "subway crash bar" : (kind == K_TRAIN ? "subway crash train" : "subway crash block"));
}

static void sw_collide(int step)
{
    for (int i = 0; i < SW_MAX_OBJ; ++i) {
        sw_obj_t *o = &sw_objs[i];
        if (o->kind == K_NONE) continue;
        int zf = sw_rel(o->wz);
        /* swept depth interval since the previous frame */
        if (zf > Z_PLAYER + HIT_BAND || zf + o->len + step < Z_PLAYER - HIT_BAND) continue;
        int dx = sw_abs(sw_px - sw_lane_x(o->lane));
        if (o->kind == K_COIN) {
            if (dx < LANE_W / 2) { o->kind = K_NONE; sw_coins++; }
            continue;
        }
        if (dx >= OBJ_HW + PLAYER_HW - HIT_SLACK) continue;
        if (o->kind == K_BAR && sw_duck > 0) continue;
        sw_crash(o->kind);
        return;
    }
}

static int sw_handle_buttons(const app_input_t *in)
{
    if (!in->pressed) return SW_STAY;
    if (sw_state == SW_PLAY && app_button_hit(in, &SW_BTN_PAUSE)) {
        sw_state = SW_PAUSE;
        app_consume_touch("SUBWAY PAUSE");
    } else if (sw_state == SW_PAUSE && app_button_hit(in, &SW_BTN_RESUME)) {
        sw_state = SW_PLAY;
        app_consume_touch("SUBWAY RESUME");
    } else if ((sw_state == SW_PAUSE && app_button_hit(in, &SW_BTN_RESTART)) ||
               (sw_state == SW_OVER && app_button_hit(in, &SW_BTN_RETRY))) {
        sw_new_run();
        app_consume_touch("SUBWAY RESTART");
    } else if (sw_state == SW_PAUSE && sw_mode == CONTROL_POSE &&
               app_button_hit(in, &SW_BTN_LANE_STEP)) {
        pose_input_set_lane_zones(!pose_input_lane_zones());
        sw_zone_wait = 0;
        app_consume_touch(pose_input_lane_zones() ? "SUBWAY LANE MODE ZONE" : "SUBWAY LANE MODE STEP");
    } else if ((sw_state == SW_PAUSE && app_button_hit(in, &SW_BTN_MENU_P)) ||
               (sw_state == SW_OVER && app_button_hit(in, &SW_BTN_MENU_O))) {
        if (sw_score > sw_best) sw_best = sw_score;
        app_consume_touch("SUBWAY MENU");
        return SW_EXIT_MENU;
    } else {
        return SW_STAY;
    }
    sw_swipe_live = SWIPE_NONE;
    return -1;                               /* consumed, no exit */
}

static int sw_update_frame(const app_input_t *in,const control_frame_t *pose,int fresh)
{
    int valid=sw_mode==CONTROL_POSE && pose && sw_epoch &&
        pose->session_epoch==sw_epoch && pose->pose_valid;
    if(sw_mode==CONTROL_POSE)sw_duck=valid && pose->actions.duck_held?1:0;
    int ui = sw_handle_buttons(in);
    if (ui == SW_EXIT_MENU) return SW_EXIT_MENU;
    if (sw_flash > 0) sw_flash--;
    if (ui != SW_STAY || sw_state != SW_PLAY) return SW_STAY;

    sw_frames++;
    if (sw_hint > 0) sw_hint--;
    if (sw_bump > 0) sw_bump--;
    if(sw_mode==CONTROL_TOUCH)sw_swipes(in);
    else if(valid && fresh && pose->seq && (!sw_have_seq || sw_last_seq!=pose->seq)) {
        sw_have_seq=1;sw_last_seq=pose->seq;
        if(pose->actions.event_seq && (!sw_have_event || sw_last_event!=pose->actions.event_seq)) {
            sw_have_event=1;sw_last_event=pose->actions.event_seq;
            if(pose->actions.move==CONTROL_MOVE_LEFT)sw_try_move(-1);
            else if(pose->actions.move==CONTROL_MOVE_RIGHT)sw_try_move(1);
        }
    }
    /* Lane mode B: step toward the published zone one lane at a time,
     * once the runner has reached its lane; retry a blocked step later. */
    if(valid && pose->actions.target_lane>=1u && pose->actions.target_lane<=3u && !sw_zone_wait) {
        int want=(int)pose->actions.target_lane-1;
        if(want!=sw_lane && sw_px==sw_lane_x(sw_lane)) {
            sw_try_move(want<sw_lane?-1:1);sw_zone_wait=SW_ZONE_RETRY_TICKS;
        }
    }
    if(sw_zone_wait>0)sw_zone_wait--;

    int target = sw_lane_x(sw_lane);
    if (sw_px < target) sw_px = sw_px + LANE_STEP > target ? target : sw_px + LANE_STEP;
    else if (sw_px > target) sw_px = sw_px - LANE_STEP < target ? target : sw_px - LANE_STEP;

    int before = sw_dist;
    /* Nominal speed stays Q4=120..288. Halve forward displacement once,
     * carrying odd Q4 increments; spawn gap uses the FULL nominal speed.
     * At equal difficulty its time interval is therefore doubled. Ramp is
     * distance based, so growth takes twice as many frames without another /2. */
    if(sw_mode==CONTROL_POSE) {
        int delta=sw_speed4+sw_half_remainder;
        sw_dist4+=delta/2;sw_half_remainder=delta&1;
    } else sw_dist4 += sw_speed4;
    sw_dist = sw_dist4 >> 4;
    sw_speed4 = SPEED_START_Q4 + sw_dist / SPEED_RAMP;
    if (sw_speed4 > SPEED_MAX_Q4) sw_speed4 = SPEED_MAX_Q4;
    while (sw_next_row - sw_dist < Z_FAR - Z_PLAYER) sw_next_row += sw_spawn_row(sw_next_row);

    sw_score = sw_dist / DIST_PER_POINT + sw_coins * COIN_SCORE;
    sw_collide(sw_dist - before);
    if (sw_mode==CONTROL_TOUCH && sw_duck > 0) sw_duck--;
    for (int i = 0; i < SW_MAX_OBJ; ++i) {
        sw_obj_t *o = &sw_objs[i];
        if (o->kind != K_NONE && sw_rel(o->wz) + o->len < Z_NEAR - 30) o->kind = K_NONE;
    }
    sw_score = sw_dist / DIST_PER_POINT + sw_coins * COIN_SCORE;
    return SW_STAY;
}

int sw_update(const app_input_t *in) { return sw_update_frame(in,0,0); }
int sw_update_pose(const app_input_t *in,const control_frame_t *pose,int fresh) {
    return sw_update_frame(in,pose,fresh);
}
