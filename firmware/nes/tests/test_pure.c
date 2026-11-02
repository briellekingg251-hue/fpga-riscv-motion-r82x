/* Host unit tests for the platform-independent NES port modules.
 * Build: see tools/run_host_tests.py.  Exits non-zero on the first failure. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nes_port.h"

static unsigned checks;
#define CHECK(cond) do { ++checks; if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); exit(1); } } while (0)

/* Mapper table stub: InfoNES is not linked into the pure tests. */
int nes_mapper_supported(unsigned mapper) { return mapper == 0 || mapper == 2 || mapper == 73; }

static uint8_t image[16 + 512 + 2 * 0x4000 + 0x2000];

static void header(uint8_t prg, uint8_t chr, uint8_t f6, uint8_t f7)
{
    memset(image, 0, sizeof image);
    memcpy(image, "NES\x1a", 4);
    image[4] = prg; image[5] = chr; image[6] = f6; image[7] = f7;
}

static void test_rom(void)
{
    nes_rom_t r;
    header(2, 1, 0x01, 0x00);
    CHECK(nes_rom_parse(image, 16 + 0x8000 + 0x2000, &r) == NES_ROM_OK);
    CHECK(r.mapper == 0 && r.prg == image + 16 && r.chr == image + 16 + 0x8000);
    CHECK(r.prg_bytes == 0x8000 && r.chr_bytes == 0x2000 && !r.trainer);
    CHECK(r.header[6] == 0x01 && r.header[7] == 0);
    /* one byte short of the CHR bank */
    CHECK(nes_rom_parse(image, 16 + 0x8000 + 0x2000 - 1, &r) == NES_ROM_TRUNCATED);
    /* trainer shifts PRG by 512 bytes */
    header(2, 1, 0x04, 0x00);
    CHECK(nes_rom_parse(image, sizeof image, &r) == NES_ROM_OK);
    CHECK(r.trainer == image + 16 && r.prg == image + 16 + 512);
    /* mapper 73 = 0x9 low nibble + 0x40 high nibble */
    header(2, 0, 0x91, 0x40);
    CHECK(nes_rom_parse(image, 16 + 0x8000, &r) == NES_ROM_OK && r.mapper == 73 && !r.chr);
    CHECK(r.header[7] == 0x40);
    /* "DiskDude!" style garbage: high nibble of byte 7 ignored -> mapper 2 */
    header(2, 0, 0x20, 'D');
    memcpy(image + 8, "iskDude!", 8);
    CHECK(nes_rom_parse(image, 16 + 0x8000, &r) == NES_ROM_OK && r.mapper == 2);
    CHECK(r.header[7] == 0 && r.header[12] == 0);
    /* unsupported mapper (4 is not in the stub) */
    header(2, 0, 0x40, 0x00);
    CHECK(nes_rom_parse(image, 16 + 0x8000, &r) == NES_ROM_MAPPER_UNSUPPORTED);
    /* NES 2.0: plain values accepted, extended sizes rejected */
    header(2, 1, 0x00, 0x08);
    CHECK(nes_rom_parse(image, 16 + 0x8000 + 0x2000, &r) == NES_ROM_OK);
    image[9] = 0x01;
    CHECK(nes_rom_parse(image, sizeof image, &r) == NES_ROM_NES2_UNSUPPORTED);
    header(0, 1, 0, 0);
    CHECK(nes_rom_parse(image, sizeof image, &r) == NES_ROM_NO_PRG);
    image[0] = 'X';
    CHECK(nes_rom_parse(image, sizeof image, &r) == NES_ROM_BAD_MAGIC);
    CHECK(nes_rom_parse(image, 15, &r) == NES_ROM_TRUNCATED);
    CHECK(nes_rom_parse(image, NES_ROM_MAX + 1, &r) == NES_ROM_TOO_BIG);
    CHECK(strcmp(nes_rom_error(NES_ROM_TRUNCATED), "FILE TRUNCATED") == 0);
}

static uint32_t pad1(int x, int y)
{
    nes_point_t p = {(int16_t)x, (int16_t)y};
    return nes_pad_from_points(&p, 1);
}

