/* Subway Run rendering.
 *
 * Floor: every framebuffer row below the horizon is one textured sprite row
 * (GPU WRAP mode) whose texel step grows with depth -- first the ground
 * across the full width, then the three-lane track.  Rows beyond the "mip"
 * depth use v-invariant far textures so distant rows never flicker; the
 * change-over is dithered by alternating rows.
 * Trains: roof as scanlines, the inner side as 2-pixel texture columns and
 * the front as one sprite; REMAP selects the red / blue / yellow colour block.
 * Everything else is a scaled sprite, drawn far to near.
 */
#include <stdint.h>
#include "soc.h"
#include "gpu.h"
#include "assets.h"
#include "app.h"
#include "subway.h"
#include "subway_int.h"
#include "subway_assets.h"

#ifndef FN_SUBWAY_TILE_ROWS
#define FN_SUBWAY_TILE_ROWS 0
#endif
#if FN_SUBWAY_TILE_ROWS > 0
typedef struct {int x,top,h,u,v,dv;} train_column_t;
/* Odd column parity can expose both clipped edge columns: -1 through 511. */
static train_column_t train_columns[257];
#endif
#define GROUND_UNITS  200          /* world units per ground tile */
#define GROUND_MIP    1300
#define TRACK_MIP     1700
#define MIP_BLEND     260
#define TIE_SP        56           /* world units per track tile along z */
#define SIDE_TILE     150          /* world units per train side tile */
#define POLE_SP       600
#define POLE_X        205
#define POLE_H        190
#define PROP_SP       260
#define PROP_FAR      2800
#define RUNNER_SIZE   68           /* world units covered by the 64x64 runner art */
#define SW_MAX_ITEMS  (SW_MAX_OBJ + 48)

/* Q16 texel steps: (64 << 16) / units */
#define V_STEP_GROUND 20971
#define V_STEP_TIES   74898
#define U_STEP_SIDE   27962
#define U_LANE_ORIGIN 6291456      /* u of world x = -150 (left lane edge) */
#define U_PER_UNIT_TRACK  41943    /* (64 << 16) / 100 */
#define U_PER_UNIT_GROUND 20971    /* (64 << 16) / 200 */
#define CAM_FOLLOW_NUM 3           /* camera x = 3/4 of the runner's x ... */
#define CAM_FOLLOW_DEN 4
#define CAM_EASE       3           /* ... approached by 1/3 of the gap per frame */

enum { DRAW_OBJ, DRAW_POLES, DRAW_PROP, DRAW_PLAYER };
enum { PROP_TREE, PROP_BUSH, PROP_SIGNAL, PROP_NONE };

typedef struct { int z, x; uint8_t type, index, mirror; } sw_item_t;

static sw_item_t sw_items[SW_MAX_ITEMS];
static int sw_g_dudx[FB_H], sw_g_u0[FB_H], sw_t_dudx[FB_H];
static int sw_anim;                 /* advances every drawn frame, also when paused */

void sw_draw_init(void)
{
    for (int y = HORIZON + 1; y < FB_H; ++y) {
        int z = sw_zrow[y];
        sw_g_dudx[y] = (z * 5592) >> 6;                    /* z * (64<<16) / (FOCAL * 200) */
        sw_g_u0[y] = -(511 * sw_g_dudx[y]) / 2;            /* texel at the centre of x = 0 */
        sw_t_dudx[y] = (z * 11185) >> 6;                   /* z * (64<<16) / (FOCAL * 100) */
    }
}

/* The camera eases toward 3/4 of the runner's x, like the arcade original:
 * the runner's lane stays clear of trains passing in the other lanes.
 */
static void sw_follow_camera(void)
{
    int target = sw_px * CAM_FOLLOW_NUM / CAM_FOLLOW_DEN;
    int step = (target - sw_cam_x) / CAM_EASE;
    if (step == 0 && target != sw_cam_x) step = target > sw_cam_x ? 1 : -1;
    sw_cam_x += step;
}

