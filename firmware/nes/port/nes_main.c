/* SPDX-License-Identifier: GPL-2.0-or-later */
/* NES package entry: SD catalog, ROM list, cartridge loading and the
 * hand-back to the resident loader.
 *
 * Cartridges are the .NES files in SD:/GAMES/NES.  A selected file is copied
 * whole into DDR (at most 1 MiB), validated, and handed to InfoNES.  Holding
 * MENU in game returns here; EXIT jumps back to the console's game list. */
#include <stddef.h>
#include "soc.h"
#include "storage.h"
#include "InfoNES.h"
#include "nes_board.h"
#include "nes_platform.h"

#define HEADER_BYTES 16u
#define READ_CHUNK   0x8000u     /* progress-bar granularity */
#define LIFT_MS      2000u       /* give up waiting for a lift after this */

static nes_menu_t menu;
static uint8_t rom_image[NES_ROM_MAX] __attribute__((aligned(64)));
static nes_rom_t rom;

static void __attribute__((noreturn)) exit_to_loader(void)
{
    uart_puts("NES_EXIT to loader\n");
    nes_video_wait();
    storage_jump(LOADER_ENTRY_ADDR);
}

/* Blocks until no contact is held (bounded), so a press that ended one screen
 * cannot act on the next.  The controller stops publishing once fingers are
 * lifted, so an idle panel reads as stale (unhealthy, no contact). */
static void wait_lift(void)
{
    uint64_t start = nes_cycles(), limit = (uint64_t)CPU_CLOCK_HZ / 1000u * LIFT_MS;
    nes_touch_t t;
    do { nes_touch_sample(&t); } while (t.down && nes_cycles() - start < limit);
}

static void wait_touch(void)
{
    nes_touch_t t;
    wait_lift();
    do { nes_touch_sample(&t); } while (!(t.healthy && t.down));
    wait_lift();
}

/* FAT 8.3 directory name "NAME    NES" -> "NAME.NES"; 0 unless extension NES. */
static int nes_file_name(const char raw[11], char out[13])
{
    unsigned n = 0;
    if (raw[8] != 'N' || raw[9] != 'E' || raw[10] != 'S') return 0;
    for (unsigned i = 0; i < 8 && raw[i] != ' '; ++i) out[n++] = raw[i];
    if (!n) return 0;
    out[n++] = '.'; out[n++] = 'N'; out[n++] = 'E'; out[n++] = 'S';
    out[n] = 0;
    return 1;
}

static void catalog_entry(const char raw[11], const sd_file_t *file)
{
    nes_entry_t e;
    uint8_t header[HEADER_BYTES];
    if (!nes_file_name(raw, e.name) || (file->attr & 0x10)) return;
    e.cluster = file->cluster;
    e.size = file->size;
    e.mapper = 0;
    e.usable = 0;
    if (file->size >= HEADER_BYTES && file->size <= NES_ROM_MAX &&
        !fat_read(file, 0, header, HEADER_BYTES) &&
        nes_rom_header_mapper(header, &e.mapper) == NES_ROM_OK)
        e.usable = (uint8_t)nes_mapper_supported(e.mapper);
    if (nes_menu_add(&menu, &e)) uart_puts("NES catalog full, file skipped\n");
}

static int scan_catalog(void)
{
    sd_file_t games, dir, file;
    char raw[12];
    if (sd_init() || fat_mount()) return -1;
    if (fat_find(fat_root(), "GAMES      ", &games) || !(games.attr & 0x10)) return -1;
    if (fat_find(games.cluster, "NES        ", &dir) || !(dir.attr & 0x10)) return -1;
    for (unsigned i = 0; i < 4096u; ++i) {
        int r = fat_dir_entry(dir.cluster, i, raw, &file);
        if (r == 1) break;
        if (r < 0) return -1;
        if (r == 0) catalog_entry(raw, &file);
    }
    uart_puts("NES catalog ");
    uart_putu(menu.count);
    uart_puts(" file(s)\n");
    return 0;
}

static int load_cartridge(const nes_entry_t *e)
{
    sd_file_t file = {e->cluster, e->size, 0};
    for (uint32_t off = 0; off < e->size; off += READ_CHUNK) {
        uint32_t n = e->size - off < READ_CHUNK ? e->size - off : READ_CHUNK;
        nes_video_progress("LOADING CARTRIDGE...", off, e->size);
        if (fat_read(&file, off, rom_image + off, n)) return -1;
    }
    return nes_rom_parse(rom_image, e->size, &rom);
}

static void play(const nes_entry_t *e)
{
    int status = load_cartridge(e);
    if (status < 0) { nes_video_message("SD READ ERROR", e->name); wait_touch(); return; }
    if (status != NES_ROM_OK) { nes_video_message(nes_rom_error(status), e->name); wait_touch(); return; }
    uart_puts("NES_PLAY ");
    uart_puts(e->name);
    uart_puts(" mapper ");
    uart_putu(rom.mapper);
    uart_puts("\n");
    wait_lift();
    nes_video_init();
    nes_session_start(&rom);
    if (InfoNES_Load(NULL)) { nes_video_message("CARTRIDGE RESET FAILED", e->name); wait_touch(); return; }
    InfoNES_Main();
    nes_stats_t st;
    nes_session_stats(&st);
    uart_puts("NES_QUIT frames=");  uart_putu(st.frames);
    uart_puts(" presented=");        uart_putu(st.presented);
    uart_puts(" busy_drop=");        uart_putu(st.skipped_busy);
    uart_puts(" late=");             uart_putu(st.late_frames);
    uart_puts(" max_skip=");         uart_putu(st.max_skip);
    uart_puts(" work_avg=");         uart_putu(st.work_frames ? (uint32_t)(st.work_cycles / st.work_frames) : 0);
    uart_puts(" work_max=");         uart_putu(st.work_max);
    uart_puts(" present_avg=");      uart_putu(st.presented ? (uint32_t)(st.present_cycles / st.presented) : 0);
    uart_puts(" texels=");           uart_putu(nes_video_texels());
    uart_puts(" misaligned=");       uart_putu(nes_trap_misaligned());
    uart_puts("\n");
    wait_lift();
}

static void run_menu(void)
{
    const char *status = menu.count ? NULL : "COPY .NES FILES TO SD:/GAMES/NES";
    for (;;) {
        nes_video_menu(&menu, status);
        for (;;) {
            nes_touch_t t;
            unsigned selected = 0;
            nes_touch_sample(&t);
            int x = t.count ? t.point[0].x : 0, y = t.count ? t.point[0].y : 0;
            int action = nes_menu_touch(&menu, t.sequence, t.healthy, t.down, x, y, &selected);
            if (action == NES_MENU_EXIT) exit_to_loader();
            if (action == NES_MENU_REDRAW) break;
            if (action == NES_MENU_PLAY) {
                play(&menu.entry[selected]);
                menu.armed = 0;
                nes_video_init();
                break;
            }
        }
    }
}

void nes_main(void)
{
    uart_puts("\nNES (InfoNES 0.97J) on O2, loader ABI 3, cpu_hz=");
    uart_putu(CPU_CLOCK_HZ);
    uart_puts("\n");
    nes_video_init();
    nes_video_progress("READING SD CARD...", 0, 1);
    if (scan_catalog()) {
        nes_video_message("SD:/GAMES/NES NOT READABLE", "TOUCH TO RETURN TO THE CONSOLE MENU");
        wait_touch();
        exit_to_loader();
    }
    run_menu();
}
