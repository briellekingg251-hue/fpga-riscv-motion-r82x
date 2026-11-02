/* Resident loader artwork: shapes and text only (no sprite RAM, which holds
 * the previous game's images).  Palette 224..255 belongs to the loader while
 * the menu is shown; every game uploads its own palette when it starts.
 * Hit regions stay in control_menu.h; this file only draws.
 */
#ifndef FN_LOADER_UI_H
#define FN_LOADER_UI_H
#include "gpu.h"
#include "assets.h"
#include "control.h"
/* Artwork is drawn rarely: keep it compact inside the 24 KiB loader region. */
#define UI_FN static __attribute__((noinline, optimize("Os")))

enum {
    UI_BAND = 224,                 /* 224..239 background gradient */
    UI_PANEL = 240, UI_PANEL_HI, UI_CYAN, UI_ORANGE, UI_GREEN, UI_PINK,
    UI_YELLOW, UI_DIM, UI_SHADOW, UI_RED, UI_CYAN_DK, UI_ORANGE_DK,
    UI_PURPLE, UI_GREEN_DK, UI_PINK_DK, UI_WHITE
};
static const uint32_t ui_colors[16] = {
    0x141c3du, 0x2b376bu, 0x38d8ffu, 0xff9b2fu, 0x63e27cu, 0xff4f9au,
    0xffd84au, 0x9aa7cfu, 0x04050du, 0xff4d4du, 0x0f4a66u, 0x6b3511u,
    0x9b74ffu, 0x1d5a33u, 0x5e1838u, 0xffffffu
};

UI_FN void ui_palette(void)
{
    /* 16-step night gradient #0a0f2c -> #3a1248 */
    for (unsigned i = 0; i < 16; ++i) {
        uint32_t r = 0x0a + (0x3a - 0x0a) * i / 15, g = 0x0f + (0x12 - 0x0f) * i / 15;
        uint32_t b = 0x2c + (0x48 - 0x2c) * i / 15;
        gpu_palette(UI_BAND + i, r << 16 | g << 8 | b);
    }
    for (unsigned i = 0; i < 15; ++i) gpu_palette(UI_PANEL + i, ui_colors[i]);
}

UI_FN void ui_circ(int cx, int cy, int r, unsigned color) { gpu_circle(cx, cy, r, color); }
UI_FN int ui_text_w(const char *s, int scale)
{
    int w = 0;
    for (; *s; ++s) w += (fn_glyph_width[(unsigned char)*s & 127] + 1) * scale;
    return w;
}
UI_FN void ui_text_c(int cx, int y, const char *s, unsigned color, int scale)
{
    gpu_text(cx - ui_text_w(s, scale) / 2, y, s, color, scale);
}
UI_FN void ui_text_sh(int x, int y, const char *s, unsigned color, int scale)
{
    gpu_text(x + scale, y + scale, s, UI_SHADOW, scale);
    gpu_text(x, y, s, color, scale);
}
UI_FN void ui_dither(int x, int y, int w, int h, unsigned color)
{
    gpu_wr(GPU_FLAGS, GPU_FLAG_DITHER);
    gpu_rect(x, y, w, h, color);
    gpu_wr(GPU_FLAGS, 0);
}
UI_FN int ui_abs(int v) { return v < 0 ? -v : v; }
/* Round-capped thick line from overlapping discs. */
UI_FN void ui_line(int x0, int y0, int x1, int y1, int r, unsigned color)
{
    int dx = x1 - x0, dy = y1 - y0;
    int n = (ui_abs(dx) > ui_abs(dy) ? ui_abs(dx) : ui_abs(dy)) / 2 + 1;
    for (int k = 0; k <= n; ++k) ui_circ(x0 + dx * k / n, y0 + dy * k / n, r, color);
}
UI_FN void ui_ring(int cx, int cy, int r, int t, unsigned color, unsigned fill)
{
    ui_circ(cx, cy, r, color);
    ui_circ(cx, cy, r - t, fill);
}
/* Panel with drop shadow and a coloured frame. */
UI_FN void ui_card(int x, int y, int w, int h, unsigned frame)
{
    ui_dither(x + 4, y + 4, w, h, UI_SHADOW);
    gpu_rect(x, y, w, h, frame);
    gpu_rect(x + 2, y + 2, w - 4, h - 4, UI_PANEL);
}
UI_FN void ui_pill(int x, int y, const char *s, unsigned fill, unsigned text)
{
    int w = ui_text_w(s, 1) + 12;
    gpu_rect(x + 2, y, w - 4, 16, fill);
    gpu_rect(x, y + 2, w, 12, fill);
    gpu_text(x + 6, y, s, text, 1);
}
UI_FN void ui_button(int x, int y, int w, int h, const char *s, unsigned frame, unsigned text)
{
    ui_card(x, y, w, h, frame);
    ui_text_c(x + w / 2, y + (h - 16) / 2, s, text, 1);
}

