/* SPDX-License-Identifier: GPL-3.0-or-later */
/* miniSDL video for the GPU v2 display engine.
 *
 * PAL draws into 8-bit 320x200 software surfaces.  The display surface
 * returned by SDL_SetVideoMode is presented by uploading the changed 64x64
 * tiles into sprite slots 0..19 (GPU op 26) and drawing them 1:1 at
 * (PAL_VIEW_X, PAL_VIEW_Y) of the 512x300 framebuffer, followed by the touch
 * control overlay and a buffer swap.  The PAL palette is the GPU palette,
 * which is applied at scan-out exactly like the VGA DAC (fades included).
 *
 * A frame is only submitted while the GPU is idle; otherwise it is marked
 * pending and flushed from pal_video_service() (event polling and delays), so
 * the CPU never blocks on vertical sync and at most one frame is in flight.
 */
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <SDL.h>
#include "../../gpu.h"
#include "../pal_touch.h"
#include "pal_port.h"

#define TILE 64
#define TILES_X 5
#define TILES_Y 4
#define DISPLAY_TILE (TILE * PAL_SCALE_NUM / PAL_SCALE_DEN)
#define SCALE_STEP ((65536u * PAL_SCALE_DEN + PAL_SCALE_NUM - 1) / PAL_SCALE_NUM) /* Q16.16 */

static SDL_Surface *screen;
static uint8_t shadow[PAL_VIEW_H][PAL_VIEW_W];
static uint8_t shadow_valid[TILES_Y][TILES_X];
static uint32_t gpu_palette_shadow[256];
static int palette_known;
static int frame_pending;
static uint8_t overlay_light = 255, overlay_dark = 0;
static uint32_t presented_frames, uploaded_tiles;

static int gpu_idle(void) { return (GPU_REG_STATUS & 4u) != 0; }

/* ------------------------------------------------------------ surfaces */
static inline int mask_to_shift(uint32_t mask)
{
    switch (mask) {
    case 0x000000ff: return 0;
    case 0x0000ff00: return 8;
    case 0x00ff0000: return 16;
    default: return 24;
    }
}

SDL_Surface *SDL_CreateRGBSurface(uint32_t flags, int width, int height, int depth,
                                  uint32_t Rmask, uint32_t Gmask, uint32_t Bmask, uint32_t Amask)
{
    SDL_Surface *s;
    assert(depth == 8 || depth == 32);
    s = calloc(1, sizeof *s);
    assert(s);
    s->flags = flags;
    s->format = calloc(1, sizeof *s->format);
    assert(s->format);
    if (depth == 8) {
        s->format->palette = malloc(sizeof(SDL_Palette));
        assert(s->format->palette);
        s->format->palette->colors = calloc(256, sizeof(SDL_Color));
        assert(s->format->palette->colors);
        s->format->palette->ncolors = 256;
    } else {
        s->format->Rmask = Rmask; s->format->Rshift = (uint8_t)mask_to_shift(Rmask);
        s->format->Gmask = Gmask; s->format->Gshift = (uint8_t)mask_to_shift(Gmask);
        s->format->Bmask = Bmask; s->format->Bshift = (uint8_t)mask_to_shift(Bmask);
        s->format->Amask = Amask; s->format->Ashift = (uint8_t)mask_to_shift(Amask);
    }
    s->format->BitsPerPixel = (uint8_t)depth;
    s->format->BytesPerPixel = (uint8_t)(depth / 8);
    s->w = width;
    s->h = height;
    s->pitch = (uint16_t)(width * depth / 8);
    if (!(flags & SDL_PREALLOC)) {
        s->pixels = calloc(1, (size_t)s->pitch * (size_t)height);
        assert(s->pixels);
    }
    return s;
}

SDL_Surface *SDL_CreateRGBSurfaceFrom(void *pixels, int width, int height, int depth, int pitch,
                                      uint32_t Rmask, uint32_t Gmask, uint32_t Bmask, uint32_t Amask)
{
    SDL_Surface *s = SDL_CreateRGBSurface(SDL_PREALLOC, width, height, depth, Rmask, Gmask, Bmask, Amask);
    assert(pitch == s->pitch);
    s->pixels = pixels;
    return s;
}

