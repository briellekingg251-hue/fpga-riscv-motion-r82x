/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "pal_fs.h"

#define CACHE_LINES 8192u /* 4 MiB of DDR */

static uint32_t game_directory;
static uint32_t cache_tag[CACHE_LINES];
static uint8_t cache_data[CACHE_LINES][512] __attribute__((aligned(64)));
static uint32_t cache_hits, cache_misses;

static void copy_bytes(uint8_t *dst, const uint8_t *src, uint32_t n)
{
    if ((((uintptr_t)dst | (uintptr_t)src) & 3u) == 0) {
        uint32_t *d = (uint32_t *)dst;
        const uint32_t *s = (const uint32_t *)src;
        for (; n >= 16; n -= 16, d += 4, s += 4) { d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3]; }
        for (; n >= 4; n -= 4) *d++ = *s++;
        dst = (uint8_t *)d;
        src = (const uint8_t *)s;
    }
    while (n--) *dst++ = *src++;
}

int pal_fs_short_name(const char *name, char out[11])
{
    unsigned base = 0, ext = 0;
    int dot = 0;
    for (unsigned i = 0; i < 11; ++i) out[i] = ' ';
    for (unsigned i = 0; name[i]; ++i) {
        unsigned c = (unsigned char)name[i];
        if (c >= 'a' && c <= 'z') c -= 32;
        if (c == '.') { if (dot || !base) return -1; dot = 1; continue; }
        if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) return -1;
        if (dot) { if (ext == 3) return -1; out[8 + ext++] = (char)c; }
        else { if (base == 8) return -1; out[base++] = (char)c; }
    }
    return base && (!dot || ext) ? 0 : -1;
}

int pal_fs_init(const char *directory)
{
    sd_file_t games, dir;
    char name[11];
    for (unsigned i = 0; i < CACHE_LINES; ++i) cache_tag[i] = 0xffffffffu;
    if (sd_init() || fat_mount()) return -1;
    if (fat_find(fat_root(), "GAMES      ", &games) || !(games.attr & 0x10)) return -1;
    if (pal_fs_short_name(directory, name) || fat_find(games.cluster, name, &dir) || !(dir.attr & 0x10)) return -1;
    game_directory = dir.cluster;
    return 0;
}

uint32_t pal_fs_directory(void) { return game_directory; }

int pal_fs_open(pal_fs_file_t *f, const char *name)
{
    char short_name[11];
    uint32_t sectors;
    if (pal_fs_short_name(name, short_name) || fat_find(game_directory, short_name, &f->file) ||
        (f->file.attr & 0x10))
        return -1;
    f->extents = 0;
    sectors = (f->file.size + 511u) / 512u;
    for (uint32_t s = 0; s < sectors; ++s) {
        uint32_t lba;
        pal_extent_t *last = f->extents ? &f->extent[f->extents - 1] : 0;
        if (fat_sector(&f->file, s, &lba)) return -1;
        if (last && last->lba + last->count == lba) { ++last->count; continue; }
        if (f->extents == PAL_FS_MAX_EXTENTS) return -1; /* too fragmented for this loader */
        f->extent[f->extents].first_sector = s;
        f->extent[f->extents].lba = lba;
        f->extent[f->extents].count = 1;
        ++f->extents;
    }
    return 0;
}

static int sector_lba(const pal_fs_file_t *f, uint32_t sector, uint32_t *lba)
{
    for (uint32_t i = 0; i < f->extents; ++i) {
        const pal_extent_t *e = &f->extent[i];
        if (sector >= e->first_sector && sector - e->first_sector < e->count) {
            *lba = e->lba + (sector - e->first_sector);
            return 0;
        }
    }
    return -1;
}

static const uint8_t *cached_sector(uint32_t lba)
{
    uint32_t line = lba & (CACHE_LINES - 1u);
    if (cache_tag[line] == lba) { ++cache_hits; return cache_data[line]; }
    ++cache_misses;
    cache_tag[line] = 0xffffffffu;
    if (sd_read_block(lba, cache_data[line])) return 0;
    cache_tag[line] = lba;
    return cache_data[line];
}

int pal_fs_read(const pal_fs_file_t *f, uint32_t offset, uint8_t *dst, uint32_t len)
{
    if (offset > f->file.size || len > f->file.size - offset) return -1;
    while (len) {
        uint32_t lba, within = offset & 511u, n = 512u - within;
        const uint8_t *sector;
        if (n > len) n = len;
        if (sector_lba(f, offset >> 9, &lba) || !(sector = cached_sector(lba))) return -1;
        copy_bytes(dst, sector + within, n);
        dst += n;
        offset += n;
        len -= n;
    }
    return 0;
}

void pal_fs_stats(uint32_t *hits, uint32_t *misses)
{
    *hits = cache_hits;
    *misses = cache_misses;
}