/* ------------------------------------------------------------ backdrop */
static void sw_draw_sky(void)
{
    static const uint8_t bands[7] = {SC_SKY0, SC_SKY1, SC_SKY2, SC_SKY3, SC_SKY4, SC_SKY5, SC_HAZE};
    for (int i = 0; i < 7; ++i)
        gpu_rect(0, i * 10, FB_W, i == 6 ? HORIZON + 1 - 60 : 10, bands[i]);
    gpu_circle(426, 26, 21, SC_SUN_GLOW);
    gpu_circle(426, 26, 14, SC_SUN);
    for (int c = 0; c < 3; ++c) {
        int x = sw_mod(c * 223 + 40 + (sw_anim >> 3), 700) - 130;
        gpu_blit(SWS_CLOUD, x, -30 + c * 9, 120 - c * 16, 120 - c * 16, c & 1, 0, 0);
    }
    gpu_wr(GPU_DST, (uint32_t)(HORIZON - 63) << 16);
    gpu_wr(GPU_SIZE, (64u << 16) | FB_W);
    gpu_wr(GPU_U0, (uint32_t)(sw_cam_x * 4096));          /* slight parallax */
    gpu_wr(GPU_V0, 0x8000);
    gpu_wr(GPU_DUDX, 0x8000);                              /* 128-pixel skyline tiles */
    gpu_wr(GPU_DVDX, 0);
    gpu_wr(GPU_DUDY, 0);
    gpu_wr(GPU_DVDY, 0x10000);
    gpu_wr(GPU_FLAGS, GPU_FLAG_WRAP);
    gpu_wr(GPU_CMD_SPRITE, SWS_SKYLINE);
}

static void sw_draw_floor(void)
{
    int origin = sw_dist - Z_PLAYER;                       /* absolute distance at depth 0 */
    gpu_wr(GPU_DVDX, 0);
    gpu_wr(GPU_DUDY, 0);
    gpu_wr(GPU_DVDY, 0);
    gpu_wr(GPU_FLAGS, GPU_FLAG_WRAP);
    gpu_wr(GPU_SIZE, (1u << 16) | FB_W);
    for (int y = HORIZON + 1; y < FB_H; ++y) {
        int z = sw_zrow[y];
        int far = z >= GROUND_MIP || (z >= GROUND_MIP - MIP_BLEND && (y & 1));
        gpu_wr(GPU_DST, (uint32_t)y << 16);
        gpu_wr(GPU_U0, (uint32_t)(sw_g_u0[y] + sw_cam_x * U_PER_UNIT_GROUND));
        gpu_wr(GPU_V0, far ? 0x8000u : (uint32_t)(sw_mod(z + origin, GROUND_UNITS) * V_STEP_GROUND));
        gpu_wr(GPU_DUDX, (uint32_t)sw_g_dudx[y]);
        gpu_wr(GPU_CMD_SPRITE, far ? SWS_GROUND_FAR : SWS_GROUND);
    }
    for (int y = HORIZON + 1; y < FB_H; ++y) {
        int z = sw_zrow[y];
        int far = z >= TRACK_MIP || (z >= TRACK_MIP - MIP_BLEND && (y & 1));
        int hw = sw_bed_hw[y];
        int x0 = CENTER_X - hw - (sw_cam_x * (y - HORIZON)) / CAM_H;   /* bed edge at x = -165 */
        int u0 = ((2 * (x0 - CENTER_X) + 1) * sw_t_dudx[y]) / 2 + U_LANE_ORIGIN +
                 sw_cam_x * U_PER_UNIT_TRACK;
        gpu_wr(GPU_DST, ((uint32_t)y << 16) | (uint32_t)(x0 & 0xFFFF));
        gpu_wr(GPU_SIZE, (1u << 16) | (uint32_t)(2 * hw + 1));
        gpu_wr(GPU_U0, (uint32_t)u0);
        gpu_wr(GPU_V0, far ? 0x8000u : (uint32_t)(sw_mod(z + origin, TIE_SP) * V_STEP_TIES));
        gpu_wr(GPU_DUDX, (uint32_t)sw_t_dudx[y]);
        gpu_wr(GPU_CMD_SPRITE, far ? SWS_TRACK_FAR : SWS_TRACK);
    }
}

