#include "gpu.h"
#include "assets.h"
#include "trig_table.h"

int isin(int a) { return fn_sin_q14[a & 255]; }
int icos(int a) { return fn_sin_q14[(a + 64) & 255]; }

static inline int iabs(int v) { return v < 0 ? -v : v; }

void gpu_rect(int x, int y, int w, int h, unsigned color)
{
    if (w <= 0 || h <= 0) return;
    gpu_wr(GPU_COLOR, color);
    gpu_wr(GPU_DST, ((uint32_t)(y & 0xFFFF) << 16) | (uint32_t)(x & 0xFFFF));
    gpu_wr(GPU_SIZE, ((uint32_t)h << 16) | (uint32_t)w);
    gpu_wr(GPU_CMD_RECT, 0);
}

/* Inverse-mapped affine blit; identical integer math to tools/gpu_model.py. */
static void sprite_common(unsigned img, int cx, int cy, int scale_q8, int angle,
                          int flip, uint32_t flags)
{
    if (scale_q8 < 16) return;
    int c = icos(angle), s = isin(angle);
    int inv = (1 << 24) / scale_q8;
    int dudx = (int)(((int64_t)c * inv) >> 14);
    int dvdx = (int)(((int64_t)-s * inv) >> 14);
    int dudy = (int)(((int64_t)s * inv) >> 14);
    int dvdy = (int)(((int64_t)c * inv) >> 14);
    int hb = (((iabs(c) + iabs(s)) * scale_q8) >> 17) + 1;
    int x0 = cx - hb, y0 = cy - hb, w = 2 * hb;
    if (x0 >= FB_W || y0 >= FB_H || x0 + w <= 0 || y0 + w <= 0) return;
    int u0 = (32 << 16) + (((dudx + dudy) * (1 - 2 * hb)) >> 1);
    int v0 = (32 << 16) + (((dvdx + dvdy) * (1 - 2 * hb)) >> 1);
    if (flip) {
        dudx = -dudx;
        dudy = -dudy;
        u0 = (64 << 16) - u0;
    }
    gpu_wr(GPU_DST, ((uint32_t)(y0 & 0xFFFF) << 16) | (uint32_t)(x0 & 0xFFFF));
    gpu_wr(GPU_SIZE, ((uint32_t)w << 16) | (uint32_t)w);
    gpu_wr(GPU_U0, (uint32_t)u0);
    gpu_wr(GPU_V0, (uint32_t)v0);
    gpu_wr(GPU_DUDX, (uint32_t)dudx);
    gpu_wr(GPU_DVDX, (uint32_t)dvdx);
    gpu_wr(GPU_DUDY, (uint32_t)dudy);
    gpu_wr(GPU_DVDY, (uint32_t)dvdy);
    gpu_wr(GPU_FLAGS, flags);
    gpu_wr(GPU_CMD_SPRITE, img);
}

void gpu_sprite(unsigned img, int cx, int cy, int scale_q8, int angle, int flip)
{
    sprite_common(img, cx, cy, scale_q8, angle, flip, 0);
}

void gpu_sprite_solid(unsigned img, int cx, int cy, int scale_q8, int angle, unsigned color)
{
    gpu_wr(GPU_COLOR, color);
    sprite_common(img, cx, cy, scale_q8, angle, 0, GPU_FLAG_SOLID);
}

int gpu_text_width(const char *s, int scale)
{
    int w = 0;
    for (; *s; ++s) w += (fn_glyph_width[(unsigned char)*s & 127] + 1) * scale;
    return w;
}

int gpu_text(int x, int y, const char *s, unsigned color, int scale)
{
    int x_start = x;
    if (scale < 1) scale = 1;
    if (scale > 4) scale = 4;
    gpu_wr(GPU_COLOR, color);
    for (; *s; ++s) {
        unsigned ch = (unsigned char)*s & 127u;
        if (ch != ' ' && x >= 0 && x < FB_W && y >= 0 && y < FB_H)
            gpu_wr(GPU_CMD_TEXT, (uint32_t)x | ((uint32_t)y << 9) | (ch << 18) |
                   ((uint32_t)(scale - 1) << 25));
        x += (fn_glyph_width[ch] + 1) * scale;
    }
    return x - x_start;
}

void gpu_text_shadow(int x, int y, const char *s, unsigned color, unsigned shadow, int scale)
{
    gpu_text(x + scale, y + scale, s, shadow, scale);
    gpu_text(x, y, s, color, scale);
}

void gpu_blit(unsigned img, int x, int y, int w, int h, int mirror, uint32_t flags, unsigned color)
{
    if (w <= 0 || h <= 0 || x >= FB_W || y >= FB_H || x + w <= 0 || y + h <= 0) return;
    int dudx = (64 << 16) / w, dvdy = (64 << 16) / h;
    int u0 = dudx >> 1, v0 = dvdy >> 1;
    if (mirror) {
        u0 = (64 << 16) - u0;
        dudx = -dudx;
    }
    if (y < 0) {                       /* also keeps h within the 10-bit SIZE field */
        v0 += dvdy * -y;
        h += y;
        y = 0;
    }
    if (h > FB_H - y) h = FB_H - y;
    if (x < 0 && w > 1023) {
        u0 += dudx * -x;
        w += x;
        x = 0;
    }
    if (w > FB_W - x) w = FB_W - x;
    gpu_wr(GPU_COLOR, color);
    gpu_wr(GPU_DST, ((uint32_t)(y & 0xFFFF) << 16) | (uint32_t)(x & 0xFFFF));
    gpu_wr(GPU_SIZE, ((uint32_t)h << 16) | (uint32_t)w);
    gpu_wr(GPU_U0, (uint32_t)u0);
    gpu_wr(GPU_V0, (uint32_t)v0);
    gpu_wr(GPU_DUDX, (uint32_t)dudx);
    gpu_wr(GPU_DVDX, 0);
    gpu_wr(GPU_DUDY, 0);
    gpu_wr(GPU_DVDY, (uint32_t)dvdy);
    gpu_wr(GPU_FLAGS, flags);
    gpu_wr(GPU_CMD_SPRITE, img);
}
