/* rv32sim: functional RV32I + Zmmul + Zicsr simulator of the SD game platform.
 *
 * Runs the real resident loader (program.hex) and the real game binaries that
 * it loads from an SD card image.  Peripheral models follow the RTL register
 * maps: UART/GPIO/MTIME (p2_peripherals), GPU command FIFO + GT911 snapshot
 * (fn_mmio_hub / fn_gpu_cmd / fn_raster), byte SPI SD (fn_sd_spi) with an SDHC
 * card behind it.  The cached RAM window 0x80000000..0x83ffffff covers the
 * 128 KiB block RAM and the DDR3 region above it.
 *
 * DIV/REM are illegal (the s80 core implements Zmmul only).  Misaligned loads
 * and stores trap with the standard causes, as on the core.
 *
 * usage: rv32sim --hex program.hex --sd card.img [--script touch.txt]
 *                [--frames DIR] [--max-ms N] [--save-sd] [--trace-calls]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define RAM_BASE   0x80000000u
#define RAM_BYTES  0x04000000u
#define BRAM_BYTES 0x00020000u
#define CPU_HZ     162000000ull
#define FB_W 512
#define FB_H 300
#define FRAME_CYCLES (CPU_HZ / 60u)
#define PIX_TO_CPU_NUM 162u   /* GPU runs at 51.2 MHz */
#define PIX_TO_CPU_DEN 51u

static uint8_t *ram;
static uint32_t x[32], pc;
static uint64_t instret, cycles;
static uint32_t csr_mstatus, csr_mtvec, csr_mepc, csr_mcause, csr_mtval, csr_mscratch, csr_mie;
static int halted, exit_code;
static uint64_t limit_cycles = 0;
static unsigned extra_cpi = 0; /* --cpi N: N cycles per instruction (pessimistic memory model) */

static void fatal(const char *msg, uint32_t value)
{
    fprintf(stderr, "\nrv32sim FATAL: %s 0x%08x pc=0x%08x instret=%llu ms=%llu\n", msg, value, pc,
            (unsigned long long)instret, (unsigned long long)(cycles / (CPU_HZ / 1000)));
    for (int i = 0; i < 32; i += 4)
        fprintf(stderr, "x%-2d %08x %08x %08x %08x\n", i, x[i], x[i + 1], x[i + 2], x[i + 3]);
    halted = 1;
    exit_code = 2;
}

/* ------------------------------------------------------------------ GPU */
static uint8_t fb[2][FB_H][FB_W];
static uint32_t gpu_pal[256];
static uint8_t sprite_mem[64 * 4096];
static uint64_t sprite_valid;
static uint16_t font[2048];
static int draw_buf = 1, disp_buf = 0;
static struct { uint32_t color, x0, y0, w, h, u0, v0, dudx, dvdx, dudy, dvdy, flags; } gr;
static uint64_t gpu_ring[1024];
static unsigned gpu_head, gpu_count;
static uint64_t gpu_last_finish;
static uint32_t gpu_swaps;
static uint64_t gpu_commands, gpu_uploads;
static const char *frame_dir;
static unsigned frame_every = 0, frame_serial;

static int16_t s16(uint32_t v) { return (int16_t)(v & 0xffffu); }

static void put_pixel(int x0, int y0, uint8_t c, int dither)
{
    if (x0 < 0 || y0 < 0 || x0 >= FB_W || y0 >= FB_H) return;
    if (dither && ((x0 + y0) & 1)) return;
    fb[draw_buf][y0][x0] = c;
}

