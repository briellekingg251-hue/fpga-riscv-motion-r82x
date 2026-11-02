/* SPDX-License-Identifier: GPL-2.0-or-later */
/* ROM list state machine.  Pure; drawing lives in nes_video.c.
 *
 * Like the resident loader, a press acts only after a lift has been seen with
 * a fresh sample, so the touch that started a screen can never select on it. */
#include "nes_port.h"

static int name_less(const char *a, const char *b)
{
    while (*a && *a == *b) { ++a; ++b; }
    return (unsigned char)*a < (unsigned char)*b;
}

int nes_menu_add(nes_menu_t *m, const nes_entry_t *e)
{
    if (m->count >= NES_ROM_SLOTS) return -1;
    unsigned i = m->count++;
    for (; i > 0 && name_less(e->name, m->entry[i - 1].name); --i) m->entry[i] = m->entry[i - 1];
    m->entry[i] = *e;
    return 0;
}

unsigned nes_menu_pages(const nes_menu_t *m)
{
    return m->count ? (m->count + NES_MENU_ROWS - 1u) / NES_MENU_ROWS : 1u;
}

int nes_menu_touch(nes_menu_t *m, uint32_t sequence, int healthy, int down,
                   int x, int y, unsigned *selected)
{
    if (!healthy) return NES_MENU_NONE;
    if (m->have_sequence && sequence == m->sequence) return NES_MENU_NONE;
    m->have_sequence = 1;
    m->sequence = sequence;
    if (!down) { m->armed = 1; return NES_MENU_NONE; }
    if (!m->armed) return NES_MENU_NONE;
    m->armed = 0;
    if (y >= NES_MENU_BTN_Y && y < NES_MENU_BTN_Y + NES_MENU_BTN_H) {
        unsigned pages = nes_menu_pages(m);
        if (x >= NES_MENU_PREV_X && x < NES_MENU_PREV_X + NES_MENU_PREV_W) {
            m->page = (m->page + pages - 1u) % pages;
            return NES_MENU_REDRAW;
        }
        if (x >= NES_MENU_EXIT_X && x < NES_MENU_EXIT_X + NES_MENU_EXIT_W) return NES_MENU_EXIT;
        if (x >= NES_MENU_NEXT_X && x < NES_MENU_NEXT_X + NES_MENU_NEXT_W) {
            m->page = (m->page + 1u) % pages;
            return NES_MENU_REDRAW;
        }
        return NES_MENU_NONE;
    }
    if (x < NES_MENU_LIST_X || x >= NES_MENU_LIST_X + NES_MENU_LIST_W ||
        y < NES_MENU_LIST_Y || y >= NES_MENU_LIST_Y + (int)(NES_MENU_ROWS * NES_MENU_ROW_H))
        return NES_MENU_NONE;
    unsigned index = m->page * NES_MENU_ROWS + (unsigned)(y - NES_MENU_LIST_Y) / NES_MENU_ROW_H;
    if (index >= m->count || !m->entry[index].usable) return NES_MENU_NONE;
    *selected = index;
    return NES_MENU_PLAY;
}
