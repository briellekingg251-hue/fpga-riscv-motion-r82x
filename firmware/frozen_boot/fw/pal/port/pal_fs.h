/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Read-only FAT32 file access for the PAL resource directory.
 *
 * Files are opened inside one directory (GAMES/PAL).  At open time the
 * cluster chain is walked once into extents of consecutive sectors, so random
 * MKF chunk seeks never re-walk the FAT.  Sector reads go through a
 * direct-mapped DDR sector cache.  Nothing here writes to the card.
 */
#ifndef FPGA_PAL_FS_H
#define FPGA_PAL_FS_H
#include <stdint.h>
#include "../../storage.h"

#define PAL_FS_MAX_EXTENTS 48

typedef struct {
    uint32_t first_sector; /* file sector index of the extent start */
    uint32_t lba;
    uint32_t count;
} pal_extent_t;

typedef struct {
    sd_file_t file;
    uint32_t extents;
    pal_extent_t extent[PAL_FS_MAX_EXTENTS];
} pal_fs_file_t;

/* Mount the card and locate GAMES/<directory>.  Returns 0 on success. */
int pal_fs_init(const char *directory);
uint32_t pal_fs_directory(void);
/* Case-insensitive 8.3 name, no path.  Returns 0, or -1 when missing/invalid. */
int pal_fs_open(pal_fs_file_t *f, const char *name);
/* Copy len bytes at offset (bounds are checked by the caller). */
int pal_fs_read(const pal_fs_file_t *f, uint32_t offset, uint8_t *dst, uint32_t len);
/* Convert "name.ext" into a FAT 11-character directory name. */
int pal_fs_short_name(const char *name, char out[11]);
void pal_fs_stats(uint32_t *hits, uint32_t *misses);
#endif
