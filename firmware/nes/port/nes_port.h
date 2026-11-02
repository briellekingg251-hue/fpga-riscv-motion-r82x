/* SPDX-License-Identifier: GPL-2.0-or-later */
/* NES (InfoNES) port for the fusion SD game platform: shared contracts.
 *
 * The emulator runs from DDR3 as a loader-ABI-3 package (GAMES/NES), reads
 * .NES images from its own SD directory and draws through the GPU command
 * FIFO.  Everything in this header is platform independent so the pure parts
 * (ROM parsing, input mapping, frame upload, menu) build on the host as well.
 */
#ifndef NES_PORT_H
#define NES_PORT_H
#include <stdint.h>

#define NES_GAME_ID   0x4e455331u   /* "NES1"; must match the loader whitelist */
#define NES_GAME_DIR  "NES"
#define NES_ROM_MAX   0x00100000u   /* largest accepted iNES image: 1 MiB */
#define NES_ROM_SLOTS 64u           /* catalog entries scanned from GAMES/NES */

/* InfoNES renders scanlines 8..231 into its 256x240 WorkFrame (NTSC crop). */
#define NES_VIEW_TOP   8
#define NES_VIEW_LINES 224
#define NES_VIEW_W     256

/* 512x300 GPU canvas, shown 2x on the 1024x600 LCD: a crisp 1:1 picture with
 * a 128-pixel control panel on each side. */
#define NES_CANVAS_W  512
#define NES_CANVAS_H  300
#define NES_SCREEN_X  128
#define NES_SCREEN_Y  38

/* GPU sprite texel 0 is transparent, so NES colour n is stored as n + 1. */
#define NES_PAL_BASE   1u
#define NES_PAL_COLORS 64u

/* ---------------------------------------------------------------- ROM */
enum {
    NES_ROM_OK = 0,
    NES_ROM_BAD_MAGIC,
    NES_ROM_NO_PRG,
    NES_ROM_TRUNCATED,
    NES_ROM_TOO_BIG,
    NES_ROM_NES2_UNSUPPORTED,
    NES_ROM_MAPPER_UNSUPPORTED
};
typedef struct {
    uint8_t header[16];        /* sanitised iNES 1.0 header for InfoNES */
    const uint8_t *trainer;    /* 512 bytes, or 0 */
    const uint8_t *prg;
    const uint8_t *chr;        /* 0 when the cartridge uses CHR RAM */
    uint32_t prg_bytes, chr_bytes;
    unsigned mapper;
} nes_rom_t;
/* Validates an in-memory image; out is fully written only on NES_ROM_OK. */
int nes_rom_parse(const uint8_t *image, uint32_t size, nes_rom_t *out);
/* Mapper number from a raw 16-byte header, with the same sanitising rules. */
int nes_rom_header_mapper(const uint8_t header[16], unsigned *mapper);
const char *nes_rom_error(int code);
/* Implemented next to InfoNES's MapperTable. */
int nes_mapper_supported(unsigned mapper);

/* -------------------------------------------------------------- input */
/* Joypad bits in NES shift order, as InfoNES's PAD1_Latch expects. */
#define NES_PAD_A      0x01u
#define NES_PAD_B      0x02u
#define NES_PAD_SELECT 0x04u
#define NES_PAD_START  0x08u
#define NES_PAD_UP     0x10u
#define NES_PAD_DOWN   0x20u
#define NES_PAD_LEFT   0x40u
#define NES_PAD_RIGHT  0x80u
#define NES_PAD_MENU   0x100u  /* port-level button, never reaches the NES */
#define NES_TOUCH_MAX  5u

typedef struct { int16_t x, y; } nes_point_t;
/* Canvas-coordinate contacts -> OR of every button they press. */
uint32_t nes_pad_from_points(const nes_point_t *points, unsigned count);