void SDL_FreeSurface(SDL_Surface *s)
{
    if (!s) return;
    if (s == screen) screen = NULL;
    if (s->format) {
        if (s->format->palette) {
            free(s->format->palette->colors);
            free(s->format->palette);
        }
        free(s->format);
    }
    if (s->pixels && !(s->flags & SDL_PREALLOC)) free(s->pixels);
    free(s);
}

SDL_Surface *SDL_SetVideoMode(int width, int height, int bpp, uint32_t flags)
{
    assert(bpp == 8 && width == PAL_VIEW_W && height == PAL_VIEW_H);
    screen = SDL_CreateRGBSurface(flags, width, height, bpp, 0, 0, 0, 0);
    memset(shadow_valid, 0, sizeof shadow_valid);
    frame_pending = 1;
    return screen;
}

/* SDL 1.2 semantics: NULL rectangles mean the whole surface; the
 * destination is clipped and dstrect receives the final blit size. */
void SDL_BlitSurface(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect)
{
    int sx, sy, w, h, dx, dy;
    assert(src && dst && src->format->BitsPerPixel == 8 && dst->format->BitsPerPixel == 8);
    sx = srcrect ? srcrect->x : 0;
    sy = srcrect ? srcrect->y : 0;
    w = srcrect ? srcrect->w : src->w;
    h = srcrect ? srcrect->h : src->h;
    dx = dstrect ? dstrect->x : 0;
    dy = dstrect ? dstrect->y : 0;
    if (sx < 0) { w += sx; dx -= sx; sx = 0; }
    if (sy < 0) { h += sy; dy -= sy; sy = 0; }
    if (sx + w > src->w) w = src->w - sx;
    if (sy + h > src->h) h = src->h - sy;
    if (dx < 0) { w += dx; sx -= dx; dx = 0; }
    if (dy < 0) { h += dy; sy -= dy; dy = 0; }
    if (dx + w > dst->w) w = dst->w - dx;
    if (dy + h > dst->h) h = dst->h - dy;
    if (w <= 0 || h <= 0) w = h = 0;
    if (dstrect) { dstrect->x = (int16_t)dx; dstrect->y = (int16_t)dy; dstrect->w = (uint16_t)w; dstrect->h = (uint16_t)h; }
    for (int y = 0; y < h; ++y)
        memcpy(dst->pixels + (size_t)(dy + y) * dst->pitch + dx, src->pixels + (size_t)(sy + y) * src->pitch + sx, (size_t)w);
}

void SDL_FillRect(SDL_Surface *dst, SDL_Rect *dstrect, uint32_t color)
{
    int x = dstrect ? dstrect->x : 0, y = dstrect ? dstrect->y : 0;
    int w = dstrect ? dstrect->w : dst->w, h = dstrect ? dstrect->h : dst->h;
    assert(dst->format->BitsPerPixel == 8);
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > dst->w) w = dst->w - x;
    if (y + h > dst->h) h = dst->h - y;
    for (int j = 0; j < h; ++j) memset(dst->pixels + (size_t)(y + j) * dst->pitch + x, (int)(color & 255u), (size_t)(w > 0 ? w : 0));
}

void SDL_SoftStretch(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect)
{
    int w = srcrect ? srcrect->w : src->w, h = srcrect ? srcrect->h : src->h;
    assert(dstrect && w == dstrect->w && h == dstrect->h);
    SDL_Rect rect = {srcrect ? srcrect->x : 0, srcrect ? srcrect->y : 0, (uint16_t)w, (uint16_t)h};
    SDL_BlitSurface(src, &rect, dst, dstrect);
}

static void choose_overlay_colors(void)
{
    int best_light = -1, best_dark = 1 << 30;
    for (unsigned i = 0; i < 256; ++i) {
        uint32_t c = gpu_palette_shadow[i];
        int y = 2 * ((c >> 16) & 255) + 5 * ((c >> 8) & 255) + (c & 255);
        int dark = abs(y - 8 * 40);
        if (y > best_light) { best_light = y; overlay_light = (uint8_t)i; }
        if (dark < best_dark) { best_dark = dark; overlay_dark = (uint8_t)i; }
    }
}

