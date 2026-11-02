/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Touch layout -> NES joypad.  Pure: canvas coordinates in, pad bits out.
 *
 * Left panel: MENU, an 8-way D-pad and SELECT.  Right panel: B and A side by
 * side (a strip between them presses both) and START.  Every contact is
 * evaluated on its own and the results are ORed, so multi-touch combinations
 * such as RIGHT + A + B work. */
#include "nes_port.h"

const nes_button_t nes_buttons[] = {
    {8, 6, 80, 26, NES_PAD_MENU, "MENU"},
    {16, 256, 96, 32, NES_PAD_SELECT, "SELECT"},
    {400, 256, 96, 32, NES_PAD_START, "START"},
};
const unsigned nes_button_count = sizeof nes_buttons / sizeof nes_buttons[0];

static int iabs(int v) { return v < 0 ? -v : v; }

/* 8-way direction relative to the D-pad centre.  A component counts when it
 * exceeds 2/5 of the other (tan 22.5 deg ~ 0.414), giving 45-degree sectors. */
static uint32_t dpad(int x, int y)
{
    int dx = x - NES_DPAD_CX, dy = y - NES_DPAD_CY;
    int ax = iabs(dx), ay = iabs(dy);
    uint32_t bits = 0;
    if (x < 0 || x >= NES_SCREEN_X || y < NES_DPAD_TOP || y >= NES_DPAD_BOTTOM) return 0;
    if (ax < NES_DPAD_DEAD && ay < NES_DPAD_DEAD) return 0;
    if (5 * ax > 2 * ay) bits |= dx < 0 ? NES_PAD_LEFT : NES_PAD_RIGHT;
    if (5 * ay > 2 * ax) bits |= dy < 0 ? NES_PAD_UP : NES_PAD_DOWN;
    return bits;
}

static uint32_t action(int x, int y)
{
    if (x < NES_AB_LEFT || x >= NES_CANVAS_W || y < NES_AB_TOP || y >= NES_AB_BOTTOM) return 0;
    if (iabs(x - NES_AB_SPLIT) < NES_AB_BOTH) return NES_PAD_A | NES_PAD_B;
    return x < NES_AB_SPLIT ? NES_PAD_B : NES_PAD_A;
}

static uint32_t button(int x, int y)
{
    for (unsigned i = 0; i < nes_button_count; ++i) {
        const nes_button_t *b = nes_buttons + i;
        if (x >= b->x && x < b->x + b->w && y >= b->y && y < b->y + b->h) return b->bit;
    }
    return 0;
}

uint32_t nes_pad_from_points(const nes_point_t *points, unsigned count)
{
    uint32_t bits = 0;
    if (count > NES_TOUCH_MAX) count = NES_TOUCH_MAX;
    for (unsigned i = 0; i < count; ++i) {
        int x = points[i].x, y = points[i].y;
        bits |= button(x, y) | dpad(x, y) | action(x, y);
    }
    /* Two fingers on opposite arms: a real pad cannot press both, and many
     * games misbehave on LEFT+RIGHT or UP+DOWN.  Drop the pair. */
    if ((bits & (NES_PAD_LEFT | NES_PAD_RIGHT)) == (NES_PAD_LEFT | NES_PAD_RIGHT))
        bits &= ~(NES_PAD_LEFT | NES_PAD_RIGHT);
    if ((bits & (NES_PAD_UP | NES_PAD_DOWN)) == (NES_PAD_UP | NES_PAD_DOWN))
        bits &= ~(NES_PAD_UP | NES_PAD_DOWN);
    return bits;
}