UI_FN void ui_background(void)
{
    for (int i = 0; i < 16; ++i) gpu_rect(0, i * 19, FB_W, i == 15 ? FB_H - 285 : 19, UI_BAND + i);
    /* faint perspective grid in the lower half */
    for (int i = 0; i < 9; ++i) ui_dither(0, 190 + i * i * 2, FB_W, 1, UI_PURPLE);
    for (int i = -4; i <= 4; ++i) ui_line(256 + i * 18, 190, 256 + i * 70, 300, 0, UI_PANEL_HI);
}

UI_FN void ui_header(unsigned light)
{
    gpu_rect(0, 0, FB_W, 40, UI_PANEL);
    gpu_rect(0, 40, FB_W, 2, UI_CYAN);
    ui_dither(0, 42, FB_W, 2, UI_CYAN_DK);
    /* logo: chip glyph + wordmark */
    gpu_rect(12, 9, 22, 22, UI_CYAN);
    gpu_rect(15, 12, 16, 16, UI_PANEL);
    gpu_rect(19, 16, 8, 8, UI_ORANGE);
    int x = 44;
    gpu_text(x + 2, 6, "FPGA", UI_SHADOW, 2);
    x += gpu_text(x, 4, "FPGA", UI_CYAN, 2) + 6;
    ui_text_sh(x, 4, "ARCADE", UI_WHITE, 2);
    /* backlight: [-]  LIGHT nn% + level bar  [+]; hit region x>=290, y<50 */
    if (light > 100) light = 100;
    char pct[5];
    pct[0] = (char)(light >= 100 ? '1' : ' ');
    pct[1] = (char)(light >= 10 ? '0' + (light / 10) % 10 : ' ');
    pct[2] = (char)('0' + light % 10); pct[3] = '%'; pct[4] = 0;
    ui_ring(314, 20, 13, 2, UI_CYAN, UI_PANEL_HI);
    gpu_rect(307, 19, 14, 3, UI_WHITE);
    ui_ring(484, 20, 13, 2, UI_CYAN, UI_PANEL_HI);
    gpu_rect(477, 19, 14, 3, UI_WHITE);
    gpu_rect(483, 13, 3, 14, UI_WHITE);
    gpu_text(352, 6, "LIGHT", UI_DIM, 1);
    gpu_text(410, 6, pct, UI_WHITE, 1);
    gpu_rect(344, 26, 110, 6, UI_PANEL_HI);
    gpu_rect(344, 26, (int)light * 110 / 100, 6, UI_YELLOW);
}

