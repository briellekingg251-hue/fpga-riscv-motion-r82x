/* Driver for the Fruit Ninja display engine (rtl/video).
 *
 * The CPU writes commands into a 1024-entry FIFO at GPU_BASE; the engine draws
 * them in order into the hidden framebuffer (512x300, 8-bit palette indices,
 * shown 2x scaled on the 1024x600 LCD) and gpu_swap() presents it at the next
 * frame boundary.  All GPU stores must be 32-bit.
 */
#ifndef FN_GPU_H
#define FN_GPU_H

#include <stdint.h>
#include "soc.h"

#define FB_W 512
#define FB_H 300

/* write registers (word index) */
enum {
    GPU_NOP = 0, GPU_COLOR = 1, GPU_DST = 2, GPU_SIZE = 3,
    GPU_U0 = 4, GPU_V0 = 5, GPU_DUDX = 6, GPU_DVDX = 7, GPU_DUDY = 8, GPU_DVDY = 9,
    GPU_FLAGS = 10,
    GPU_CMD_CLEAR = 16, GPU_CMD_BG = 17, GPU_CMD_RECT = 18, GPU_CMD_SPRITE = 19,
    GPU_CMD_GLYPH = 20, GPU_CMD_TEXT = 21, GPU_CMD_CIRCLE = 22, GPU_CMD_PSET = 23,
    GPU_CMD_PALETTE = 24, GPU_CMD_SWAP = 25
};
#define GPU_FLAG_SOLID  1u   /* sprite: opaque texels drawn in COLOR */
#define GPU_FLAG_WRAP   2u   /* sprite: u, v wrap modulo 64 (tiling) */
#define GPU_FLAG_REMAP  4u   /* sprite: opaque texels drawn as texel + COLOR */
#define GPU_FLAG_DITHER 8u   /* sprite and RECT: only pixels with even x + y */

/* read registers (byte offset) */
#define GPU_REG_ID      MMIO32(GPU_BASE + 0x00u)
#define GPU_REG_STATUS  MMIO32(GPU_BASE + 0x04u)
#define GPU_REG_FRAME   MMIO32(GPU_BASE + 0x08u)
#define GPU_REG_SWAPS   MMIO32(GPU_BASE + 0x0Cu)
#define GPU_ID_VALUE    0x464E4731u

#ifdef FN_GPU_TRACE
/* Host-only capture hook; production builds keep the direct MMIO store. */
void fn_gpu_trace(unsigned idx, uint32_t value);
#endif
static inline void gpu_wr(unsigned idx, uint32_t v)
{
#ifdef FN_GPU_TRACE
    fn_gpu_trace(idx, v);
#else
    MMIO32(GPU_BASE + (idx << 2)) = v;
#endif
}

static inline uint32_t gpu_swaps(void) { return GPU_REG_SWAPS & 0xFFFFu; }
static inline uint32_t gpu_frame(void) { return GPU_REG_FRAME & 0xFFFFu; }

static inline void gpu_bg(unsigned variant) { gpu_wr(GPU_CMD_BG, variant); }
static inline void gpu_clear(unsigned color) { gpu_wr(GPU_CMD_CLEAR, color); }
static inline void gpu_swap(void) { gpu_wr(GPU_CMD_SWAP, 0); }

static inline void gpu_circle(int cx, int cy, int r, unsigned color)
{
    if (cx < 0 || cy < 0 || cx > 511 || cy > 511 || r < 0) return;
    gpu_wr(GPU_CMD_CIRCLE, (uint32_t)cx | ((uint32_t)cy << 9) |
           ((uint32_t)(r & 63) << 18) | ((uint32_t)color << 24));
}

static inline void gpu_pset(int x, int y, unsigned color)
{
    if (x < 0 || y < 0 || x > 511 || y > 511) return;
    gpu_wr(GPU_CMD_PSET, (uint32_t)x | ((uint32_t)y << 9) | ((uint32_t)color << 24));
}

static inline void gpu_palette(unsigned index, uint32_t rgb)
{
    gpu_wr(GPU_CMD_PALETTE, (index << 24) | (rgb & 0xFFFFFFu));
}

void gpu_rect(int x, int y, int w, int h, unsigned color);
/* sprite centred on (cx, cy); scale_q8 256 = 1.0; angle 0..255 = full turn */
void gpu_sprite(unsigned img, int cx, int cy, int scale_q8, int angle, int flip);
void gpu_sprite_solid(unsigned img, int cx, int cy, int scale_q8, int angle, unsigned color);
/* Map a whole 64x64 image onto the box (x, y, w, h), optionally mirrored.
 * Rows above the framebuffer are clipped here; the GPU clips the rest.
 */
void gpu_blit(unsigned img, int x, int y, int w, int h, int mirror, uint32_t flags, unsigned color);
/* returns the x advance; scale 1..4 */
int  gpu_text(int x, int y, const char *s, unsigned color, int scale);
int  gpu_text_width(const char *s, int scale);
void gpu_text_shadow(int x, int y, const char *s, unsigned color, unsigned shadow, int scale);

int  isin(int a);   /* Q14 */
int  icos(int a);

#endif
