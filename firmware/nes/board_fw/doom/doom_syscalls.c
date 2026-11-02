/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Read-only WAD files. Configuration and save writes fail explicitly in this
 * initial candidate. Neither FAT allocation nor existing game saves change. */
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/times.h>
#include "../soc.h"
#include "../pal/port/pal_fs.h"
#include "doom_port.h"
#undef errno
extern int errno;
typedef struct {int used;uint32_t position;pal_fs_file_t file;} doom_fd_t;
static doom_fd_t files[12];
static int ready;
int doom_storage_init(void) { ready=pal_fs_init(DOOM_GAME_DIR)==0;return ready?0:-1; }
int _open(const char *path,int flags,int mode)
{
    const char *name=path;int fd;
    (void)mode;
    if(!ready){errno=EIO;return -1;}
    if((flags&O_ACCMODE)!=O_RDONLY){errno=EROFS;return -1;}
    for(const char *p=path;*p;++p)if(*p=='/' || *p=='\\')name=p+1;
    for(fd=3;fd<12 && files[fd].used;++fd){}
    if(fd==12){errno=EMFILE;return -1;}
    if(pal_fs_open(&files[fd].file,name)){errno=ENOENT;return -1;}
    files[fd].used=1;files[fd].position=0;return fd;
}
int _close(int fd)
{
    if(fd<3 || fd>=12 || !files[fd].used){errno=EBADF;return -1;}
    files[fd].used=0;return 0;
}
int _read(int fd,void *buffer,int length)
{
    if(fd<3 || fd>=12 || !files[fd].used){errno=EBADF;return -1;}
    if(length<0){errno=EINVAL;return -1;}
    doom_fd_t *f=files+fd;
    uint32_t n=f->file.file.size-f->position;
    if(n>(uint32_t)length)n=(uint32_t)length;
    if(pal_fs_read(&f->file,f->position,buffer,n)){errno=EIO;return -1;}
    f->position+=n;return (int)n;
}
int _write(int fd,const void *buffer,int length)
{
    if(length<0){errno=EINVAL;return -1;}
    if(fd!=1 && fd!=2){errno=EROFS;return -1;}
    const char *p=buffer;
    for(int i=0;i<length;++i){if(p[i]=='\n')uart_putc('\r');uart_putc(p[i]);}
    return length;
}
int _lseek(int fd,int offset,int whence)
{
    if(fd<3 || fd>=12 || !files[fd].used){errno=EBADF;return -1;}
    doom_fd_t *f=files+fd;
    int64_t base=whence==SEEK_SET?0:whence==SEEK_CUR?(int64_t)f->position:
                 whence==SEEK_END?(int64_t)f->file.file.size:-1;
    int64_t pos=base+offset;
    if(base<0 || pos<0 || pos>f->file.file.size){errno=EINVAL;return -1;}
    f->position=(uint32_t)pos;return (int)pos;
}
int _fstat(int fd,struct stat *st)
{
    memset(st,0,sizeof *st);
    if(fd>=0 && fd<3){st->st_mode=S_IFCHR;return 0;}
    if(fd<3 || fd>=12 || !files[fd].used){errno=EBADF;return -1;}
    st->st_mode=S_IFREG;st->st_size=files[fd].file.file.size;st->st_blksize=4096;return 0;
}
int _stat(const char *path,struct stat *st)
{
    int fd=_open(path,O_RDONLY,0);if(fd<0)return -1;
    int r=_fstat(fd,st);_close(fd);return r;
}
int _isatty(int fd){return fd>=0 && fd<3;}
extern char __heap_start[],__heap_end[];
static char *heap_top=__heap_start;
void *_sbrk(ptrdiff_t increment)
{
    if(increment<0 || increment>__heap_end-heap_top){errno=ENOMEM;return (void *)-1;}
    char *old=heap_top;heap_top+=increment;return old;
}
int _gettimeofday(struct timeval *tv,void *tz)
{
    (void)tz;uint32_t ms=doom_ticks_ms();tv->tv_sec=ms/1000;tv->tv_usec=(ms%1000)*1000;return 0;
}
clock_t _times(struct tms *t)
{
    clock_t c=(clock_t)doom_ticks_ms();t->tms_utime=c;t->tms_stime=t->tms_cutime=t->tms_cstime=0;return c;
}
void _exit(int code)
{
    uart_puts("DOOM exit ");uart_putu((uint32_t)code);uart_puts("\n");
    doom_message("GAME ENDED - PRESS RESET");for(;;){}
}
int _kill(int pid,int sig){(void)pid;(void)sig;errno=EINVAL;return -1;}
int _getpid(void){return 1;}
int _unlink(const char *path){(void)path;errno=EROFS;return -1;}
int _link(const char *a,const char *b){(void)a;(void)b;errno=EROFS;return -1;}
int _mkdir(const char *path,int mode){(void)path;(void)mode;errno=EROFS;return -1;}
int mkdir(const char *path,mode_t mode){return _mkdir(path,(int)mode);}