/* Returns pixel-clock work for the cost model. */
static uint64_t raster(int mode, int x0, int y0, int w, int h, uint32_t color, uint32_t u0,
                       uint32_t v0, uint32_t dudx, uint32_t dvdx, uint32_t dudy, uint32_t dvdy,
                       unsigned src, unsigned flags, int radius)
{
    uint64_t work = 8;
    uint32_t urow = u0, vrow = v0;
    int dither = (flags & 8) != 0;
    for (int j = 0; j < h; ++j) {
        int dy = y0 + j;
        if (dy >= FB_H) break;
        if (dy >= 0) {
            uint32_t u = urow, v = vrow;
            for (int i = 0; i < w; ++i, u += dudx, v += dvdx) {
                int dx = x0 + i;
                if (dx >= FB_W) break;
                if (dx < 0) continue;
                ++work;
                if (mode == 0) put_pixel(dx, dy, (uint8_t)color, dither);
                else if (mode == 2) {
                    if (!(flags & 2) && ((u >> 22) || (v >> 22))) continue;
                    unsigned addr = (src << 12) | (((v >> 16) & 63) << 6) | ((u >> 16) & 63);
                    uint8_t t = (sprite_valid >> src) & 1 ? sprite_mem[addr] : 0;
                    if (!t) continue;
                    put_pixel(dx, dy, (uint8_t)((flags & 1) ? color : (flags & 4) ? t + color : t), dither);
                } else if (mode == 3) {
                    if ((u >> 20) || (v >> 20)) continue;
                    uint16_t row = font[((src & 127) << 4) | ((v >> 16) & 15)];
                    if ((row >> (15 - ((u >> 16) & 15))) & 1) put_pixel(dx, dy, (uint8_t)color, 0);
                } else if (mode == 4) {
                    int a = i - radius, b = j - radius;
                    if (a * a + b * b <= radius * radius + radius) put_pixel(dx, dy, (uint8_t)color, 0);
                }
            }
        }
        urow += dudy;
        vrow += dvdy;
    }
    return work;
}

static void dump_frame(const char *tag)
{
    char path[512];
    FILE *f;
    if (!frame_dir) return;
    snprintf(path, sizeof path, "%s/%05u_%s.ppm", frame_dir, frame_serial++, tag);
    f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", path); return; }
    fprintf(f, "P6\n%d %d\n255\n", FB_W, FB_H);
    for (int y = 0; y < FB_H; ++y)
        for (int xx = 0; xx < FB_W; ++xx) {
            uint32_t c = gpu_pal[fb[disp_buf][y][xx]];
            fputc((c >> 16) & 255, f); fputc((c >> 8) & 255, f); fputc(c & 255, f);
        }
    fclose(f);
    printf("[sim %llu ms] frame %s\n", (unsigned long long)(cycles / (CPU_HZ / 1000)), path);
}

static uint64_t gpu_execute(unsigned idx, uint32_t d, uint64_t start)
{
    uint64_t pix = 2;
    ++gpu_commands;
    switch (idx) {
    case 1: gr.color = d & 255; break;
    case 2: gr.x0 = d & 0xffff; gr.y0 = d >> 16; break;
    case 3: gr.w = d & 1023; gr.h = (d >> 16) & 1023; break;
    case 4: gr.u0 = d; break;
    case 5: gr.v0 = d; break;
    case 6: gr.dudx = d; break;
    case 7: gr.dvdx = d; break;
    case 8: gr.dudy = d; break;
    case 9: gr.dvdy = d; break;
    case 10: gr.flags = d & 15; break;
    case 16: case 17: pix += raster(0, 0, 0, FB_W, FB_H, d & 255, 0, 0, 0, 0, 0, 0, 0, 0, 0); break;
    case 18: pix += raster(0, s16(gr.x0), s16(gr.y0), gr.w, gr.h, gr.color, 0, 0, 0, 0, 0, 0, 0, gr.flags & 8, 0); break;
    case 19: pix += raster(2, s16(gr.x0), s16(gr.y0), gr.w, gr.h, gr.color, gr.u0, gr.v0, gr.dudx, gr.dvdx,
                           gr.dudy, gr.dvdy, d & 63, gr.flags, 0); break;
    case 20: pix += raster(3, s16(gr.x0), s16(gr.y0), gr.w, gr.h, gr.color, gr.u0, gr.v0, gr.dudx, gr.dvdx,
                           gr.dudy, gr.dvdy, d & 127, 0, 0); break;
    case 21: {
        static const uint32_t inv[4] = {0x10000, 0x8000, 0x5556, 0x4000};
        unsigned sc = ((d >> 25) & 3) + 1;
        pix += raster(3, d & 511, (d >> 9) & 511, 16 * sc, 16 * sc, gr.color, 0, 0, inv[sc - 1], 0, 0,
                      inv[sc - 1], (d >> 18) & 127, 0, 0);
        break;
    }
    case 22: {
        int r = (d >> 18) & 63;
        pix += raster(4, (int)(d & 511) - r, (int)((d >> 9) & 511) - r, 2 * r + 1, 2 * r + 1, d >> 24,
                      0, 0, 0, 0, 0, 0, 0, 0, r);
        break;
    }
    case 23: pix += raster(0, d & 511, (d >> 9) & 511, 1, 1, d >> 24, 0, 0, 0, 0, 0, 0, 0, 0, 0); break;
    case 24: gpu_pal[d >> 24] = d & 0xffffff; break;
    case 25: {
        /* Shown from the next frame boundary; drawing continues into the other buffer. */
        uint64_t when = (start / FRAME_CYCLES + 1) * FRAME_CYCLES;
        disp_buf = draw_buf;
        draw_buf ^= 1;
        ++gpu_swaps;
        if (frame_every && gpu_swaps % frame_every == 0) dump_frame("swap");
        return when - start + 4;
    }
    case 26:
        ++gpu_uploads;
        sprite_mem[(d >> 8) & 0x3ffff] = (uint8_t)d;
        sprite_valid |= 1ull << ((d >> 20) & 63);
        break;
    default: break;
    }
    return pix * PIX_TO_CPU_NUM / PIX_TO_CPU_DEN;
}

