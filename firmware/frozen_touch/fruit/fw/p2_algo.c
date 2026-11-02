/* Integer D1/P2 decode and crop ROI.  Shared by the RISC-V firmware and the host
 * reference (tools/host_ref).  Mirrors p2/src: det.decode_boxes (top-1),
 * eval_e2e.detect_top1, data.box_to_center_scale (PAD 1.25), data.crop_matrix,
 * data.decode; fixed point Q8 (camera px) and Q16 (ROI). */
#include "p2_algo.h"
#include "p2_model.h"

const uint8_t p2_edges[P2_NSEG][2] = {
    {0, 1}, {0, 2}, {2, 4}, {1, 3}, {3, 5}, {0, 6}, {1, 7}, {6, 7}, {6, 8}, {8, 10}, {7, 9}, {9, 11}};

static int32_t clamp32(int32_t v, int32_t lo, int32_t hi) { return v < lo ? lo : v > hi ? hi : v; }

void p2_det_decode(const int8_t *heat, const int8_t (*box)[4], p2_box *out) {
    /* top-1 of 3x3 peaks == global maximum; first index wins ties */
    int best = 0;
    for (int i = 1; i < P2_DET_GH * P2_DET_GW; i++)
        if (heat[i] > heat[best]) best = i;
    out->score_q = heat[best];
    out->valid = heat[best] >= P2_DET_T_Q;
    int r = best / P2_DET_GW, c = best % P2_DET_GW;
    /* box exponent -3: value_q8 = q * 32 */
    int32_t cy = r * 16 * 256 + 1920 + box[best][0] * 32;
    int32_t cx = c * 16 * 256 + 1920 + box[best][1] * 32;
    int32_t bh = (int32_t)p2_exp_q8[box[best][2] + 128];
    int32_t bw = (int32_t)p2_exp_q8[box[best][3] + 128];
    /* D1 input px -> camera px: x*8, (y-3)*8 (letterbox inverse) */
    int32_t ax = (cx - bw / 2) * 8, bx = (cx + bw / 2) * 8;
    int32_t ay = (cy - bh / 2 - 3 * 256) * 8, by = (cy + bh / 2 - 3 * 256) * 8;
    ax = clamp32(ax, 0, P2_CAM_W * 256); bx = clamp32(bx, 0, P2_CAM_W * 256);
    ay = clamp32(ay, 0, P2_CAM_H * 256); by = clamp32(by, 0, P2_CAM_H * 256);
    if (bx - ax < 2 * 256) bx = ax + 2 * 256;
    if (by - ay < 2 * 256) by = ay + 2 * 256;
    out->x0 = ax; out->y0 = ay; out->x1 = bx; out->y1 = by;
}

void p2_box_to_roi(const p2_box *b, p2_roi *roi) {
    int32_t w = b->x1 - b->x0, h = b->y1 - b->y0;           /* Q8 */
    int32_t cx = b->x0 + w / 2, cy = b->y0 + h / 2;
    if (w * 3 > h * 2) h = w * 3 / 2; else w = h * 2 / 3;      /* aspect 192:288 */
    w = w * 5 / 4;                                              /* PAD 1.25 */
    uint32_t step = ((uint32_t)w << 8) / P2_CROP_W;             /* camera px per crop px, Q16 */
    roi->step_q16 = step;
    roi->x0_q16 = cx * 256 - (int32_t)(96 * step);
    roi->y0_q16 = cy * 256 - (int32_t)(144 * step);
}

void p2_pose_decode(const int8_t (*heat)[12], const int8_t (*off)[24], const p2_roi *roi, p2_kp kp[P2_NJ]) {
    for (int j = 0; j < P2_NJ; j++) {
        int best = 0;
        for (int p = 1; p < P2_POSE_GH * P2_POSE_GW; p++)
            if (heat[p][j] > heat[best][j]) best = p;
        int r = best / P2_POSE_GW, c = best % P2_POSE_GW;
        /* offset exponent -1: value_q8 = q * 128 */
        int32_t y = r * 16 * 256 + 1920 + off[best][j] * 128;
        int32_t x = c * 16 * 256 + 1920 + off[best][j + 12] * 128;
        /* camera = origin + crop * step  (Q16 origin, Q8 crop, Q16 step) */
        kp[j].x_q8 = (int32_t)(((int64_t)roi->x0_q16 + (((int64_t)x * roi->step_q16) >> 8)) >> 8);
        kp[j].y_q8 = (int32_t)(((int64_t)roi->y0_q16 + (((int64_t)y * roi->step_q16) >> 8)) >> 8);
        kp[j].logit_q = heat[best][j];
        kp[j].valid = heat[best][j] >= P2_KP_T_Q;
    }
}