/* ------------------------------------------------------------ world boxes */
/* Sprite covering world x0..x1 and heights h0..h1 at depth scale k. */
static void sw_box(unsigned img, int x0, int x1, int h0, int h1, int k, int mirror,
                   uint32_t flags, unsigned color)
{
    int sx0 = sw_sx(x0, k), sx1 = sw_sx(x1, k);
    int sy0 = sw_sy(h1, k), sy1 = sw_sy(h0, k);
    gpu_blit(img, sx0, sy0, sx1 - sx0 > 0 ? sx1 - sx0 : 1, sy1 - sy0 > 0 ? sy1 - sy0 : 1,
             mirror, flags, color);
}

static void sw_draw_poles(int z)
{
    int k = sw_k(z);
    sw_box(SWS_POLE, -POLE_X - 11, -POLE_X + 69, 0, POLE_H, k, 0, 0, 0);
    sw_box(SWS_POLE, POLE_X - 69, POLE_X + 11, 0, POLE_H, k, 1, 0, 0);
}

static void sw_draw_prop(const sw_item_t *it)
{
    int k = sw_k(it->z);
    if (it->type == PROP_TREE)        sw_box(SWS_TREE, it->x - 60, it->x + 60, 0, 160, k, it->mirror, 0, 0);
    else if (it->type == PROP_BUSH)   sw_box(SWS_BUSH, it->x - 45, it->x + 45, 0, 90, k, it->mirror, 0, 0);
    else if (it->type == PROP_SIGNAL) sw_box(SWS_SIGNAL, it->x - 22, it->x + 22, 0, 120, k, 0, 0, 0);
}

static void sw_draw_block(const sw_obj_t *o, int z)
{
    int xc = sw_lane_x(o->lane), k = sw_k(z), kb = sw_k(z + BLOCK_DEPTH);
    int top_far = sw_sy(BLOCK_H, kb), top_near = sw_sy(BLOCK_H, k);
    int sx0 = sw_sx(xc - OBJ_HW + 4, k), sx1 = sw_sx(xc + OBJ_HW - 4, k);
    gpu_rect(sx0, top_far, sx1 - sx0, top_near - top_far + 1, SC_CONCRETE_TOP);
    sw_box(SWS_BARRIER, xc - OBJ_HW, xc + OBJ_HW, 0, BLOCK_H + 9, k, 0, 0, 0);
    int r = (3 * k) >> 8;
    if (r >= 1 && (sw_anim >> 3) & 1) gpu_circle(sw_sx(xc, k), sw_sy(BLOCK_H + 5, k), r, SC_AMBER);
}

static void sw_draw_coin(const sw_obj_t *o, int z)
{
    int k = sw_k(z);
    int cx = sw_sx(sw_lane_x(o->lane), k), cy = sw_sy(26, k);
    int r = (12 * k) >> 8;
    if (r < 1) r = 1;
    int c = icos(sw_anim * 6 + (o->wz >> 2));
    int cw = (2 * r * (c < 0 ? -c : c)) >> 14;
    if (cw < 2) cw = 2;
    gpu_blit(SWS_COIN, cx - cw / 2, cy - r, cw, 2 * r, c < 0, 0, 0);
}