static void gpu_retire(void)
{
    while (gpu_count && gpu_ring[gpu_head] <= cycles) {
        gpu_head = (gpu_head + 1) & 1023;
        --gpu_count;
    }
}

static void gpu_push(unsigned idx, uint32_t d)
{
    uint64_t start, finish;
    gpu_retire();
    if (gpu_count == 1024) {
        cycles = gpu_ring[gpu_head];
        gpu_retire();
    }
    start = gpu_last_finish > cycles ? gpu_last_finish : cycles;
    finish = start + gpu_execute(idx, d, start);
    gpu_last_finish = finish;
    gpu_ring[(gpu_head + gpu_count) & 1023] = finish;
    ++gpu_count;
}

/* ------------------------------------------------------------------ touch */
typedef struct { uint64_t ms; int kind, x, y; char name[64]; } script_t;
static script_t *script;
static unsigned script_len, script_pos;
static int touch_down, touch_x, touch_y;
static uint32_t touch_seq;

static void load_script(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[256];
    unsigned cap = 0;
    if (!f) { fprintf(stderr, "cannot open script %s\n", path); exit(1); }
    while (fgets(line, sizeof line, f)) {
        script_t s;
        char verb[32];
        memset(&s, 0, sizeof s);
        if (line[0] == '#' || sscanf(line, "%llu %31s", (unsigned long long *)&s.ms, verb) != 2) continue;
        if (!strcmp(verb, "down")) { s.kind = 1; sscanf(line, "%*llu %*s %d %d", &s.x, &s.y); }
        else if (!strcmp(verb, "up")) s.kind = 2;
        else if (!strcmp(verb, "dump")) { s.kind = 3; sscanf(line, "%*llu %*s %63s", s.name); }
        else if (!strcmp(verb, "quit")) s.kind = 4;
        else if (!strcmp(verb, "tap")) { s.kind = 5; sscanf(line, "%*llu %*s %d %d", &s.x, &s.y); }
        else { fprintf(stderr, "bad script line: %s", line); exit(1); }
        if (script_len == cap) { cap = cap ? cap * 2 : 64; script = realloc(script, cap * sizeof *script); }
        script[script_len++] = s;
    }
    fclose(f);
}

static void run_script(void)
{
    uint64_t ms = cycles / (CPU_HZ / 1000);
    while (script_pos < script_len && script[script_pos].ms <= ms) {
        script_t *s = &script[script_pos++];
        switch (s->kind) {
        case 1: touch_down = 1; touch_x = s->x; touch_y = s->y; ++touch_seq; break;
        case 2: touch_down = 0; ++touch_seq; break;
        case 3: dump_frame(s->name); break;
        case 4: printf("[sim %llu ms] script quit\n", (unsigned long long)ms); halted = 1; break;
        case 5: {
            /* down now, up 120 ms later: insert as a follow-up event */
            touch_down = 1; touch_x = s->x; touch_y = s->y; ++touch_seq;
            s->kind = 2; s->ms = ms + 120; --script_pos;
            break;
        }
        }
    }
    if (touch_down) ++touch_seq; /* the GT911 poller keeps publishing while held */
}

/* ------------------------------------------------------------------ SD card */
static uint8_t *sd_image;
static uint32_t sd_sectors;
static int sd_dirty;
static uint32_t sd_cs = 1, sd_divider = 203, sd_result = 0xff;
static uint8_t sd_cmd[6];
static unsigned sd_cmd_pos;
static uint8_t sd_q[1100];
static unsigned sd_q_head, sd_q_len;
static int sd_idle = 1, sd_app;
static int sd_wstate; /* 0 none, 1 wait token, 2 data */
static uint32_t sd_wlba;
static unsigned sd_wpos;
static uint8_t sd_wbuf[514];
static uint64_t sd_reads, sd_writes;

