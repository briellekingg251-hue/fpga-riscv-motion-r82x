/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef FPGA_PAL_SD_H
#define FPGA_PAL_SD_H
#include "../storage.h"
typedef struct {sd_file_t file;uint32_t position;} pal_file_t;
int pal_file_open(pal_file_t *file,uint32_t directory,const char *name);
int pal_file_seek(pal_file_t *file,int32_t offset,int origin);
/* fread-style bytes read, or -1 on media/filesystem error. */
int pal_file_read(pal_file_t *file,uint8_t *data,uint32_t length);
/* Pair consists of preallocated FAT32 files; no directory/FAT mutation.
 * Header sector is committed only after every payload sector is verified. */
int pal_save_load(const sd_file_t pair[2],uint32_t game_id,uint32_t slot,
                  uint8_t *data,uint32_t capacity,uint32_t *length);
int pal_save_commit(const sd_file_t pair[2],uint32_t game_id,uint32_t slot,
                    const uint8_t *data,uint32_t length);
#endif