/* Roof scanlines from the far end to the near end (roof top is TRAIN_H). */
static void sw_train_roof(int xc, int z0, int z1)
{
    const int above = CAM_H - TRAIN_H;
    int y_far = sw_sy(TRAIN_H, sw_k(z1)), y_near = sw_sy(TRAIN_H, sw_k(z0));
    for (int y = y_far; y <= y_near && y < FB_H; ++y) {
        int t = y - HORIZON;                                /* = above * k / 256 */
        int x0 = CENTER_X + ((xc - OBJ_HW - sw_cam_x) * t) / above;
        int x1 = CENTER_X + ((xc + OBJ_HW - sw_cam_x) * t) / above;
        int ridge = (x1 - x0) / 3;
        gpu_rect(x0, y, x1 - x0, 1, SC_ROOF);
        gpu_rect(x0 + ridge, y, ridge, 1, SC_ROOF_RIDGE);
    }
}

/* The side face turned toward the camera as 2-pixel texture columns; the
 * depth of each column follows from its screen x: x - 256 = (xe - cam) * k.
 */
static void sw_train_side(const sw_obj_t *o, int zf, int z0, int z1, unsigned remap)
{
    int xc = sw_lane_x(o->lane);
    int xe = sw_cam_x < xc - OBJ_HW ? xc - OBJ_HW : xc + OBJ_HW;
    int rel = xe - sw_cam_x;
    if (sw_cam_x >= xc - OBJ_HW && sw_cam_x <= xc + OBJ_HW) return;   /* camera above the roof */
    int xa = sw_sx(xe, sw_k(z0)), xb = sw_sx(xe, sw_k(z1));
    int lo = xa < xb ? xa : xb, hi = xa < xb ? xb : xa;
    gpu_wr(GPU_COLOR, remap);
    gpu_wr(GPU_DUDX, 0);
    gpu_wr(GPU_DVDX, 0);
    gpu_wr(GPU_DUDY, 0);
    gpu_wr(GPU_FLAGS, GPU_FLAG_REMAP | GPU_FLAG_WRAP);
#if FN_SUBWAY_TILE_ROWS > 0
    /* Keep original column parity and projected sample centre. Clip columns
     * before division/MMIO; reorder only disjoint rectangles of this face. */
    if(lo < -1)lo+=((-1-lo+1)/2)*2;
    if(hi > FB_W)hi=FB_W;
    unsigned n=0;
#endif
    for (int c = lo; c < hi; c += 2) {
        int k = ((c + 1 - CENTER_X) * 256) / rel;
        if (k <= 0) continue;
        int top = sw_sy(TRAIN_H, k), h = sw_sy(0, k) - top;
        if (h <= 0) continue;
        int local = (FOCAL << 8) / k - zf;                  /* distance behind the front */
        int dvdy = (64 << 16) / h, v0 = dvdy >> 1;
        if (top < 0) { v0 += dvdy * -top; h += top; top = 0; }
        if (h > FB_H - top) h = FB_H - top;
#if FN_SUBWAY_TILE_ROWS > 0
        if(h<=0)continue;
        train_columns[n++]=(train_column_t){c,top,h,sw_mod(local,SIDE_TILE)*U_STEP_SIDE,v0,dvdy};
#else
        gpu_wr(GPU_DST, ((uint32_t)top << 16) | (uint32_t)(c & 0xFFFF));
        gpu_wr(GPU_SIZE, ((uint32_t)h << 16) | 2u);
        gpu_wr(GPU_U0, (uint32_t)(sw_mod(local, SIDE_TILE) * U_STEP_SIDE));
        gpu_wr(GPU_V0, (uint32_t)v0);
        gpu_wr(GPU_DVDY, (uint32_t)dvdy);
        gpu_wr(GPU_CMD_SPRITE, SWS_TRAIN_SIDE);
#endif
    }
#if FN_SUBWAY_TILE_ROWS > 0
    for(int row=0;row<FB_H;row+=FN_SUBWAY_TILE_ROWS) {
        for(unsigned i=0;i<n;i++) {
            const train_column_t *q=&train_columns[i];
            int top=q->top>row?q->top:row;
            int end=q->top+q->h<row+FN_SUBWAY_TILE_ROWS?q->top+q->h:row+FN_SUBWAY_TILE_ROWS;
            if(top>=end)continue;
            gpu_wr(GPU_DST,((uint32_t)top<<16)|(uint32_t)(q->x&0xffff));
            gpu_wr(GPU_SIZE,((uint32_t)(end-top)<<16)|2u);
            gpu_wr(GPU_U0,(uint32_t)q->u);
            gpu_wr(GPU_V0,(uint32_t)(q->v+q->dv*(top-q->top)));
            gpu_wr(GPU_DVDY,(uint32_t)q->dv);
            gpu_wr(GPU_CMD_SPRITE,SWS_TRAIN_SIDE);
        }
    }
#endif
}