void SDL_SetPalette(SDL_Surface *s, int flags, SDL_Color *colors, int firstcolor, int ncolors)
{
    (void)flags;
    assert(s && s->format && s->format->palette && firstcolor == 0 && ncolors <= 256);
    s->format->palette->ncolors = ncolors;
    memcpy(s->format->palette->colors, colors, sizeof(SDL_Color) * (size_t)ncolors);
    if (s != screen) return;
    for (int i = 0; i < ncolors; ++i) {
        uint32_t rgb = (uint32_t)colors[i].r << 16 | (uint32_t)colors[i].g << 8 | colors[i].b;
        if (!palette_known || gpu_palette_shadow[i] != rgb) {
            gpu_palette_shadow[i] = rgb;
            gpu_palette((unsigned)i, rgb);
        }
    }
    palette_known = 1;
    choose_overlay_colors();
}

/* ------------------------------------------------------------ presenter */
static void upload_tile(unsigned tx, unsigned ty)
{
    unsigned slot = ty * TILES_X + tx, rows = ty == TILES_Y - 1 ? PAL_VIEW_H - TILE * (TILES_Y - 1) : TILE;
    for (unsigned v = 0; v < rows; ++v) {
        const uint8_t *src = screen->pixels + (size_t)(ty * TILE + v) * screen->pitch + tx * TILE;
        uint8_t *mirror = &shadow[ty * TILE + v][tx * TILE];
        uint32_t base = ((uint32_t)slot << 12 | (uint32_t)v << 6) << 8;
        for (unsigned u = 0; u < TILE; ++u) {
            gpu_wr(26, base | (uint32_t)u << 8 | src[u]);
            mirror[u] = src[u];
        }
    }
    shadow_valid[ty][tx] = 1;
    ++uploaded_tiles;
}

static int tile_changed(unsigned tx, unsigned ty)
{
    unsigned rows = ty == TILES_Y - 1 ? PAL_VIEW_H - TILE * (TILES_Y - 1) : TILE;
    if (!shadow_valid[ty][tx]) return 1;
    for (unsigned v = 0; v < rows; ++v) {
        const uint32_t *a = (const uint32_t *)(screen->pixels + (size_t)(ty * TILE + v) * screen->pitch + tx * TILE);
        const uint32_t *b = (const uint32_t *)&shadow[ty * TILE + v][tx * TILE];
        for (unsigned i = 0; i < TILE / 4; ++i)
            if (a[i] != b[i]) return 1;
    }
    return 0;
}

static void outline(int x, int y, int w, int h, unsigned color)
{
    gpu_rect(x, y, w, 1, color);
    gpu_rect(x, y + h - 1, w, 1, color);
    gpu_rect(x, y, 1, h, color);
    gpu_rect(x + w - 1, y, 1, h, color);
}

static void label(int cx, int cy, const char *text, unsigned color)
{
    gpu_text(cx - gpu_text_width(text, 1) / 2, cy - 8, text, color, 1);
}

/* The GPU has no alpha blending: "semi-transparent" buttons use the DITHER
 * flag, which writes every other pixel in a checkerboard, so half of the game
 * picture stays visible through the button face. */
static void button(int x, int y, int w, int h, const char *text)
{
    gpu_wr(GPU_FLAGS, GPU_FLAG_DITHER);
    gpu_rect(x, y, w, h, overlay_dark);
    gpu_wr(GPU_FLAGS, 0);
    outline(x, y, w, h, overlay_light);
    label(x + w / 2, y + h / 2, text, overlay_light);
}

static void draw_overlay(void)
{
    static const struct { int x, y, w, h; } pad[4] = {
        {60, 212, 40, 30}, {60, 268, 40, 30}, {16, 236, 44, 36}, {100, 236, 44, 36}};
    static const char *arrows[4] = {"^", "v", "<", ">"};
    for (unsigned i = 0; i < 4; ++i) button(pad[i].x, pad[i].y, pad[i].w, pad[i].h, arrows[i]);
    for (unsigned i = 0; i < 6; ++i) {
        const pal_button_t *b = &pal_buttons[i];
        button(b->x, b->y, b->w, b->h, b->label);
    }
}

