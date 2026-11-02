/* SPDX-License-Identifier: GPL-2.0-or-later */
/* GPU drawing: NES picture as 16 sprite tiles, touch controls, ROM list.
 *
 * Palette: 1..64 hold the NES colours (texel 0 is transparent to sprites);
 * UI colours live at 200+ so they never alias a NES colour.  Every frame is a
 * complete redraw into the hidden framebuffer followed by a swap. */
#include "gpu.h"
#include "nes_board.h"
#include "nes_platform.h"

enum {
    UI_BG = 200, UI_PANEL, UI_EDGE, UI_TEXT, UI_DIM, UI_RED, UI_RED_HI, UI_GOLD,
    UI_BLUE, UI_PRESS, UI_SHADOW
};
static const uint32_t ui_rgb[] = {
    0x0c0e14, 0x20242e, 0x5a6378, 0xf0f0f0, 0x9097a8, 0xc8283a, 0xff7878, 0xffc440,
    0x3c78dc, 0xffe08a, 0x000000
};
static const uint8_t nes_rgb[64][3] = {
#include "nes_palette_rgb.inc"
};

#define TILE         64
#define LAST_ROWS    (NES_VIEW_LINES - 3 * TILE)   /* 32 */
#define TEXEL_HALF   0x8000u                       /* sample texel centres */
#define TEXEL_STEP   0x10000u                      /* 1:1 in 16.16 */
#define GPU_TEXEL_CMD 26u
#define GPU_READY    4u

static uint32_t texels;

uint32_t nes_video_texels(void) { return texels; }
int nes_video_ready(void) { return (GPU_REG_STATUS & GPU_READY) != 0; }
/* Bounded: after ~0.1 s the GPU is assumed wedged and drawing proceeds
 * (commands still queue in order; the FIFO stalls stores when full). */
void nes_video_wait(void)
{
    uint64_t limit = nes_cycles() + nes_cpu_hz() / 10u;
    while (!nes_video_ready() && nes_cycles() < limit) {}
}

static void texel_sink(uint32_t word) { gpu_wr(GPU_TEXEL_CMD, word); }

void nes_video_init(void)
{
    nes_video_wait();
    for (unsigned i = 0; i < NES_PAL_COLORS; ++i)
        gpu_palette(NES_PAL_BASE + i, (uint32_t)nes_rgb[i][0] << 16 | (uint32_t)nes_rgb[i][1] << 8 | nes_rgb[i][2]);
    for (unsigned i = 0; i < sizeof ui_rgb / sizeof ui_rgb[0]; ++i) gpu_palette(UI_BG + i, ui_rgb[i]);
    nes_frame_invalidate();
    gpu_clear(UI_BG);
    gpu_swap();
}

static void text_centered(int cx, int y, const char *s, unsigned color, int scale)
{
    gpu_text(cx - gpu_text_width(s, scale) / 2, y, s, color, scale);
}

static void frame_rect(int x, int y, int w, int h, unsigned color)
{
    gpu_rect(x, y, w, 1, color);
    gpu_rect(x, y + h - 1, w, 1, color);
    gpu_rect(x, y, 1, h, color);
    gpu_rect(x + w - 1, y, 1, h, color);
}

static void draw_picture(void)
{
    gpu_wr(GPU_FLAGS, 0);
    gpu_wr(GPU_U0, TEXEL_HALF); gpu_wr(GPU_V0, TEXEL_HALF);
    gpu_wr(GPU_DUDX, TEXEL_STEP); gpu_wr(GPU_DVDX, 0);
    gpu_wr(GPU_DUDY, 0); gpu_wr(GPU_DVDY, TEXEL_STEP);
    for (unsigned ty = 0; ty < NES_TILE_ROWS; ++ty) {
        unsigned rows = ty == NES_TILE_ROWS - 1u ? LAST_ROWS : TILE;
        gpu_wr(GPU_SIZE, rows << 16 | TILE);
        for (unsigned tx = 0; tx < NES_TILE_COLS; ++tx) {
            gpu_wr(GPU_DST, (uint32_t)(NES_SCREEN_Y + ty * TILE) << 16 | (NES_SCREEN_X + tx * TILE));
            gpu_wr(GPU_CMD_SPRITE, NES_TILE_SLOT0 + ty * NES_TILE_COLS + tx);
        }
    }
}