static void test_pad(void)
{
    const int cx = NES_DPAD_CX, cy = NES_DPAD_CY;
    CHECK(pad1(cx, cy) == 0);                                   /* dead zone */
    CHECK(pad1(cx + 30, cy) == NES_PAD_RIGHT);
    CHECK(pad1(cx - 30, cy + 5) == NES_PAD_LEFT);
    CHECK(pad1(cx, cy - 30) == NES_PAD_UP);
    CHECK(pad1(cx + 3, cy + 40) == NES_PAD_DOWN);
    CHECK(pad1(cx + 25, cy - 25) == (NES_PAD_RIGHT | NES_PAD_UP));
    CHECK(pad1(cx - 25, cy + 25) == (NES_PAD_LEFT | NES_PAD_DOWN));
    /* sector boundaries: 2/5 ratio */
    CHECK(pad1(cx + 30, cy - 11) == NES_PAD_RIGHT);
    CHECK(pad1(cx + 30, cy - 13) == (NES_PAD_RIGHT | NES_PAD_UP));
    CHECK(pad1(cx, NES_DPAD_TOP - 1) == 0);                    /* above the zone */
    CHECK(pad1(NES_SCREEN_X, cy) == 0);                         /* picture area */
    CHECK(pad1(NES_B_CX, NES_B_CY) == NES_PAD_B);
    CHECK(pad1(NES_A_CX, NES_A_CY) == NES_PAD_A);
    CHECK(pad1(NES_AB_SPLIT, 150) == (NES_PAD_A | NES_PAD_B));
    CHECK(pad1(NES_AB_SPLIT - NES_AB_BOTH, 150) == NES_PAD_B);
    CHECK(pad1(NES_AB_SPLIT + NES_AB_BOTH, 150) == NES_PAD_A);
    CHECK(pad1(NES_AB_LEFT - 1, 150) == 0);
    CHECK(pad1(20, 10) == NES_PAD_MENU);
    CHECK(pad1(40, 270) == NES_PAD_SELECT);
    CHECK(pad1(440, 270) == NES_PAD_START);
    CHECK(pad1(256, 150) == 0);
    nes_point_t multi[6] = {{(int16_t)(cx + 30), (int16_t)cy}, {NES_A_CX, NES_A_CY},
                            {NES_B_CX, NES_B_CY}, {440, 270}, {20, 10}, {40, 270}};
    CHECK(nes_pad_from_points(multi, 3) == (NES_PAD_RIGHT | NES_PAD_A | NES_PAD_B));
    /* contacts beyond NES_TOUCH_MAX are ignored */
    CHECK(nes_pad_from_points(multi, 6) == (NES_PAD_RIGHT | NES_PAD_A | NES_PAD_B |
                                           NES_PAD_START | NES_PAD_MENU));
    /* opposite arms from two fingers cancel; the other axis survives */
    nes_point_t both[3] = {{(int16_t)(cx - 30), (int16_t)cy}, {(int16_t)(cx + 30), (int16_t)cy},
                           {(int16_t)cx, (int16_t)(cy - 30)}};
    CHECK(nes_pad_from_points(both, 2) == 0);
    CHECK(nes_pad_from_points(both, 3) == NES_PAD_UP);
    /* buttons never overlap the D-pad or A/B zones */
    for (unsigned i = 0; i < nes_button_count; ++i) {
        const nes_button_t *b = nes_buttons + i;
        for (int y = b->y; y < b->y + b->h; ++y)
            for (int x = b->x; x < b->x + b->w; ++x) CHECK(pad1(x, y) == b->bit);
    }
}

static void entry(nes_entry_t *e, const char *name, int usable)
{
    memset(e, 0, sizeof *e);
    strcpy(e->name, name);
    e->usable = (uint8_t)usable;
}