static uint16_t crc16_ccitt(const uint8_t *p, unsigned n)
{
    uint16_t crc = 0;
    while (n--) {
        crc ^= (uint16_t)(*p++) << 8;
        for (int k = 0; k < 8; ++k) crc = (uint16_t)((crc << 1) ^ ((crc & 0x8000) ? 0x1021 : 0));
    }
    return crc;
}

static void sd_push(uint8_t b) { if (sd_q_len < sizeof sd_q) sd_q[(sd_q_head + sd_q_len++) % sizeof sd_q] = b; }

static void sd_command(void)
{
    unsigned cmd = sd_cmd[0] & 63;
    uint32_t arg = (uint32_t)sd_cmd[1] << 24 | (uint32_t)sd_cmd[2] << 16 | (uint32_t)sd_cmd[3] << 8 | sd_cmd[4];
    int app = sd_app;
    uint8_t r1 = sd_idle ? 1 : 0;
    sd_app = 0;
    sd_push(0xff);
    if (app && cmd == 41) { sd_idle = 0; sd_push(0); return; }
    switch (cmd) {
    case 0: sd_idle = 1; sd_push(1); break;
    case 8: sd_push(r1); sd_push(0); sd_push(0); sd_push(1); sd_push(0xaa); break;
    case 55: sd_app = 1; sd_push(r1); break;
    case 58: sd_push(r1); sd_push(0xc0); sd_push(0xff); sd_push(0x80); sd_push(0); break;
    case 16: sd_push(r1); break;
    case 9: {
        uint8_t csd[16] = {0x40, 0x0e, 0, 0x32, 0x5b, 0x59, 0, 0, 0, 0, 0x7f, 0x80, 0x0a, 0x40, 0, 0x01};
        uint32_t c = sd_sectors / 1024 - 1;
        uint16_t crc;
        csd[7] = (c >> 16) & 63; csd[8] = (c >> 8) & 255; csd[9] = c & 255;
        crc = crc16_ccitt(csd, 16);
        sd_push(r1); sd_push(0xff); sd_push(0xfe);
        for (int i = 0; i < 16; ++i) sd_push(csd[i]);
        sd_push(crc >> 8); sd_push(crc & 255);
        break;
    }
    case 17:
        if (arg >= sd_sectors) { sd_push(0x40); break; }
        {
            const uint8_t *p = sd_image + (uint64_t)arg * 512;
            uint16_t crc = crc16_ccitt(p, 512);
            sd_push(r1); sd_push(0xff); sd_push(0xfe);
            for (int i = 0; i < 512; ++i) sd_push(p[i]);
            sd_push(crc >> 8); sd_push(crc & 255);
            ++sd_reads;
        }
        break;
    case 24:
        if (arg >= sd_sectors) { sd_push(0x40); break; }
        sd_push(r1);
        sd_wstate = 1; sd_wlba = arg; sd_wpos = 0;
        break;
    default: sd_push(0x04); break;
    }
}

static uint8_t sd_transfer(uint8_t tx)
{
    uint8_t rx = 0xff;
    cycles += (uint64_t)sd_divider * 16u; /* real SPI byte time */
    if (sd_cs) return 0xff;
    if (sd_q_len) { rx = sd_q[sd_q_head]; sd_q_head = (sd_q_head + 1) % sizeof sd_q; --sd_q_len; }
    if (sd_wstate == 1) {
        if (tx == 0xfe) sd_wstate = 2;
        return rx;
    }
    if (sd_wstate == 2) {
        sd_wbuf[sd_wpos++] = tx;
        if (sd_wpos == 514) {
            uint16_t crc = crc16_ccitt(sd_wbuf, 512);
            sd_wstate = 0;
            if ((sd_wbuf[512] << 8 | sd_wbuf[513]) != crc) { sd_push(0x0b); return rx; }
            memcpy(sd_image + (uint64_t)sd_wlba * 512, sd_wbuf, 512);
            sd_dirty = 1;
            ++sd_writes;
            sd_push(0xe5); sd_push(0); sd_push(0); sd_push(0xff);
        }
        return rx;
    }
    if (sd_cmd_pos == 0 && (tx & 0xc0) != 0x40) return rx;
    sd_cmd[sd_cmd_pos++] = tx;
    if (sd_cmd_pos == 6) { sd_cmd_pos = 0; sd_q_len = 0; sd_command(); }
    return rx;
}

