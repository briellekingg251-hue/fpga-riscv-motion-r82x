/* GT911 snapshot registers in the GPU MMIO window.  Read STATE first: the
 * hardware freezes XY, sequence and errors together until the next STATE read.
 * The default panel reports landscape coordinates: 1024 x 600 pixels.
 */
#ifndef FN_TOUCH_H
#define FN_TOUCH_H

#include <stdint.h>
#include "soc.h"

#define TOUCH_STATE_OFFSET  0x100u
#define TOUCH_XY_OFFSET     0x104u
#define TOUCH_SEQ_OFFSET    0x108u
#define TOUCH_ERRORS_OFFSET 0x10Cu
#define TOUCH_DOWN          1u
#define TOUCH_READY         2u
#define TOUCH_FAULT         4u

/* Override these at build time for differently mounted panels.  With SWAP_XY,
 * the controller is expected to report portrait coordinates (600 x 1024).
 * Mirroring applies after swapping, in landscape LCD coordinates.
 */
#ifndef FN_TOUCH_SWAP_XY
#define FN_TOUCH_SWAP_XY 0
#endif
#ifndef FN_TOUCH_MIRROR_X
#define FN_TOUCH_MIRROR_X 0
#endif
#ifndef FN_TOUCH_MIRROR_Y
#define FN_TOUCH_MIRROR_Y 0
#endif
#ifndef FN_TOUCH_RELEASE_FRAMES
/* Used only by explicitly compiled FN_DEMO_MODE=1 builds. Manual play never
 * enables an AI blade when a finger is released.
 */
#define FN_TOUCH_RELEASE_FRAMES 60
#endif
#ifndef FN_TOUCH_STALE_FRAMES
#define FN_TOUCH_STALE_FRAMES 30
#endif
#ifndef FN_TOUCH_LOG
#define FN_TOUCH_LOG 1
#endif
#ifndef FN_TOUCH_READ_REG
#define FN_TOUCH_READ_REG(offset) MMIO32(GPU_BASE + (offset))
#endif

typedef struct {
    uint32_t status, xy, sequence, errors;
} touch_sample_t;

static inline touch_sample_t touch_read(void)
{
    touch_sample_t s;
    s.status = FN_TOUCH_READ_REG(TOUCH_STATE_OFFSET);
    s.xy = FN_TOUCH_READ_REG(TOUCH_XY_OFFSET);
    s.sequence = FN_TOUCH_READ_REG(TOUCH_SEQ_OFFSET);
    s.errors = FN_TOUCH_READ_REG(TOUCH_ERRORS_OFFSET);
    return s;
}

/* Reject malformed coordinates rather than turning them into a screen-edge
 * swipe.  Convert to the 512 x 300 framebuffer only after orientation mapping.
 */
static inline int touch_map(uint32_t xy, int *x, int *y)
{
    unsigned rx = xy & 0xFFFFu, ry = xy >> 16;
#if FN_TOUCH_SWAP_XY
    unsigned tmp = rx; rx = ry; ry = tmp;
#endif
    if (rx >= 1024u || ry >= 600u) return 0;
#if FN_TOUCH_MIRROR_X
    rx = 1023u - rx;
#endif
#if FN_TOUCH_MIRROR_Y
    ry = 599u - ry;
#endif
    *x = (int)(rx >> 1);
    *y = (int)(ry >> 1);
    return 1;
}

#endif