static void sw_draw_train(const sw_obj_t *o, int zf)
{
    int xc = sw_lane_x(o->lane);
    int z0 = zf < Z_NEAR ? Z_NEAR : zf;
    int z1 = zf + o->len > Z_FAR ? Z_FAR : zf + o->len;
    if (z1 <= z0) return;
    unsigned remap = (unsigned)(o->variant % SW_TRAIN_VARIANTS) * SW_TRAIN_STRIDE;
    sw_train_roof(xc, z0, z1);
    sw_train_side(o, zf, z0, z1, remap);
    if (zf >= Z_NEAR)
        sw_box(SWS_TRAIN_FRONT, xc - OBJ_HW, xc + OBJ_HW, 0, TRAIN_H, sw_k(zf), 0, GPU_FLAG_REMAP, remap);
}

/* ------------------------------------------------------------ runner */
static void sw_draw_shadow(int cx, int fy, int k)
{
    int w = (60 * k) >> 8, h = (26 * k) >> 8;
    gpu_blit(SWS_SHADOW, cx - w / 2, fy - h / 2, w, h, 0, GPU_FLAG_DITHER, 0);
    gpu_wr(GPU_FLAGS, 0);                                   /* RECT honours DITHER too */
}

static void sw_draw_player(void)
{
    int k = sw_k(Z_PLAYER);
    int size = (RUNNER_SIZE * k) >> 8;
    int cx = sw_sx(sw_px, k), fy = sw_sy(0, k);
    if (sw_bump > 0) cx += (sw_bump & 2) ? 3 : -3;
    sw_draw_shadow(cx, fy, k);
    int x = cx - size / 2, y = fy - size + 2;
    if (sw_state == SW_OVER) {
        gpu_blit(SWS_CRASH, x, y, size, size, 0, 0, 0);
        for (int i = 0; i < 3; ++i) {
            int a = sw_anim * 4 + i * 85;
            int sx = cx + ((icos(a) * 22) >> 14), sy = y + 6 + ((isin(a) * 6) >> 14);
            gpu_blit(SWS_STAR, sx - 7, sy - 7, 14, 14, 0, 0, 0);
        }
        return;
    }
    if (sw_duck > 0) {
        for (int i = 0; i < 2; ++i) {
            int d = 18 + ((sw_anim * 3 + i * 9) % 14);
            int s = 20 + ((sw_anim + i * 5) % 8);
            gpu_blit(SWS_DUST, cx + (i ? d : -d) - s / 2, fy - s + 4, s, s, i, 0, 0);
        }
        gpu_blit(SWS_DUCK, x, y, size, size, 0, 0, 0);
        return;
    }
    int stride = (sw_dist / 34) & 3;                        /* A, B, mirrored A, mirrored B */
    gpu_blit((stride & 1) ? SWS_RUN_B : SWS_RUN_A, x, y - (stride & 1), size, size, stride >= 2, 0, 0);
}

/* ------------------------------------------------------------ ordering */
static uint32_t sw_hash(uint32_t v)
{
    v *= 2654435761u;
    v ^= v >> 15;
    v *= 2246822519u;
    v ^= v >> 13;
    return v;
}