void p2_cam_to_lcd(int32_t x_q8, int32_t y_q8, int32_t *lx, int32_t *ly) {
    /* camera -> display scale (LCD x4/5, HDMI 1:1); round to nearest pixel */
    *lx = (x_q8 * P2_DISP_NUM / P2_DISP_DEN + 128) >> 8;
    *ly = P2_LCD_Y0 + ((y_q8 * P2_DISP_NUM / P2_DISP_DEN + 128) >> 8);
}

static uint32_t isqrt(uint32_t v) {
    uint32_t r = 0, bit = 1u << 30;
    while (bit > v) bit >>= 2;
    while (bit) {
        if (v >= r + bit) { v -= r + bit; r = (r >> 1) + bit; } else r >>= 1;
        bit >>= 2;
    }
    return r;
}

void p2_make_seg(int32_t x1, int32_t y1, int32_t x2, int32_t y2, int32_t half_width, p2_seg *s) {
    int32_t dx = x2 - x1, dy = y2 - y1;
    s->dx = (int16_t)dx; s->dy = (int16_t)dy;
    s->c00 = -x1 * dy + y1 * dx;
    s->d00 = -x1 * dx - y1 * dy;
    s->len2 = dx * dx + dy * dy;
    s->lim = half_width * (int32_t)isqrt((uint32_t)s->len2);
}

/* ---------------- temporal smoothing ---------------- */
/* alpha(fc) = r / (1 + r), r = 2*pi*fc / FPS; fc in Q8 Hz -> alpha in Q16 */
static int32_t oe_alpha(int32_t fc_q8) {
    /* 2*pi*10/FPS_X10 in Q24, computed once by the compiler for constant FPS */
    const int64_t k_q24 = (int64_t)(6.283185307179586 * 10.0 * 16777216.0) / P2_FPS_X10;
    int64_t r_q16 = (k_q24 * fc_q8) >> 16;            /* Q24 * Q8 >> 16 = Q16 */
    return (int32_t)((r_q16 << 16) / (65536 + r_q16));
}

void p2_oe_reset(p2_oe *f) {
    for (int j = 0; j < P2_NJ; j++) f->j[j].on = 0;
}

static int32_t oe_axis(int32_t *xh, int32_t *dh, int32_t x, int32_t min_cutoff_q8, int32_t beta_q16) {
    const int32_t ad = oe_alpha(256);                  /* derivative cutoff 1 Hz */
    int32_t d = x - *xh;                               /* Q8 px per frame */
    *dh += (int32_t)(((int64_t)ad * (d - *dh)) >> 16);
    int32_t ad_abs = *dh < 0 ? -*dh : *dh;
    /* fc = min_cutoff + beta * |dx| * FPS  (|dx| per frame, Q8) */
    int32_t fc = min_cutoff_q8 + (int32_t)(((int64_t)ad_abs * beta_q16 * P2_FPS_X10 / 10) >> 16);
    int32_t a = oe_alpha(fc);
    *xh += (int32_t)(((int64_t)a * (x - *xh)) >> 16);
    return *xh;
}

void p2_oe_apply(p2_oe *f, p2_kp kp[P2_NJ], int32_t min_cutoff_q8, int32_t beta_q16) {
    for (int j = 0; j < P2_NJ; j++) {
        p2_oe_joint *s = &f->j[j];
        if (!kp[j].valid || !s->on) {                  /* unreliable or new: restart this joint */
            s->x = kp[j].x_q8; s->y = kp[j].y_q8; s->dx = 0; s->dy = 0; s->on = kp[j].valid;
            continue;
        }
        kp[j].x_q8 = oe_axis(&s->x, &s->dx, kp[j].x_q8, min_cutoff_q8, beta_q16);
        kp[j].y_q8 = oe_axis(&s->y, &s->dy, kp[j].y_q8, min_cutoff_q8, beta_q16);
    }
}