/* ------------------------------------------------------------------ bus */
static uint64_t mmio_ops;
static uint32_t backlight = 70;

static uint32_t mmio_read(uint32_t a)
{
    ++mmio_ops;
    cycles += 6;
    if (a == 0x10000004u) return 0;                  /* UART not busy */
    if (a == 0x10002000u) return (uint32_t)cycles;
    if (a == 0x10002004u) return (uint32_t)(cycles >> 32);
    if (a >= 0x10004000u && a < 0x10004100u) {
        gpu_retire();
        switch (a & 0xff) {
        case 0x00: return 0x464e4731u;
        case 0x04: return (gpu_count == 0 ? 1u : 0u) | (gpu_count == 1024 ? 2u : 0u) |
                          (gpu_last_finish <= cycles ? 4u : 0u) | ((1024u-gpu_count)<<16);
        case 0x08: return (uint32_t)(cycles / FRAME_CYCLES) & 0xffff;
        case 0x0c: {
            /* swaps completed by now */
            return gpu_last_finish <= cycles ? gpu_swaps & 0xffff : (gpu_swaps ? gpu_swaps - 1 : 0) & 0xffff;
        }
        case 0x10: return (FB_H << 16) | FB_W;
        case 0x14: return (600u << 16) | 1024u;
        case 0x18: return (uint32_t)CPU_HZ;
        }
        return 0;
    }
    if (a == 0x10004100u) return touch_down ? 0x00000113u : 0x00000002u;
    if (a == 0x10004104u) return (uint32_t)touch_y << 16 | (uint32_t)touch_x;
    if (a == 0x10004108u) return touch_seq;
    if (a == 0x1000410cu) return 0;
    if (a >= 0x10004200u && a < 0x10004300u) {
        switch (a & 0xff) {
        case 0x00: return 0x53445331u;
        case 0x04: return 2u;
        case 0x08: return sd_cs;
        case 0x0c: return sd_divider;
        case 0x10: return sd_result;
        }
        return 0;
    }
    if (a == 0x10004f00u) return 1u; /* DDR3 calibrated */
    if (a == 0x10004f04u) return backlight;
    if (a >= 0x10004300u && a < 0x10005000u) return 0;
    return 0;
}