static int sw_add_item(int n, int z, int x, int type, int index, int mirror)
{
    if (n >= SW_MAX_ITEMS) return n;
    sw_items[n].z = z;
    sw_items[n].x = x;
    sw_items[n].type = (uint8_t)type;
    sw_items[n].index = (uint8_t)index;
    sw_items[n].mirror = (uint8_t)mirror;
    return n + 1;
}

static int sw_add_props(int n, int origin)
{
    for (int side = -1; side <= 1; side += 2) {
        for (int c = (origin + Z_CLIP) / PROP_SP - 1; c * PROP_SP <= origin + PROP_FAR; ++c) {
            uint32_t h = sw_hash((uint32_t)(c * 2 + (side > 0)));
            int z = c * PROP_SP + (int)(h % 120u) - origin;
            int type = (int)((h >> 8) % 12u);
            type = type < 5 ? PROP_TREE : (type < 10 ? PROP_BUSH : (type == 10 ? PROP_SIGNAL : PROP_NONE));
            if (type == PROP_NONE || z < Z_CLIP || z > PROP_FAR) continue;
            int x = type == PROP_TREE ? 280 + (int)((h >> 12) % 90u) :
                    (type == PROP_BUSH ? 228 + (int)((h >> 12) % 60u) : 178);
            n = sw_add_item(n, z, side * x, DRAW_PROP, type, (int)((h >> 20) & 1));
        }
    }
    return n;
}

static int sw_collect_items(void)
{
    int n = 0;
    for (int i = 0; i < SW_MAX_OBJ; ++i) {
        const sw_obj_t *o = &sw_objs[i];
        if (o->kind == K_NONE) continue;
        int z = sw_rel(o->wz);
        if (z > Z_FAR || z + o->len < Z_NEAR || (o->kind != K_TRAIN && z < Z_CLIP)) continue;
        n = sw_add_item(n, z, 0, DRAW_OBJ, i, 0);
    }
    int origin = sw_dist - Z_PLAYER;
    int first = origin + Z_CLIP + sw_mod(-(origin + Z_CLIP), POLE_SP);
    for (int wz = first; wz - origin <= Z_FAR; wz += POLE_SP)
        n = sw_add_item(n, wz - origin, 0, DRAW_POLES, 0, 0);
    n = sw_add_props(n, origin);
    n = sw_add_item(n, Z_PLAYER, 0, DRAW_PLAYER, 0, 0);
    for (int i = 1; i < n; ++i) {                           /* insertion sort, far first */
        sw_item_t it = sw_items[i];
        int j = i - 1;
        while (j >= 0 && sw_items[j].z < it.z) { sw_items[j + 1] = sw_items[j]; --j; }
        sw_items[j + 1] = it;
    }
    return n;
}

static void sw_draw_items(void)
{
    int n = sw_collect_items();
    for (int i = 0; i < n; ++i) {
        const sw_item_t *it = &sw_items[i];
        if (it->type == DRAW_PLAYER) { sw_draw_player(); continue; }
        if (it->type == DRAW_POLES) { sw_draw_poles(it->z); continue; }
        if (it->type == DRAW_PROP) { sw_draw_prop(it); continue; }
        const sw_obj_t *o = &sw_objs[it->index];
        int xc = sw_lane_x(o->lane);
        if (o->kind == K_TRAIN)      sw_draw_train(o, it->z);   /* z may be <= 0 here */
        else if (o->kind == K_BLOCK) sw_draw_block(o, it->z);
        else if (o->kind == K_BAR)   sw_box(SWS_BAR, xc - OBJ_HW - 4, xc + OBJ_HW + 4, 0, 64,
                                            sw_k(it->z), 0, 0, 0);
        else if (o->kind == K_COIN)  sw_draw_coin(o, it->z);
    }
}