static void test_menu(void)
{
    static nes_menu_t m;
    nes_entry_t e;
    unsigned sel = 99;
    const char *names[] = {"TANK.NES", "CONTRA.NES", "MARIO.NES", "HDL.NES", "SLMS.NES",
                           "MXT.NES", "ICANREM.NES", "BAD.NES"};
    for (unsigned i = 0; i < 8; ++i) { entry(&e, names[i], i != 7); CHECK(nes_menu_add(&m, &e) == 0); }
    for (unsigned i = 1; i < m.count; ++i) CHECK(strcmp(m.entry[i - 1].name, m.entry[i].name) < 0);
    CHECK(strcmp(m.entry[0].name, "BAD.NES") == 0 && nes_menu_pages(&m) == 2);
    int row = NES_MENU_LIST_Y + NES_MENU_ROW_H / 2, x = NES_MENU_LIST_X + 10;
    /* a press without a preceding lift does nothing */
    CHECK(nes_menu_touch(&m, 1, 1, 1, x, row + NES_MENU_ROW_H, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 2, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    /* same sequence again is ignored */
    CHECK(nes_menu_touch(&m, 2, 1, 1, x, row, &sel) == NES_MENU_NONE);
    /* unusable entry 0 cannot be selected; arming is consumed */
    CHECK(nes_menu_touch(&m, 3, 1, 1, x, row, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 4, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 5, 1, 1, x, row + NES_MENU_ROW_H, &sel) == NES_MENU_PLAY && sel == 1);
    /* unhealthy samples never act */
    CHECK(nes_menu_touch(&m, 6, 0, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 7, 0, 1, x, row, &sel) == NES_MENU_NONE);
    /* next page wraps, previous page wraps backwards */
    CHECK(nes_menu_touch(&m, 8, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 9, 1, 1, 400, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_REDRAW && m.page == 1);
    CHECK(nes_menu_touch(&m, 10, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 11, 1, 1, 400, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_REDRAW && m.page == 0);
    CHECK(nes_menu_touch(&m, 12, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 13, 1, 1, 20, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_REDRAW && m.page == 1);
    /* page 1 row 1 = entry 7; row 2 is empty */
    CHECK(nes_menu_touch(&m, 14, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 15, 1, 1, x, row + 2 * NES_MENU_ROW_H, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 16, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 17, 1, 1, x, row + NES_MENU_ROW_H, &sel) == NES_MENU_PLAY && sel == 7);
    CHECK(nes_menu_touch(&m, 18, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    /* the gaps between and beside the drawn buttons do nothing */
    CHECK(nes_menu_touch(&m, 19, 1, 1, NES_MENU_EXIT_X + NES_MENU_EXIT_W, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 20, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 21, 1, 1, NES_MENU_PREV_X - 1, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 22, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 23, 1, 1, NES_MENU_NEXT_X + NES_MENU_NEXT_W, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 24, 1, 0, 0, 0, &sel) == NES_MENU_NONE);
    CHECK(nes_menu_touch(&m, 25, 1, 1, NES_MENU_EXIT_X, NES_MENU_BTN_Y + 5, &sel) == NES_MENU_EXIT);
    /* catalog capacity */
    static nes_menu_t full;
    for (unsigned i = 0; i < NES_ROM_SLOTS; ++i) {
        char n[13]; snprintf(n, sizeof n, "G%02u.NES", i); entry(&e, n, 1);
        CHECK(nes_menu_add(&full, &e) == 0);
    }
    CHECK(nes_menu_add(&full, &e) == -1 && full.count == NES_ROM_SLOTS);
}

/* Sprite-memory model fed by the texel sink. */
static uint8_t sprite[NES_TILE_COLS * NES_TILE_ROWS][64][64];
static uint32_t sink_count;
static void sink(uint32_t word)
{
    uint32_t addr = word >> 8, slot = addr >> 12;
    CHECK(slot < NES_TILE_COLS * NES_TILE_ROWS);
    sprite[slot][(addr >> 6) & 63][addr & 63] = (uint8_t)word;
    ++sink_count;
}

static void check_picture(const uint16_t *work)
{
    for (unsigned y = 0; y < NES_VIEW_LINES; ++y)
        for (unsigned x = 0; x < NES_VIEW_W; ++x) {
            unsigned want = (work[(NES_VIEW_TOP + y) * NES_VIEW_W + x] & 0x3f) + NES_PAL_BASE;
            CHECK(sprite[(y >> 6) * NES_TILE_COLS + (x >> 6)][y & 63][x & 63] == want);
        }
}

static void test_frame(void)
{
    static uint16_t work[NES_VIEW_W * 240];
    srand(7);
    for (unsigned i = 0; i < NES_VIEW_W * 240; ++i) work[i] = (uint16_t)(rand() & 0x803f);
    memset(sprite, 0xee, sizeof sprite);
    nes_frame_invalidate();
    CHECK(nes_frame_upload(work, sink) == NES_VIEW_W * NES_VIEW_LINES);
    check_picture(work);
    /* nothing changed: no traffic */
    sink_count = 0;
    CHECK(nes_frame_upload(work, sink) == 0 && sink_count == 0);
    /* background flag only: no traffic */
    for (unsigned i = 0; i < NES_VIEW_W * 240; ++i) work[i] ^= 0x8000;
    CHECK(nes_frame_upload(work, sink) == 0);
    /* rows outside the visible window are ignored */
    work[0] ^= 1; work[239 * NES_VIEW_W + 5] ^= 2;
    CHECK(nes_frame_upload(work, sink) == 0);
    /* scattered single-pixel changes: exactly those texels */
    unsigned changed = 0;
    for (unsigned k = 0; k < 500; ++k) {
        unsigned y = NES_VIEW_TOP + (unsigned)rand() % NES_VIEW_LINES, x = (unsigned)rand() % NES_VIEW_W;
        uint16_t *p = &work[y * NES_VIEW_W + x];
        uint16_t v = (uint16_t)((*p & 0x8000) | ((*p + 1 + (unsigned)rand() % 62) % 64));
        if ((v & 0x3f) != (*p & 0x3f)) *p = v;
    }
    sink_count = 0;
    changed = nes_frame_upload(work, sink);
    CHECK(changed == sink_count && changed > 0 && changed <= 500);
    check_picture(work);
    /* texel word layout */
    CHECK(nes_texel_word(0, 0, 5) == 5u);
    CHECK(nes_texel_word(255, 223, 64) == (((15u << 12 | 31u << 6 | 63u) << 8) | 64u));
    CHECK(nes_texel_word(64, 64, 1) == (((5u << 12) << 8) | 1u));
}

int main(void)
{
    test_rom();
    test_pad();
    test_menu();
    test_frame();
    printf("PURE_TESTS_PASS checks=%u\n", checks);
    return 0;
}