static void draw_dpad(uint32_t pad)
{
    const int cx = NES_DPAD_CX, cy = NES_DPAD_CY, arm = NES_DPAD_ARM, half = NES_DPAD_WIDTH / 2;
    gpu_rect(cx - half, cy - arm - half, NES_DPAD_WIDTH, 2 * (arm + half), UI_PANEL);
    gpu_rect(cx - arm - half, cy - half, 2 * (arm + half), NES_DPAD_WIDTH, UI_PANEL);
    if (pad & NES_PAD_UP) gpu_rect(cx - half, cy - arm - half, NES_DPAD_WIDTH, arm, UI_PRESS);
    if (pad & NES_PAD_DOWN) gpu_rect(cx - half, cy + half, NES_DPAD_WIDTH, arm, UI_PRESS);
    if (pad & NES_PAD_LEFT) gpu_rect(cx - arm - half, cy - half, arm, NES_DPAD_WIDTH, UI_PRESS);
    if (pad & NES_PAD_RIGHT) gpu_rect(cx + half, cy - half, arm, NES_DPAD_WIDTH, UI_PRESS);
    gpu_circle(cx, cy, 5, UI_EDGE);
}

static void draw_round_button(int cx, int cy, const char *label, int pressed)
{
    gpu_circle(cx, cy + 2, NES_AB_RADIUS, UI_SHADOW);
    gpu_circle(cx, cy, NES_AB_RADIUS, pressed ? UI_RED_HI : UI_RED);
    text_centered(cx, cy - 8, label, UI_TEXT, 1);
}

static void draw_controls(uint32_t pad, unsigned menu_pct)
{
    draw_dpad(pad);
    draw_round_button(NES_B_CX, NES_B_CY, "B", (pad & NES_PAD_B) != 0);
    draw_round_button(NES_A_CX, NES_A_CY, "A", (pad & NES_PAD_A) != 0);
    for (unsigned i = 0; i < nes_button_count; ++i) {
        const nes_button_t *b = nes_buttons + i;
        if (b->bit == NES_PAD_MENU) {
            /* Hold-to-quit: the button fills left to right while held. */
            gpu_rect(b->x, b->y, b->w, b->h, UI_PANEL);
            if (menu_pct) gpu_rect(b->x, b->y, b->w * (int)menu_pct / 100, b->h, UI_RED);
        } else {
            gpu_rect(b->x, b->y, b->w, b->h, (pad & b->bit) ? UI_PRESS : UI_PANEL);
        }
        frame_rect(b->x, b->y, b->w, b->h, UI_EDGE);
        text_centered(b->x + b->w / 2, b->y + (b->h - 16) / 2, b->label, UI_TEXT, 1);
    }
    text_centered(NES_SCREEN_X / 2, 40, "HOLD MENU", UI_DIM, 1);
}

void nes_video_line(const uint16_t *line, unsigned y)
{
    texels += nes_frame_upload_line(line, y, texel_sink);
}

void nes_video_present(uint32_t pad, unsigned menu_pct)
{
    gpu_clear(UI_BG);
    draw_picture();
    frame_rect(NES_SCREEN_X - 1, NES_SCREEN_Y - 1, NES_VIEW_W + 2, NES_VIEW_LINES + 2, UI_EDGE);
    draw_controls(pad, menu_pct);
    gpu_swap();
}

void nes_video_message(const char *title, const char *detail)
{
    nes_video_wait();
    gpu_clear(UI_BG);
    gpu_rect(56, 96, 400, 108, UI_PANEL);
    frame_rect(56, 96, 400, 108, UI_RED);
    text_centered(256, 116, title, UI_TEXT, 1);
    if (detail) text_centered(256, 148, detail, UI_DIM, 1);
    text_centered(256, 176, "TOUCH TO CONTINUE", UI_GOLD, 1);
    gpu_swap();
    uart_puts("NES_MESSAGE ");
    uart_puts(title);
    if (detail) { uart_puts(" / "); uart_puts(detail); }
    uart_puts("\n");
}

