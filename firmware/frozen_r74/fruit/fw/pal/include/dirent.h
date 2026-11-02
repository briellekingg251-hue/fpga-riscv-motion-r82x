/* SPDX-License-Identifier: GPL-3.0-or-later
 * Bare-metal directory API declarations. Implementation must enumerate FAT32;
 * this header alone does not provide a filesystem backend. */
#ifndef FPGA_PAL_DIRENT_H
#define FPGA_PAL_DIRENT_H
typedef struct pal_directory DIR;
struct dirent {char d_name[256];};
DIR *opendir(const char *path);
struct dirent *readdir(DIR *directory);
int closedir(DIR *directory);
#endif