void p2_box_smooth(p2_box *s, int *have, const p2_box *b, int32_t a_q8) {
    if (!b->valid) return;
    if (!*have || a_q8 >= 256) { *s = *b; *have = 1; return; }
    s->x0 += (a_q8 * (b->x0 - s->x0)) >> 8;
    s->y0 += (a_q8 * (b->y0 - s->y0)) >> 8;
    s->x1 += (a_q8 * (b->x1 - s->x1)) >> 8;
    s->y1 += (a_q8 * (b->y1 - s->y1)) >> 8;
    s->score_q = b->score_q; s->valid = 1;
}

/* ---------------- hardware post-processing reference ---------------- */
#include "p2_oe_lut.h"

uint32_t p2_pack_joint(const p2_kp *k) {
    int32_t x = k->x_q8 >> 4, y = k->y_q8 >> 4;
    x = clamp32(x, 0, 32767); y = clamp32(y, 0, 32767);
    return ((uint32_t)(k->valid != 0) << 31) | ((uint32_t)y << 16) | (uint32_t)x;
}

void p2_post_reset(p2_post_state *s) {
    for (int j = 0; j < P2_NJ; j++) s->on[j] = 0;
}

static int32_t post_axis(int32_t *xh, int32_t *dh, int32_t x) {
    int32_t d = x - *xh;
    *dh += (int32_t)(((int64_t)p2_oe_lut[16] * (d - *dh)) >> 16);
    int32_t a = *dh < 0 ? -*dh : *dh;
    int32_t fc = P2_OE_MC_Q8 + (int32_t)(((int64_t)a * P2_OE_KB_Q16) >> 16);
    int32_t idx = fc >> 4; if (idx > 1023) idx = 1023;
    *xh += (int32_t)(((int64_t)p2_oe_lut[idx] * (x - *xh)) >> 16);
    return *xh;
}

static int32_t post_map(int32_t v_q8) {
    return (int32_t)(((((int64_t)v_q8 * P2_DISP_MUL_Q16) >> 16) + 128) >> 8);
}

void p2_post(p2_post_state *s, const uint32_t raw[P2_NJ], uint32_t dots[P2_NJ], uint32_t segs[P2_NSEG][5],
             uint32_t *dot_en, uint32_t *seg_en) {
    int32_t lx[P2_NJ], ly[P2_NJ];
    uint32_t den = 0, sen = 0;
    for (int j = 0; j < P2_NJ; j++) {
        int v = raw[j] >> 31;
        int32_t x = (int32_t)(raw[j] & 0x7fff) << 4, y = (int32_t)((raw[j] >> 16) & 0x7fff) << 4;
        if (!v || !s->on[j]) {
            s->xh[j] = x; s->yh[j] = y; s->dxh[j] = 0; s->dyh[j] = 0; s->on[j] = (uint8_t)v;
        } else {
            post_axis(&s->xh[j], &s->dxh[j], x);
            post_axis(&s->yh[j], &s->dyh[j], y);
        }
        lx[j] = post_map(s->xh[j]);
        ly[j] = P2_LCD_Y0 + post_map(s->yh[j]);
        if (v) den |= 1u << j;
        dots[j] = ((uint32_t)(ly[j] & 0xfff) << 16) | (uint32_t)(lx[j] & 0xfff);
    }
    for (int e = 0; e < P2_NSEG; e++) {
        int a = p2_edges[e][0], b = p2_edges[e][1];
        p2_seg g;
        p2_make_seg(lx[a], ly[a], lx[b], ly[b], 2, &g);
        segs[e][0] = (uint32_t)g.c00; segs[e][1] = (uint32_t)g.d00;
        segs[e][2] = ((uint32_t)(uint16_t)g.dy << 16) | (uint16_t)g.dx;
        segs[e][3] = (uint32_t)g.lim; segs[e][4] = (uint32_t)g.len2;
        if ((den >> a & 1) && (den >> b & 1)) sen |= 1u << e;
    }
    *dot_en = den; *seg_en = sen;
}