void nes_video_progress(const char *title, uint32_t done, uint32_t total)
{
    nes_video_wait();
    gpu_clear(UI_BG);
    text_centered(256, 120, title, UI_TEXT, 1);
    gpu_rect(106, 150, 300, 10, UI_PANEL);
    gpu_rect(106, 150, total ? (int)((uint64_t)done * 300u / total) : 0, 10, UI_BLUE);
    gpu_swap();
}

static void menu_button(int x, int w, const char *label, unsigned color)
{
    gpu_rect(x, NES_MENU_BTN_Y, w, NES_MENU_BTN_H, color);
    frame_rect(x, NES_MENU_BTN_Y, w, NES_MENU_BTN_H, UI_EDGE);
    text_centered(x + w / 2, NES_MENU_BTN_Y + 12, label, UI_TEXT, 1);
}

static void draw_entry(const nes_entry_t *e, int y)
{
    char mapper[12] = "MAPPER ";
    unsigned m = e->mapper, n = 7;
    if (m >= 100) mapper[n++] = (char)('0' + m / 100);
    if (m >= 10) mapper[n++] = (char)('0' + m / 10 % 10);
    mapper[n++] = (char)('0' + m % 10);
    mapper[n] = 0;
    gpu_rect(NES_MENU_LIST_X, y + 2, NES_MENU_LIST_W, NES_MENU_ROW_H - 4, UI_PANEL);
    gpu_rect(NES_MENU_LIST_X, y + 2, 4, NES_MENU_ROW_H - 4, e->usable ? UI_RED : UI_EDGE);
    gpu_text(NES_MENU_LIST_X + 14, y + 7, e->name, e->usable ? UI_TEXT : UI_DIM, 1);
    gpu_text(NES_MENU_LIST_X + 300, y + 7, e->usable ? mapper : "UNSUPPORTED", UI_DIM, 1);
}

void nes_video_menu(const nes_menu_t *m, const char *status)
{
    char page[16] = "PAGE ";
    unsigned pages = nes_menu_pages(m), n = 5;
    page[n++] = (char)('0' + (m->page + 1) / 10 % 10);
    page[n++] = (char)('0' + (m->page + 1) % 10);
    page[n++] = '/';
    page[n++] = (char)('0' + pages / 10 % 10);
    page[n++] = (char)('0' + pages % 10);
    page[n] = 0;
    nes_video_wait();
    gpu_clear(UI_BG);
    gpu_rect(0, 0, NES_CANVAS_W, 40, UI_PANEL);
    gpu_text(16, 8, "NES", UI_RED, 2);
    gpu_text(80, 12, "FAMICOM CARTRIDGES ON SD:/GAMES/NES", UI_DIM, 1);
    gpu_text(420, 12, page, UI_DIM, 1);
    for (unsigned r = 0; r < NES_MENU_ROWS; ++r) {
        unsigned index = m->page * NES_MENU_ROWS + r;
        if (index >= m->count) break;
        draw_entry(&m->entry[index], NES_MENU_LIST_Y + (int)(r * NES_MENU_ROW_H));
    }
    if (!m->count) text_centered(256, 120, "NO .NES FILES FOUND", UI_DIM, 1);
    if (status) text_centered(256, NES_MENU_BTN_Y - 17, status, UI_GOLD, 1);
    menu_button(NES_MENU_PREV_X, NES_MENU_PREV_W, "< PREV", UI_PANEL);
    menu_button(NES_MENU_EXIT_X, NES_MENU_EXIT_W, "EXIT", UI_RED);
    menu_button(NES_MENU_NEXT_X, NES_MENU_NEXT_W, "NEXT >", UI_PANEL);
    gpu_swap();
}
