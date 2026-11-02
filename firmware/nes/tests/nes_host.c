/* Host harness: the real InfoNES core and port glue on a PC.
 *
 * Platform services are models: a virtual cycle counter, a scripted joypad and
 * a GPU sprite-memory model fed by the same texel stream the board sends.  On
 * every presented frame the sprite memory is checked pixel-for-pixel against
 * the WorkFrame, so the incremental upload can never drift from the picture.
 *
 * usage: nes_host ROM.nes OUT_DIR FRAMES [SCRIPT]
 *   SCRIPT lines: "<first_frame> <last_frame> <hex pad bits>" (NES_PAD_*).
 *   Writes OUT_DIR/frame_NNNNN.ppm every 60 frames and the last frame, and
 *   prints one HOST_RESULT line. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "InfoNES.h"
#include "InfoNES_System.h"
#include "nes_platform.h"

#define HOST_HZ (60099u * 16u)   /* frame_cycles = 16000 */
#define MAX_SCRIPT 64

static const uint8_t rgb[64][3] = {
#include "nes_palette_rgb.inc"
};
/* Start 40 display frames before the 16-bit frame counter wraps, so every
 * run exercises the wrap in pace(). */
static uint64_t clock_now = (0x10000u - 40u) * 16000ull;
static uint32_t frames_seen, presented, uploads, script_n;
static uint32_t script[MAX_SCRIPT][3];
static uint8_t sprite[16][64][64];
static const char *out_dir;
static uint32_t max_frames;

uint64_t nes_cycles(void) { return ++clock_now; }
uint32_t nes_cpu_hz(void) { return HOST_HZ; }
/* 16000 virtual cycles per display frame (~60 Hz at HOST_HZ). */
uint32_t nes_display_frame(void) { return (uint32_t)(++clock_now / 16000u) & 0xffffu; }
/* Every fifth frame the GPU reports busy: that frame must be dropped whole
 * and the next presented picture must still match texel for texel. */
static uint32_t ready_calls, busy_reports;
int nes_video_ready(void)
{
    if (++ready_calls % 5u == 3u) { ++busy_reports; return 0; }
    return 1;
}
void nes_log(const char *t) { fputs(t, stdout); }
void nes_log_u32(uint32_t v) { printf("%u", v); }

/* The frame number is the session's emulated-frame count (V-blank callbacks). */
static void sync_frame(void)
{
    nes_stats_t st;
    nes_session_stats(&st);
    frames_seen = st.frames;
}

uint32_t nes_input_read(void)
{
    uint32_t bits = 0;
    sync_frame();
    for (uint32_t i = 0; i < script_n; ++i)
        if (frames_seen >= script[i][0] && frames_seen <= script[i][1]) bits |= script[i][2];
    if (frames_seen >= max_frames) bits |= NES_PAD_MENU;   /* hold MENU to quit */
    return bits;
}

static void sink(uint32_t word)
{
    uint32_t addr = word >> 8, slot = addr >> 12;
    if (slot >= 16) { fprintf(stderr, "HOST_FAIL slot %u\n", slot); exit(2); }
    sprite[slot][(addr >> 6) & 63][addr & 63] = (uint8_t)word;
    ++uploads;
}

static void write_ppm(unsigned n)
{
    char path[512];
    snprintf(path, sizeof path, "%s/frame_%05u.ppm", out_dir, n);
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); exit(2); }
    fprintf(f, "P6\n%d %d\n255\n", NES_VIEW_W, NES_VIEW_LINES);
    for (unsigned y = 0; y < NES_VIEW_LINES; ++y)
        for (unsigned x = 0; x < NES_VIEW_W; ++x) {
            unsigned t = sprite[(y >> 6) * 4 + (x >> 6)][y & 63][x & 63] - NES_PAL_BASE;
            fwrite(rgb[t & 63], 1, 3, f);
        }
    fclose(f);
}

void nes_video_line(const uint16_t *line, unsigned y)
{
    nes_frame_upload_line(line, y, sink);
}

/* Every picture row has been streamed by now (rows end at 231, the frame is
 * presented at scanline 240): the model must equal the WorkFrame exactly. */
void nes_video_present(uint32_t pad, unsigned menu_pct)
{
    const uint16_t *work = WorkFrame;
    (void)pad; (void)menu_pct;
    sync_frame();
    for (unsigned y = 0; y < NES_VIEW_LINES; ++y)
        for (unsigned x = 0; x < NES_VIEW_W; ++x) {
            unsigned want = (work[(NES_VIEW_TOP + y) * NES_VIEW_W + x] & 0x3f) + NES_PAL_BASE;
            if (sprite[(y >> 6) * 4 + (x >> 6)][y & 63][x & 63] != want) {
                fprintf(stderr, "HOST_FAIL texel mismatch frame %u at %u,%u\n", frames_seen, x, y);
                exit(3);
            }
        }
    ++presented;
    if (frames_seen % 60 == 0) write_ppm(frames_seen);
}

static uint8_t *read_file(const char *path, uint32_t *size)
{
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(2); }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *data = malloc((size_t)n);
    if (!data || fread(data, 1, (size_t)n, f) != (size_t)n) { fprintf(stderr, "read failed\n"); exit(2); }
    fclose(f);
    *size = (uint32_t)n;
    return data;
}

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: nes_host ROM OUT FRAMES [SCRIPT]\n"); return 1; }
    out_dir = argv[2];
    max_frames = (uint32_t)atoi(argv[3]);
    if (argc > 4) {
        FILE *s = fopen(argv[4], "r");
        if (!s) { perror(argv[4]); return 2; }
        while (script_n < MAX_SCRIPT &&
               fscanf(s, "%u %u %x", &script[script_n][0], &script[script_n][1], &script[script_n][2]) == 3)
            ++script_n;
        fclose(s);
    }
    uint32_t size;
    uint8_t *image = read_file(argv[1], &size);
    nes_rom_t rom;
    int status = nes_rom_parse(image, size, &rom);
    if (status != NES_ROM_OK) { printf("HOST_RESULT rom_error=%s\n", nes_rom_error(status)); return 4; }
    nes_session_start(&rom);
    if (InfoNES_Load(NULL)) { printf("HOST_RESULT load_failed\n"); return 5; }
    InfoNES_Main();
    write_ppm(frames_seen);
    nes_stats_t st;
    nes_session_stats(&st);
    printf("HOST_RESULT mapper=%u frames=%u presented=%u busy=%u uploads=%u avg_uploads=%u max_skip=%u\n",
           rom.mapper, st.frames, presented, busy_reports, uploads, presented ? uploads / presented : 0,
           st.max_skip);
    if (busy_reports == 0 || st.skipped_busy != busy_reports) { printf("HOST_FAIL busy path\n"); return 7; }
    return st.frames >= max_frames ? 0 : 6;
}
