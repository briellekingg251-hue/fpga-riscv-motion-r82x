/* SPDX-License-Identifier: GPL-3.0-or-later */
/* newlib system calls of the PAL image.
 *
 *  - stdout/stderr go to the UART.
 *  - Read-only files are the resources in GAMES/PAL (extent mapped, cached).
 *  - "<n>.rpg" (n = 1..5) is a save slot.  It is backed by two preallocated
 *    files SAVE<n>A.DAT / SAVE<n>B.DAT and committed with the A/B protocol of
 *    pal_sd.c (payload verified by read-back, header with sequence and CRC
 *    written last), so a power cut never destroys the previous save.
 *  - The heap is the DDR between the end of .bss and the stack.
 */
#include <errno.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/times.h>
#include "../../soc.h"
#include "../pal_sd.h"
#include "pal_fs.h"
#include "pal_port.h"

#undef errno
extern int errno;

enum { FD_FREE, FD_RESOURCE, FD_SAVE_READ, FD_SAVE_WRITE };
#define MAX_FILES 16

typedef struct {
    int kind;
    uint32_t position, size, capacity, slot;
    uint8_t *buffer;
    pal_fs_file_t resource;
} pal_fd_t;

static pal_fd_t files[MAX_FILES];
static int storage_ready;

int pal_port_storage_init(void)
{
    storage_ready = pal_fs_init(PAL_GAME_DIR) == 0;
    return storage_ready ? 0 : -1;
}

static const char *base_name(const char *path)
{
    const char *b = path;
    for (const char *p = path; *p; ++p)
        if (*p == '/' || *p == '\\') b = p + 1;
    return b;
}

/* "3.rpg" -> 3, anything else -> 0 */
static unsigned save_slot(const char *name)
{
    if (name[0] >= '1' && name[0] <= '0' + (int)PAL_SAVE_SLOTS && name[1] == '.' &&
        (name[2] | 32) == 'r' && (name[3] | 32) == 'p' && (name[4] | 32) == 'g' && !name[5])
        return (unsigned)(name[0] - '0');
    return 0;
}

static int save_pair(unsigned slot, sd_file_t pair[2])
{
    char name[11];
    for (unsigned i = 0; i < 2; ++i) {
        memcpy(name, "SAVE    DAT", 11);
        name[4] = (char)('0' + slot);
        name[5] = i ? 'B' : 'A';
        if (fat_find(pal_fs_directory(), name, &pair[i]) || (pair[i].attr & 0x10) || pair[i].size < 1024)
            return -1;
    }
    return 0;
}

static int alloc_fd(void)
{
    for (int i = 3; i < MAX_FILES; ++i)
        if (files[i].kind == FD_FREE) { memset(&files[i], 0, sizeof files[i]); return i; }
    errno = EMFILE;
    return -1;
}

int _open(const char *path, int flags, int mode)
{
    const char *name = base_name(path);
    unsigned slot = save_slot(name);
    int fd, writing = (flags & O_ACCMODE) != O_RDONLY;
    (void)mode;
    if (!storage_ready) { errno = EIO; return -1; }
    if (slot) {
        sd_file_t pair[2];
        if (save_pair(slot, pair)) { errno = ENOENT; return -1; }
        if ((fd = alloc_fd()) < 0) return -1;
        files[fd].capacity = pair[0].size - 512u;
        if (pair[1].size - 512u < files[fd].capacity) files[fd].capacity = pair[1].size - 512u;
        files[fd].buffer = malloc(files[fd].capacity);
        files[fd].slot = slot;
        if (!files[fd].buffer) { errno = ENOMEM; return -1; }
        if (writing) {
            files[fd].kind = FD_SAVE_WRITE;
            return fd;
        }
        if (pal_save_load(pair, PAL_GAME_ID, slot, files[fd].buffer, files[fd].capacity, &files[fd].size)) {
            free(files[fd].buffer);
            errno = ENOENT;
            return -1;
        }
        files[fd].kind = FD_SAVE_READ;
        return fd;
    }
    if (writing) { errno = EACCES; return -1; } /* configuration writes are not supported */
    if ((fd = alloc_fd()) < 0) return -1;
    if (pal_fs_open(&files[fd].resource, name)) { errno = ENOENT; return -1; }
    files[fd].kind = FD_RESOURCE;
    files[fd].size = files[fd].resource.file.size;
    return fd;
}

int _close(int fd)
{
    int result = 0;
    if (fd < 3 || fd >= MAX_FILES || files[fd].kind == FD_FREE) { errno = EBADF; return -1; }
    if (files[fd].kind == FD_SAVE_WRITE) {
        sd_file_t pair[2];
        if (!files[fd].size || save_pair(files[fd].slot, pair) ||
            pal_save_commit(pair, PAL_GAME_ID, files[fd].slot, files[fd].buffer, files[fd].size)) {
            uart_puts("PAL save commit FAILED slot ");
            result = -1;
            errno = EIO;
        } else uart_puts("PAL save committed slot ");
        uart_putu(files[fd].slot);
        uart_puts(" bytes ");
        uart_putu(files[fd].size);
        uart_puts("\n");
    }
    if (files[fd].buffer) free(files[fd].buffer);
    files[fd].kind = FD_FREE;
    return result;
}

