#include "pose_ui.h"
#include "gpu.h"
#include "assets.h"
#include "pose_input.h"

static int ui_abs(int v) { return v < 0 ? -v : v; }
static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }
static int joint_ok(const control_pose_snapshot_t *s, unsigned j)
{
    const control_joint_t *p = &s->joint[j];
    return p->valid && p->logit >= -6 && p->x >= 0 && p->x < 1280 && p->y >= 0 && p->y < 720;
}
/* Same orientation as the blade backend: mirrored, 1.5x gain about the centre,
 * so a hand reaches every screen edge without leaving the camera view. */
static int map_x(int x) { int f = 511 - x * 511 / 1279; return clampi(255 + (f - 255) * 3 / 2, 0, 511); }
static int map_y(int y) { int f = y * 299 / 719; return clampi(149 + (f - 149) * 3 / 2, 0, 299); }

void pose_ui_reset(pose_ui_t *u, uint32_t now_ms)
{
    *u = (pose_ui_t){0};
    u->now = now_ms; u->dwell_btn = -1;
}

void pose_ui_update(pose_ui_t *u, uint32_t now_ms)
{
    u->now = now_ms;
    u->body = pose_input_view(&u->snap, now_ms, POSE_UI_VIEW_MS);
    if (u->body) { u->seen_ms = u->snap.capture_ms; u->have_seen = 1; }  /* last real observation */
    for (unsigned h = 0; h < 2; ++h) {
        unsigned j = POSE_L_WRIST + h;
        u->hand_ok[h] = u->body && joint_ok(&u->snap, j);
        if (u->hand_ok[h]) { u->hx[h] = map_x(u->snap.joint[j].x); u->hy[h] = map_y(u->snap.joint[j].y); }
    }
}

int pose_ui_lost_for(const pose_ui_t *u, uint32_t ms)
{
    return u->have_seen && !u->body && u->now - u->seen_ms >= ms;
}

static int inside(const pose_ui_rect_t *b, int x, int y)
{
    return x >= b->x && x < b->x + b->w && y >= b->y && y < b->y + b->h;
}

int pose_ui_dwell(pose_ui_t *u, const pose_ui_rect_t *rects, unsigned n)
{
    int hit = -1, hand = -1;
    for (unsigned h = 0; h < 2 && hit < 0; ++h) {
        if (!u->hand_ok[h]) continue;
        for (unsigned i = 0; i < n; ++i)
            if (inside(&rects[i], u->hx[h], u->hy[h])) { hit = (int)i; hand = (int)h; break; }
    }
    if (hit < 0) { u->locked = 0; u->dwell_btn = -1; u->progress = 0; return -1; }
    if (u->locked) { u->progress = 0; return -1; }
    if (hit != u->dwell_btn || hand != u->dwell_hand) {
        u->dwell_btn = hit; u->dwell_hand = hand; u->dwell_start = u->now; u->progress = 0;
        return -1;
    }
    uint32_t held = u->now - u->dwell_start;
    if (held < POSE_UI_DWELL_MS) { u->progress = held * 256u / POSE_UI_DWELL_MS; return -1; }
    u->locked = 1; u->dwell_btn = -1; u->progress = 0;
    return hit;
}

static void line(int x0, int y0, int x1, int y1, int r, unsigned color)
{
    int dx = x1 - x0, dy = y1 - y0;
    int n = (ui_abs(dx) > ui_abs(dy) ? ui_abs(dx) : ui_abs(dy)) / 2 + 1;
    for (int k = 0; k <= n; ++k) gpu_circle(x0 + dx * k / n, y0 + dy * k / n, r, color);
}

void pose_ui_draw_cursors(const pose_ui_t *u)
{
    for (unsigned h = 0; h < 2; ++h) {
        if (!u->hand_ok[h]) continue;
        int x = u->hx[h], y = u->hy[h];
        gpu_circle(x, y, 13, COL_SHADOW);
        gpu_circle(x, y, 11, h ? COL_GOLD : COL_BLADE_GLOW);
        gpu_circle(x, y, 8, COL_INK);
        gpu_circle(x, y, 5, COL_WHITE);
        if (u->dwell_btn >= 0 && u->dwell_hand == (int)h && u->progress) {
            /* progress ring: 24 beads clockwise from 12 o'clock */
            int beads = (int)(u->progress * 24u / 256u);
            for (int i = 0; i <= beads; ++i) {
                int a = i * 256 / 24 - 64;
                gpu_circle(x + (icos(a) * 17 >> 14), y + (isin(a) * 17 >> 14), 2, COL_GREEN);
            }
        }
    }
}