static void mmio_write(uint32_t a, uint32_t v, unsigned size)
{
    ++mmio_ops;
    cycles += 4;
    if (a == 0x10000000u) { putchar((int)(v & 255)); if ((v & 255) == '\n') fflush(stdout); return; }
    if (a == 0x10001000u) return;
    if (a == 0x10004f04u) { backlight = v; printf("[sim] backlight %u%%
", v); return; }
    if (a == 0x20000000u) { printf("[sim] exit write %u\n", v); halted = 1; exit_code = v == 1 ? 0 : 3; return; }
    if (a >= 0x10004000u && a < 0x10004100u) {
        if (size != 4) { fatal("sub-word GPU store", a); return; }
        gpu_push((a >> 2) & 63, v);
        return;
    }
    if (a >= 0x10004200u && a < 0x10004300u) {
        switch (a & 0xff) {
        case 0x08: sd_cs = v & 1; if (sd_cs) { sd_cmd_pos = 0; } break;
        case 0x0c: sd_divider = v & 0xffff; break;
        case 0x10: sd_result = sd_transfer((uint8_t)v); break;
        }
        return;
    }
}

static int in_ram(uint32_t a, unsigned n) { return a >= RAM_BASE && a - RAM_BASE <= RAM_BYTES - n; }

static int load(uint32_t a, unsigned n, uint32_t *out)
{
    if (a & (n - 1)) return 4;
    if (in_ram(a, n)) {
        const uint8_t *p = ram + (a - RAM_BASE);
        *out = n == 1 ? p[0] : n == 2 ? (uint32_t)(p[0] | p[1] << 8) :
               (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
        return 0;
    }
    if (a >= 0x10000000u && a < 0x10010000u) {
        uint32_t w = mmio_read(a & ~3u);
        *out = n == 4 ? w : n == 2 ? (w >> ((a & 2) * 8)) & 0xffff : (w >> ((a & 3) * 8)) & 255;
        return 0;
    }
    return 5;
}

static int store(uint32_t a, unsigned n, uint32_t v)
{
    if (a & (n - 1)) return 6;
    if (in_ram(a, n)) {
        uint8_t *p = ram + (a - RAM_BASE);
        p[0] = (uint8_t)v;
        if (n > 1) p[1] = (uint8_t)(v >> 8);
        if (n > 2) { p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
        return 0;
    }
    if ((a >= 0x10000000u && a < 0x10010000u) || a == 0x20000000u) { mmio_write(a, v, n); return 0; }
    return 7;
}

/* ------------------------------------------------------------------ CPU */
static void trap(uint32_t cause, uint32_t tval)
{
    if (!csr_mtvec) {
        static const char *names[] = {"misaligned fetch", "fetch fault", "illegal instruction", "breakpoint",
                                      "misaligned load", "load fault", "misaligned store", "store fault",
                                      "ecall U", "", "", "ecall M"};
        fatal(cause < 12 ? names[cause] : "trap", tval);
        return;
    }
    csr_mepc = pc;
    csr_mcause = cause;
    csr_mtval = tval;
    csr_mstatus = (csr_mstatus & ~0x1888u) | ((csr_mstatus & 8u) << 4) | 0x1800u;
    pc = csr_mtvec & ~3u;
}

static int csr_access(unsigned id, uint32_t *value, uint32_t wdata, int write)
{
    uint32_t *r = NULL;
    switch (id) {
    case 0x300: r = &csr_mstatus; break;
    case 0x304: r = &csr_mie; break;
    case 0x305: r = &csr_mtvec; break;
    case 0x340: r = &csr_mscratch; break;
    case 0x341: r = &csr_mepc; break;
    case 0x342: r = &csr_mcause; break;
    case 0x343: r = &csr_mtval; break;
    case 0x301: *value = 0x40000100u; return 0;
    case 0x344: *value = 0; return 0;
    case 0xf14: *value = 0; return 0;
    case 0xb00: case 0xc00: case 0xc01: *value = (uint32_t)cycles; return 0;
    case 0xb80: case 0xc80: case 0xc81: *value = (uint32_t)(cycles >> 32); return 0;
    case 0xb02: case 0xc02: *value = (uint32_t)instret; return 0;
    case 0xb82: case 0xc82: *value = (uint32_t)(instret >> 32); return 0;
    default: return -1;
    }
    *value = *r;
    if (write) *r = wdata;
    return 0;
}

static void step(void)
{
    uint32_t insn, next = pc + 4;
    unsigned rd, rs1, rs2, f3, f7;
    uint32_t a, b, imm, v;
    int err;

    if (pc & 3) { trap(0, pc); return; }
    if (!in_ram(pc, 4)) { trap(1, pc); return; }
    insn = *(uint32_t *)(ram + (pc - RAM_BASE));
    rd = (insn >> 7) & 31; rs1 = (insn >> 15) & 31; rs2 = (insn >> 20) & 31;
    f3 = (insn >> 12) & 7; f7 = insn >> 25;
    a = x[rs1]; b = x[rs2];
    ++instret;
    cycles += 1 + extra_cpi;

    switch (insn & 0x7f) {
    case 0x37: if (rd) x[rd] = insn & 0xfffff000u; break;
    case 0x17: if (rd) x[rd] = pc + (insn & 0xfffff000u); break;
    case 0x6f:
        imm = ((insn >> 31) ? 0xfff00000u : 0) | (insn & 0xff000u) | ((insn >> 9) & 0x800u) | ((insn >> 20) & 0x7feu);
        if (rd) x[rd] = next;
        next = pc + imm;
        cycles += 1;
        break;
    case 0x67:
        imm = (uint32_t)((int32_t)insn >> 20);
        v = next;
        next = (a + imm) & ~1u;
        if (rd) x[rd] = v;
        cycles += 2;
        break;
    case 0x63: {
        int take;
        imm = ((insn >> 31) ? 0xfffff000u : 0) | ((insn << 4) & 0x800u) | ((insn >> 20) & 0x7e0u) | ((insn >> 7) & 0x1eu);
        switch (f3) {
        case 0: take = a == b; break;
        case 1: take = a != b; break;
        case 4: take = (int32_t)a < (int32_t)b; break;
        case 5: take = (int32_t)a >= (int32_t)b; break;
        case 6: take = a < b; break;
        case 7: take = a >= b; break;
        default: trap(2, insn); return;
        }
        if (take) { next = pc + imm; cycles += 1; }
        break;
    }
    case 0x03: {
        unsigned n = (f3 & 3) == 0 ? 1 : (f3 & 3) == 1 ? 2 : 4;
        if ((f3 & 3) == 3 || f3 == 6 || f3 == 7) { trap(2, insn); return; }
        imm = (uint32_t)((int32_t)insn >> 20);
        err = load(a + imm, n, &v);
        if (err) { trap(err, a + imm); return; }
        if (f3 == 0) v = (uint32_t)(int32_t)(int8_t)v;
        else if (f3 == 1) v = (uint32_t)(int32_t)(int16_t)v;
        if (rd) x[rd] = v;
        cycles += 1;
        break;
    }
    case 0x23: {
        unsigned n = f3 == 0 ? 1 : f3 == 1 ? 2 : 4;
        if (f3 > 2) { trap(2, insn); return; }
        imm = (uint32_t)(((int32_t)insn >> 25) << 5) | ((insn >> 7) & 31);
        err = store(a + imm, n, b);
        if (err) { trap(err, a + imm); return; }
        break;
    }
    case 0x13:
        imm = (uint32_t)((int32_t)insn >> 20);
        switch (f3) {
        case 0: v = a + imm; break;
        case 1: if (f7) { trap(2, insn); return; } v = a << (imm & 31); break;
        case 2: v = (int32_t)a < (int32_t)imm; break;
        case 3: v = a < imm; break;
        case 4: v = a ^ imm; break;
        case 5:
            if (f7 == 0x20) v = (uint32_t)((int32_t)a >> (imm & 31));
            else if (f7 == 0) v = a >> (imm & 31);
            else { trap(2, insn); return; }
            break;
        case 6: v = a | imm; break;
        default: v = a & imm; break;
        }
        if (rd) x[rd] = v;
        break;
    case 0x33:
        if (f7 == 1) {
            switch (f3) {
            case 0: v = a * b; break;
            case 1: v = (uint32_t)(((int64_t)(int32_t)a * (int64_t)(int32_t)b) >> 32); break;
            case 2: v = (uint32_t)(((int64_t)(int32_t)a * (int64_t)(uint64_t)b) >> 32); break;
            case 3: v = (uint32_t)(((uint64_t)a * (uint64_t)b) >> 32); break;
            default: trap(2, insn); return; /* DIV/REM: not in Zmmul */
            }
            cycles += 1;
        } else if (f7 == 0 || f7 == 0x20) {
            switch (f3 | (f7 == 0x20 ? 8 : 0)) {
            case 0: v = a + b; break;
            case 8: v = a - b; break;
            case 1: v = a << (b & 31); break;
            case 2: v = (int32_t)a < (int32_t)b; break;
            case 3: v = a < b; break;
            case 4: v = a ^ b; break;
            case 5: v = a >> (b & 31); break;
            case 13: v = (uint32_t)((int32_t)a >> (b & 31)); break;
            case 6: v = a | b; break;
            case 7: v = a & b; break;
            default: trap(2, insn); return;
            }
        } else { trap(2, insn); return; }
        if (rd) x[rd] = v;
        break;
    case 0x0f: cycles += f3 == 1 ? 40 : 2; break; /* FENCE / FENCE.I (cache maintenance) */
    case 0x73:
        if (f3 == 0) {
            if (insn == 0x30200073u) { next = csr_mepc; csr_mstatus = (csr_mstatus & ~8u) | ((csr_mstatus >> 4) & 8u) | 0x80u; }
            else if (insn == 0x00000073u) { trap(11, 0); return; }
            else if (insn == 0x00100073u) { trap(3, pc); return; }
            else if (insn == 0x10500073u) { /* wfi */ }
            else { trap(2, insn); return; }
        } else {
            uint32_t old, src = (f3 & 4) ? rs1 : a, nv;
            int write = 1;
            if (csr_access(insn >> 20, &old, 0, 0)) { trap(2, insn); return; }
            if ((f3 & 3) == 1) nv = src;
            else if ((f3 & 3) == 2) { nv = old | src; write = rs1 != 0; }
            else { nv = old & ~src; write = rs1 != 0; }
            if (write) csr_access(insn >> 20, &old, nv, 1);
            if (rd) x[rd] = old;
        }
        break;
    default:
        trap(2, insn);
        return;
    }
    pc = next;
}

/* ------------------------------------------------------------------ main */
static void load_hex32(const char *path, uint8_t *dst, size_t max_words)
{
    FILE *f = fopen(path, "r");
    char line[64];
    size_t i = 0;
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    while (fgets(line, sizeof line, f) && i < max_words) {
        uint32_t w = (uint32_t)strtoul(line, NULL, 16);
        memcpy(dst + 4 * i++, &w, 4);
    }
    fclose(f);
}

static void load_font(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[64];
    unsigned i = 0;
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    while (fgets(line, sizeof line, f) && i < 2048) font[i++] = (uint16_t)strtoul(line, NULL, 16);
    fclose(f);
}

int main(int argc, char **argv)
{
    const char *hex = NULL, *sd = NULL, *script_path = NULL, *font_path = NULL, *pal_path = NULL;
    int save_sd = 0;
    uint64_t max_ms = 600000;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--hex") && i + 1 < argc) hex = argv[++i];
        else if (!strcmp(argv[i], "--sd") && i + 1 < argc) sd = argv[++i];
        else if (!strcmp(argv[i], "--script") && i + 1 < argc) script_path = argv[++i];
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) frame_dir = argv[++i];
        else if (!strcmp(argv[i], "--frame-every") && i + 1 < argc) frame_every = (unsigned)atoi(argv[++i]);
        else if (!strcmp(argv[i], "--max-ms") && i + 1 < argc) max_ms = (uint64_t)_atoi64(argv[++i]);
        else if (!strcmp(argv[i], "--font") && i + 1 < argc) font_path = argv[++i];
        else if (!strcmp(argv[i], "--palette") && i + 1 < argc) pal_path = argv[++i];
        else if (!strcmp(argv[i], "--save-sd")) save_sd = 1;
        else if (!strcmp(argv[i], "--cpi") && i + 1 < argc) extra_cpi = (unsigned)atoi(argv[++i]) - 1;
        else { fprintf(stderr, "unknown argument %s\n", argv[i]); return 1; }
    }
    if (!hex || !sd || !font_path) { fprintf(stderr, "need --hex, --sd and --font\n"); return 1; }
    ram = malloc(RAM_BYTES);
    if (!ram) return 1;
    /* Block RAM starts from the bitstream image; DDR3 holds garbage at power-up. */
    memset(ram, 0, BRAM_BYTES);
    for (uint32_t i = BRAM_BYTES; i < RAM_BYTES; ++i) ram[i] = (uint8_t)(0xa5 ^ (i * 131u >> 7));
    load_hex32(hex, ram, BRAM_BYTES / 4);
    load_font(font_path);
    if (pal_path) {
        FILE *f = fopen(pal_path, "r");
        char line[64];
        unsigned i = 0;
        while (f && fgets(line, sizeof line, f) && i < 256) gpu_pal[i++] = (uint32_t)strtoul(line, NULL, 16);
        if (f) fclose(f);
    }
    {
        FILE *f = fopen(sd, "rb");
        long size;
        if (!f) { fprintf(stderr, "cannot open %s\n", sd); return 1; }
        fseek(f, 0, SEEK_END);
        size = ftell(f);
        fseek(f, 0, SEEK_SET);
        sd_sectors = (uint32_t)(size / 512);
        sd_image = malloc((size_t)size);
        if (!sd_image || fread(sd_image, 1, (size_t)size, f) != (size_t)size) { fprintf(stderr, "read %s failed\n", sd); return 1; }
        fclose(f);
    }
    if (script_path) load_script(script_path);
    limit_cycles = max_ms * (CPU_HZ / 1000);
    pc = 0x80018000u;
    while (!halted) {
        for (int k = 0; k < 4096 && !halted; ++k) step();
        run_script();
        if (cycles >= limit_cycles) { printf("\n[sim] time limit %llu ms reached\n", (unsigned long long)max_ms); break; }
    }
    printf("\n[sim] end: %llu ms simulated, %llu instructions, %llu GPU commands (%llu uploads), "
           "%u swaps, SD %llu reads %llu writes, pc=%08x\n",
           (unsigned long long)(cycles / (CPU_HZ / 1000)), (unsigned long long)instret,
           (unsigned long long)gpu_commands, (unsigned long long)gpu_uploads, gpu_swaps,
           (unsigned long long)sd_reads, (unsigned long long)sd_writes, pc);
    dump_frame("final");
    if (save_sd && sd_dirty) {
        FILE *f = fopen(sd, "wb");
        if (!f || fwrite(sd_image, 512, sd_sectors, f) != sd_sectors) { fprintf(stderr, "SD write-back failed\n"); return 1; }
        fclose(f);
        printf("[sim] SD image written back\n");
    }
    return exit_code;
}