int _read(int fd, void *buffer, int length)
{
    pal_fd_t *f;
    uint32_t n;
    if (fd < 3 || fd >= MAX_FILES || files[fd].kind == FD_FREE || files[fd].kind == FD_SAVE_WRITE) {
        errno = EBADF;
        return -1;
    }
    f = &files[fd];
    if (length <= 0 || f->position >= f->size) return 0;
    n = f->size - f->position;
    if (n > (uint32_t)length) n = (uint32_t)length;
    if (f->kind == FD_RESOURCE) {
        if (pal_fs_read(&f->resource, f->position, buffer, n)) { errno = EIO; return -1; }
    } else memcpy(buffer, f->buffer + f->position, n);
    f->position += n;
    return (int)n;
}

int _write(int fd, const void *buffer, int length)
{
    const char *p = buffer;
    if (fd == 1 || fd == 2) {
        for (int i = 0; i < length; ++i) {
            if (p[i] == '\n') uart_putc('\r');
            uart_putc(p[i]);
        }
        return length;
    }
    if (fd < 3 || fd >= MAX_FILES || files[fd].kind != FD_SAVE_WRITE) { errno = EBADF; return -1; }
    if (length < 0 || files[fd].position + (uint32_t)length > files[fd].capacity) { errno = ENOSPC; return -1; }
    memcpy(files[fd].buffer + files[fd].position, buffer, (size_t)length);
    files[fd].position += (uint32_t)length;
    if (files[fd].position > files[fd].size) files[fd].size = files[fd].position;
    return length;
}

int _lseek(int fd, int offset, int whence)
{
    int64_t base, pos;
    if (fd < 3 || fd >= MAX_FILES || files[fd].kind == FD_FREE) { errno = EBADF; return -1; }
    base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? (int64_t)files[fd].position :
           whence == SEEK_END ? (int64_t)files[fd].size : -1;
    pos = base + offset;
    if (base < 0 || pos < 0 || pos > (int64_t)(files[fd].kind == FD_SAVE_WRITE ? files[fd].capacity : files[fd].size)) {
        errno = EINVAL;
        return -1;
    }
    files[fd].position = (uint32_t)pos;
    return (int)pos;
}

int _fstat(int fd, struct stat *st)
{
    memset(st, 0, sizeof *st);
    if (fd >= 0 && fd < 3) { st->st_mode = S_IFCHR; return 0; }
    if (fd >= MAX_FILES || files[fd].kind == FD_FREE) { errno = EBADF; return -1; }
    st->st_mode = S_IFREG;
    st->st_size = files[fd].size;
    st->st_blksize = 4096;
    return 0;
}

int _stat(const char *path, struct stat *st)
{
    int fd = _open(path, O_RDONLY, 0);
    if (fd < 0) return -1;
    _fstat(fd, st);
    _close(fd);
    return 0;
}

int _isatty(int fd) { return fd >= 0 && fd < 3; }

extern char __heap_start[], __heap_end[];
static char *heap_top = __heap_start;

void *_sbrk(ptrdiff_t increment)
{
    char *previous = heap_top;
    if (increment < 0 || __heap_end - heap_top < increment) { errno = ENOMEM; return (void *)-1; }
    heap_top += increment;
    return previous;
}

uint32_t pal_port_heap_used(void) { return (uint32_t)(heap_top - __heap_start); }

static uint64_t cycles64(void)
{
    uint32_t hi, lo, again;
    do { hi = MTIME_HI; lo = MTIME_LO; again = MTIME_HI; } while (hi != again);
    return (uint64_t)hi << 32 | lo;
}

int _gettimeofday(struct timeval *tv, void *tz)
{
    uint64_t us = cycles64() * 1000u / (CPU_CLOCK_HZ / 1000u);  /* exact for non-integer MHz */
    (void)tz;
    tv->tv_sec = (time_t)(us / 1000000u);
    tv->tv_usec = (suseconds_t)(us % 1000000u);
    return 0;
}

clock_t _times(struct tms *t)
{
    clock_t c = (clock_t)(cycles64() / (CPU_CLOCK_HZ / 1000u));
    t->tms_utime = c;
    t->tms_stime = t->tms_cutime = t->tms_cstime = 0;
    return c;
}

void _exit(int code)
{
    uart_puts("PAL exit ");
    uart_putu((uint32_t)code);
    uart_puts("\n");
    pal_port_message("GAME ENDED", "PRESS RESET TO RETURN TO MENU");
    for (;;) { }
}

int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void) { return 1; }
int _unlink(const char *path) { (void)path; errno = EACCES; return -1; }
int _link(const char *a, const char *b) { (void)a; (void)b; errno = EACCES; return -1; }