/* ------------------------------------------------------------ HUD */
static void sw_shade_rect(int x, int y, int w, int h)
{
    gpu_wr(GPU_FLAGS, GPU_FLAG_DITHER);
    gpu_rect(x, y, w, h, SC_SHADE);
    gpu_wr(GPU_FLAGS, 0);
}

static void sw_draw_hud(void)
{
    char txt[20];
    app_fmt_uint(txt, "", sw_score);
    gpu_text_shadow(8, 4, txt, COL_GOLD, COL_SHADOW, 2);
    app_fmt_uint(txt, "BEST ", sw_best > sw_score ? sw_best : sw_score);
    gpu_text_shadow(10, 38, txt, COL_CREAM, COL_SHADOW, 1);
    gpu_blit(SWS_COIN, 404, 9, 26, 26, 0, 0, 0);
    app_fmt_uint(txt, "", sw_coins);
    gpu_text_shadow(436, 6, txt, COL_GOLD, COL_SHADOW, 2);
    if (sw_state == SW_PLAY) app_draw_button(&SW_BTN_PAUSE);
    if (sw_state == SW_PLAY && sw_hint > 0) {
        sw_shade_rect(92, 110, 328, 48);
        int pose = sw_pose_mode();
        app_draw_center(pose ? "STEP LEFT / RIGHT TO CHANGE LANE" : "SWIPE LEFT / RIGHT TO CHANGE LANE",
                        118, COL_WHITE, COL_SHADOW, 1);
        app_draw_center(pose ? "SQUAT DOWN TO DUCK UNDER BARS" : "SWIPE DOWN TO DUCK UNDER BARS",
                        136, COL_GOLD, COL_SHADOW, 1);
    }
}

void sw_draw(void)
{
    sw_anim++;
    sw_follow_camera();
    sw_draw_sky();
    sw_draw_floor();
    sw_draw_items();
    sw_draw_hud();
    if (sw_state == SW_PAUSE) {
        sw_shade_rect(0, 0, FB_W, FB_H);
        gpu_rect(140, 30, 232, 228, COL_INK);
        app_draw_center("PAUSED", 38, COL_GOLD, COL_SHADOW, 3);
        app_draw_button(&SW_BTN_RESUME);
        app_draw_button(&SW_BTN_RESTART);
        app_draw_button(&SW_BTN_MENU_P);
    } else if (sw_state == SW_OVER) {
        char txt[24];
        sw_shade_rect(0, 0, FB_W, FB_H);
        gpu_rect(70, 56, 372, 222, COL_INK);
        app_draw_center("CRASHED!", 62, COL_RED, COL_SHADOW, 4);
        if (sw_pose_mode())
            app_draw_center(sw_crash_kind == K_BAR ? "BARS: SQUAT DOWN TO DUCK" :
                            "BLOCKS AND TRAINS: STEP LEFT / RIGHT", 128, COL_WHITE, COL_SHADOW, 1);
        else
            app_draw_center(sw_crash_kind == K_BAR ? "BARS: SWIPE DOWN TO DUCK" :
                            "BLOCKS AND TRAINS: SWIPE LEFT / RIGHT", 128, COL_WHITE, COL_SHADOW, 1);
        app_fmt_uint(txt, "SCORE ", sw_score);
        app_draw_center(txt, 146, COL_GOLD, COL_SHADOW, 2);
        app_fmt_uint(txt, "COINS ", sw_coins);
        app_draw_center(txt, 184, COL_CREAM, COL_SHADOW, 1);
        app_fmt_uint(txt, "BEST ", sw_best);
        app_draw_center(txt, 202, COL_CREAM, COL_SHADOW, 1);
        app_draw_button(&SW_BTN_RETRY);
        app_draw_button(&SW_BTN_MENU_O);
    }
    if (sw_flash > FLASH_FRAMES - 2) gpu_rect(0, 0, FB_W, FB_H, COL_WHITE);
}