typedef struct { int16_t x, y, w, h; uint32_t bit; const char *label; } nes_button_t;
extern const nes_button_t nes_buttons[];
extern const unsigned nes_button_count;
/* D-pad geometry, shared by hit testing and drawing. */
#define NES_DPAD_CX    64
#define NES_DPAD_CY    160
#define NES_DPAD_TOP   80
#define NES_DPAD_BOTTOM 240
#define NES_DPAD_DEAD  10
#define NES_DPAD_ARM   34
#define NES_DPAD_WIDTH 24
/* A/B area: B left of the split, A right of it, both inside the band. */
#define NES_AB_LEFT    384
#define NES_AB_TOP     96
#define NES_AB_BOTTOM  240
#define NES_AB_SPLIT   448
#define NES_AB_BOTH    8      /* half-width of the strip that presses A+B */
#define NES_B_CX       416
#define NES_B_CY       184
#define NES_A_CX       478
#define NES_A_CY       150
#define NES_AB_RADIUS  26

/* --------------------------------------------------------------- frame */
/* 256x224 picture -> 4x4 GPU sprite slots of 64x64 (last row 32 lines). */
#define NES_TILE_SLOT0 0u
#define NES_TILE_COLS  4u
#define NES_TILE_ROWS  4u
typedef void (*nes_texel_sink_t)(uint32_t word);
/* Forget what the GPU holds; the next upload rewrites every texel. */
void nes_frame_invalidate(void);
/* Streams only texels that changed since the last upload; returns the count.
 * line: one 256-pixel WorkFrame row (WORDs: colour | 0x8000 bg flag, 4-byte
 * aligned); y: picture row 0..NES_VIEW_LINES-1. */
uint32_t nes_frame_upload_line(const uint16_t *line, unsigned y, nes_texel_sink_t sink);
/* Whole picture: rows NES_VIEW_TOP.. of InfoNES's 256x240 WorkFrame. */
uint32_t nes_frame_upload(const uint16_t *work, nes_texel_sink_t sink);
/* GPU sprite-memory write word for one texel (command 26 payload). */
static inline uint32_t nes_texel_word(unsigned x, unsigned y, unsigned texel)
{
    unsigned slot = NES_TILE_SLOT0 + (y >> 6) * NES_TILE_COLS + (x >> 6);
    return ((slot << 12 | (y & 63u) << 6 | (x & 63u)) << 8) | (texel & 0xffu);
}

/* ---------------------------------------------------------------- menu */
#define NES_MENU_ROWS  6u
typedef struct {
    char name[13];             /* "NAME.NES" for display */
    uint32_t cluster, size;
    unsigned mapper;
    uint8_t usable;            /* parsed header and supported mapper */
} nes_entry_t;
typedef struct {
    nes_entry_t entry[NES_ROM_SLOTS];
    unsigned count, page, armed, have_sequence;
    uint32_t sequence;
} nes_menu_t;
enum { NES_MENU_NONE, NES_MENU_REDRAW, NES_MENU_PLAY, NES_MENU_EXIT };
/* Keeps entries sorted by name; returns 0, or -1 when the catalog is full. */
int nes_menu_add(nes_menu_t *m, const nes_entry_t *e);
unsigned nes_menu_pages(const nes_menu_t *m);
/* Touch state machine: arms on a lift, acts on the next press. */
int nes_menu_touch(nes_menu_t *m, uint32_t sequence, int healthy, int down,
                   int x, int y, unsigned *selected);
/* Menu geometry (canvas pixels). */
#define NES_MENU_LIST_X  32
#define NES_MENU_LIST_Y  52
#define NES_MENU_ROW_H   30
#define NES_MENU_LIST_W  448
#define NES_MENU_BTN_Y   250
#define NES_MENU_BTN_H   40
/* Bottom buttons (x, width): PREV, EXIT, NEXT. */
#define NES_MENU_PREV_X  16
#define NES_MENU_PREV_W  128
#define NES_MENU_EXIT_X  176
#define NES_MENU_EXIT_W  160
#define NES_MENU_NEXT_X  368
#define NES_MENU_NEXT_W  128

#endif