void pose_ui_draw_panel(const pose_ui_t *u, int x, int y)
{
    static const unsigned char bone[12][2] = {
        {0,1},{0,2},{2,4},{1,3},{3,5},{0,6},{1,7},{6,7},{6,8},{8,10},{7,9},{9,11}};
    unsigned frame = u->body ? COL_GREEN : COL_RED;
    gpu_rect(x - 2, y - 2, 84, 49, frame);
    gpu_rect(x, y, 80, 45, COL_INK);
    if (u->body) {
        int px[12], py[12], ok[12];
        int x0 = 1280, x1 = 0, y0 = 720, y1 = 0;
        for (unsigned j = 0; j < 12; ++j) {
            ok[j] = joint_ok(&u->snap, j);
            if (!ok[j]) continue;
            int jx = u->snap.joint[j].x, jy = u->snap.joint[j].y;
            if (jx < x0) x0 = jx;
            if (jx > x1) x1 = jx;
            if (jy < y0) y0 = jy;
            if (jy > y1) y1 = jy;
        }
        /* Fit the body (plus head room) into the panel, mirror view. */
        y0 -= (y1 - y0) / 5 + 8;
        int span = (x1 - x0) * 45 > (y1 - y0) * 80 ? (x1 - x0) * 45 / 40 : (y1 - y0);
        if (span < 1) span = 1;
        int cxm = (x0 + x1) / 2;
        for (unsigned j = 0; j < 12; ++j) {
            px[j] = x + 40 - (u->snap.joint[j].x - cxm) * 40 / span;
            py[j] = y + 2 + (u->snap.joint[j].y - y0) * 40 / span;
        }
        for (unsigned i = 0; i < 12; ++i) {
            unsigned a = bone[i][0], b = bone[i][1];
            if (ok[a] && ok[b]) line(px[a], py[a], px[b], py[b], 0, COL_WHITE);
        }
        for (unsigned j = 0; j < 12; ++j)
            if (ok[j]) gpu_circle(px[j], py[j], j == 4 || j == 5 ? 2 : 1, j == 4 || j == 5 ? COL_GOLD : COL_GREEN);
        if (ok[0] && ok[1]) {
            int hr = ui_abs(px[0] - px[1]) / 4 + 2;
            gpu_circle((px[0] + px[1]) / 2, (py[0] + py[1]) / 2 - hr - 2, hr, COL_WHITE);
        }
    } else {
        /* empty camera view: dashed outline of where to stand */
        for (int k = 0; k < 6; ++k) gpu_rect(x + 34, y + 6 + k * 6, 12, 3, COL_DARK_GRAY);
        gpu_circle(x + 40, y + 6, 4, COL_DARK_GRAY);
    }
    gpu_text_shadow(x + 2, y + 46, u->body ? "PLAYER OK" : "NO PLAYER", u->body ? COL_GREEN : COL_RED, COL_SHADOW, 1);
}

void pose_ui_draw_prompt(const pose_ui_t *u, int y, const char *line1, const char *line2)
{
    (void)u;
    gpu_rect(72, y, 368, 92, COL_INK);   /* solid: hides any game hint below */
    gpu_rect(72, y, 368, 3, COL_GOLD);
    gpu_rect(72, y + 89, 368, 3, COL_GOLD);
    /* body outline icon */
    gpu_circle(116, y + 26, 9, COL_GOLD);
    line(116, y + 36, 116, y + 62, 2, COL_GOLD);
    line(100, y + 46, 132, y + 46, 2, COL_GOLD);
    line(116, y + 62, 106, y + 82, 2, COL_GOLD);
    line(116, y + 62, 126, y + 82, 2, COL_GOLD);
    gpu_text_shadow(150, y + 18, line1, COL_WHITE, COL_SHADOW, 2);
    gpu_text_shadow(150, y + 58, line2, COL_CREAM, COL_SHADOW, 1);
}