/* Animated icons: t advances 15 times per second. */
UI_FN void ui_icon_touch(int cx, int cy, unsigned t)
{
    for (int k = 2; k >= 0; --k) {
        int r = 14 + (int)((t * 3 + (unsigned)k * 11) % 33);   /* 14..46 */
        ui_ring(cx, cy, r, 2, r > 36 ? UI_CYAN_DK : UI_CYAN, UI_PANEL);
    }
    for (int k = 0; k < 6; ++k)        /* swipe trail ending at the fingertip */
        ui_circ(cx - 66 + k * 10, cy + 34 - k * 6, 1 + k / 2, k < 3 ? UI_CYAN_DK : UI_CYAN);
    ui_circ(cx, cy, 11, UI_WHITE);
    ui_circ(cx, cy, 7, UI_CYAN);
}
UI_FN void ui_icon_pose(int cx, int cy, unsigned t)
{
    int p = (int)((t * 6u) & 255u);
    int w = (p < 128 ? p - 64 : 192 - p) / 4;   /* triangle wave -16..16 */
    /* camera brackets */
    for (int i = 0; i < 4; ++i) {
        int bx = (i & 1) ? cx + 32 : cx - 46, by = (i & 2) ? cy + 40 : cy - 44;
        gpu_rect(bx, (i & 2) ? by + 2 : by, 14, 2, UI_ORANGE);
        gpu_rect((i & 1) ? bx + 12 : bx, (i & 2) ? by - 10 : by, 2, 14, UI_ORANGE);
    }
    /* 12-joint layout of the on-board pose model: shoulders, elbows, wrists,
     * hips, knees, ankles (left/right pairs); arms wave with w. */
    static const signed char ox[12] = {-10, 10, -20, 20, -30, 30, -7, 7, -14, 14, -16, 16};
    static const signed char oy[12] = {-18, -18, -22, -22, -40, -40, 12, 12, 30, 30, 46, 46};
    static const signed char wave[12] = {0, 0, -1, 1, -2, 2, 0, 0, 0, 0, 0, 0};
    static const unsigned char bone[12][2] = {
        {0,1},{0,2},{2,4},{1,3},{3,5},{0,6},{1,7},{6,7},{6,8},{8,10},{7,9},{9,11}};
    int jx[12], jy[12];
    for (int i = 0; i < 12; ++i) { jx[i] = cx + ox[i]; jy[i] = cy + oy[i] + wave[i] * w / 2; }
    for (int i = 0; i < 12; ++i)
        ui_line(jx[bone[i][0]], jy[bone[i][0]], jx[bone[i][1]], jy[bone[i][1]], 2, UI_WHITE);
    ui_circ(cx, cy - 31, 7, UI_WHITE);
    for (int i = 0; i < 12; ++i) ui_circ(jx[i], jy[i], i == 4 || i == 5 ? 4 : 3, i == 4 || i == 5 ? UI_PINK : UI_ORANGE);
}

/* Per-game artwork, name and accent; unknown packages show their folder. */
UI_FN unsigned ui_game_accent(uint32_t id)
{
    return id == CONTROL_GAME_FRUIT ? UI_GREEN : id == CONTROL_GAME_SUBWAY ? UI_ORANGE :
           id == CONTROL_GAME_PAL ? UI_PURPLE : UI_DIM;
}
UI_FN const char *ui_game_title(uint32_t id, const char *folder)
{
    return id == CONTROL_GAME_FRUIT ? "FRUIT NINJA" : id == CONTROL_GAME_SUBWAY ? "SUBWAY RUN" :
           id == CONTROL_GAME_PAL ? "SWORD & FAIRY" : folder;
}
UI_FN void ui_game_icon(uint32_t id, int cx, int cy)
{
    ui_circ(cx, cy, 15, UI_PANEL_HI);
    if (id == CONTROL_GAME_FRUIT) {
        ui_circ(cx, cy, 12, UI_GREEN);
        ui_circ(cx, cy, 10, UI_GREEN_DK);
        ui_circ(cx, cy, 8, UI_RED);
        ui_circ(cx - 3, cy - 2, 1, UI_SHADOW); ui_circ(cx + 3, cy + 1, 1, UI_SHADOW);
        ui_circ(cx - 1, cy + 4, 1, UI_SHADOW);
        ui_line(cx - 14, cy + 10, cx + 14, cy - 10, 0, UI_WHITE);
    } else if (id == CONTROL_GAME_SUBWAY) {
        ui_line(cx - 4, cy - 12, cx - 12, cy + 12, 0, UI_DIM);
        ui_line(cx + 4, cy - 12, cx + 12, cy + 12, 0, UI_DIM);
        gpu_rect(cx - 8, cy - 9, 16, 16, UI_ORANGE);
        gpu_rect(cx - 6, cy - 7, 12, 6, UI_CYAN);
        ui_circ(cx - 4, cy + 3, 1, UI_YELLOW); ui_circ(cx + 4, cy + 3, 1, UI_YELLOW);
    } else if (id == CONTROL_GAME_PAL) {
        ui_line(cx - 9, cy + 9, cx + 9, cy - 9, 1, UI_WHITE);
        ui_line(cx - 9, cy + 1, cx - 1, cy + 9, 1, UI_YELLOW);
        ui_circ(cx - 11, cy + 11, 2, UI_YELLOW);
    } else {
        gpu_rect(cx - 7, cy - 7, 14, 14, UI_DIM);
    }
}

#endif