static void present(void)
{
    frame_pending = 0;
    if (!screen) return;
    for (unsigned ty = 0; ty < TILES_Y; ++ty)
        for (unsigned tx = 0; tx < TILES_X; ++tx)
            if (tile_changed(tx, ty)) upload_tile(tx, ty);
    gpu_clear(0);
    gpu_wr(GPU_FLAGS, 0);
    /* Each 64x64 tile covers 96x96 display pixels; sample at pixel centres
     * (u = (i + 0.5) * 2/3), so tile borders map exactly and leave no seams. */
    gpu_wr(GPU_U0, SCALE_STEP / 2);
    gpu_wr(GPU_V0, SCALE_STEP / 2);
    gpu_wr(GPU_DUDX, SCALE_STEP);
    gpu_wr(GPU_DVDX, 0);
    gpu_wr(GPU_DUDY, 0);
    gpu_wr(GPU_DVDY, SCALE_STEP);
    for (unsigned ty = 0; ty < TILES_Y; ++ty) {
        unsigned rows = ty == TILES_Y - 1 ? PAL_VIEW_H - TILE * (TILES_Y - 1) : TILE;
        gpu_wr(GPU_SIZE, (uint32_t)(rows * PAL_SCALE_NUM / PAL_SCALE_DEN) << 16 | DISPLAY_TILE);
        for (unsigned tx = 0; tx < TILES_X; ++tx) {
            gpu_wr(GPU_DST, (uint32_t)(PAL_VIEW_Y + ty * DISPLAY_TILE) << 16 | (uint32_t)(PAL_VIEW_X + tx * DISPLAY_TILE));
            gpu_wr(GPU_CMD_SPRITE, ty * TILES_X + tx);
        }
    }
    draw_overlay();
    gpu_swap();
    ++presented_frames;
}

void SDL_UpdateRect(SDL_Surface *s, int x, int y, int w, int h)
{
    (void)x; (void)y; (void)w; (void)h;
    if (s != screen) return;
    frame_pending = 1;
    pal_video_service();
}

void pal_video_service(void)
{
    if (frame_pending && gpu_idle()) present();
}

void pal_video_init(void)
{
    while (!gpu_idle()) { }
    gpu_clear(0);
    gpu_swap();
}

uint32_t pal_video_frames(void) { return presented_frames; }
uint32_t pal_video_tiles(void) { return uploaded_tiles; }

/* ------------------------------------------------------------ messages */
void pal_port_message(const char *line1, const char *line2)
{
    for (int i = 0; i < 2; ++i) {
        while (!gpu_idle()) { }
        gpu_palette(1, 0xffffff);
        gpu_clear(0);
        gpu_text(20, 110, line1, 1, 1);
        if (line2) gpu_text(20, 140, line2, 1, 1);
        gpu_swap();
    }
}

void pal_port_fatal_screen(const char *what, uint32_t pc)
{
    static const char hex[] = "0123456789ABCDEF";
    char line[24] = "PC ";
    for (int i = 0; i < 8; ++i) line[3 + i] = hex[(pc >> (28 - 4 * i)) & 15u];
    line[11] = 0;
    pal_port_message(what, line);
}

/* ------------------------------------------------------------ remaining API */
SDL_Surface *SDL_ConvertSurface(SDL_Surface *src, SDL_PixelFormat *fmt, uint32_t flags)
{
    (void)src; (void)fmt; (void)flags;
    assert(!"SDL_ConvertSurface is not used by PAL classic");
    return NULL;
}

uint32_t SDL_MapRGBA(SDL_PixelFormat *fmt, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    uint32_t p = (uint32_t)r << fmt->Rshift | (uint32_t)g << fmt->Gshift | (uint32_t)b << fmt->Bshift;
    if (fmt->Amask) p |= (uint32_t)a << fmt->Ashift;
    return p;
}

int SDL_LockSurface(SDL_Surface *s) { (void)s; return 0; }
void SDL_UnlockSurface(SDL_Surface *s) { (void)s; }
