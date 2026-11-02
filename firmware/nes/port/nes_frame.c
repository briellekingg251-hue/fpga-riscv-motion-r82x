/* SPDX-License-Identifier: GPL-2.0-or-later */
/* WorkFrame -> GPU sprite memory, changed texels only.  Pure.
 *
 * GPU sprite memory is written one texel per MMIO store, so only texels that
 * differ from the last upload are sent.  Lines are processed right after
 * InfoNES renders them, while the 512-byte line is still in the data cache.
 * Pixels are compared two at a time (one 32-bit word of WorkFrame, little
 * endian: low half = left pixel), four words per branch.  Only the colour
 * bits count: InfoNES's 0x8000 background flag does not change the image. */
#include "nes_port.h"

#define PAIRS_PER_ROW (NES_VIEW_W / 2)
#define COLOUR_MASK   0x003f003fu
/* Unreachable masked value: forces a full upload. */
#define INVALID_PAIR  0xffffffffu

typedef uint32_t __attribute__((may_alias)) pair_t;

static uint32_t uploaded[NES_VIEW_LINES][PAIRS_PER_ROW];

void nes_frame_invalidate(void)
{
    for (unsigned y = 0; y < NES_VIEW_LINES; ++y)
        for (unsigned i = 0; i < PAIRS_PER_ROW; ++i) uploaded[y][i] = INVALID_PAIR;
}

static unsigned texel(uint32_t pixel) { return (pixel & 0x3fu) + NES_PAL_BASE; }

static uint32_t send_pair(uint32_t pair, uint32_t old, unsigned x, unsigned y, nes_texel_sink_t sink)
{
    uint32_t diff = pair ^ old, sent = 0;
    if (diff & 0xffffu) { sink(nes_texel_word(x, y, texel(pair))); ++sent; }
    if (diff >> 16) { sink(nes_texel_word(x + 1u, y, texel(pair >> 16))); ++sent; }
    return sent;
}

uint32_t nes_frame_upload_line(const uint16_t *line, unsigned y, nes_texel_sink_t sink)
{
    const pair_t *now = (const pair_t *)line;
    uint32_t *old = uploaded[y], sent = 0;
    for (unsigned i = 0; i < PAIRS_PER_ROW; i += 4) {
        uint32_t p0 = now[i] & COLOUR_MASK, p1 = now[i + 1] & COLOUR_MASK;
        uint32_t p2 = now[i + 2] & COLOUR_MASK, p3 = now[i + 3] & COLOUR_MASK;
        if (!((p0 ^ old[i]) | (p1 ^ old[i + 1]) | (p2 ^ old[i + 2]) | (p3 ^ old[i + 3]))) continue;
        sent += send_pair(p0, old[i], 2 * i, y, sink);
        sent += send_pair(p1, old[i + 1], 2 * i + 2, y, sink);
        sent += send_pair(p2, old[i + 2], 2 * i + 4, y, sink);
        sent += send_pair(p3, old[i + 3], 2 * i + 6, y, sink);
        old[i] = p0; old[i + 1] = p1; old[i + 2] = p2; old[i + 3] = p3;
    }
    return sent;
}

uint32_t nes_frame_upload(const uint16_t *work, nes_texel_sink_t sink)
{
    uint32_t sent = 0;
    for (unsigned y = 0; y < NES_VIEW_LINES; ++y)
        sent += nes_frame_upload_line(work + (NES_VIEW_TOP + y) * NES_VIEW_W, y, sink);
    return sent;
}
