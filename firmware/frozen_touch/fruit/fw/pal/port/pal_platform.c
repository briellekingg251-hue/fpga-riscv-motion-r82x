/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Board entry, miniSDL general/timer/audio/file glue and the platform
 * functions SDLPAL expects from its OS layer (unix.cpp is not built). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL.h>
#include "../pal_sdl_backend.h"
#include "pal_port.h"

typedef int BOOL;
typedef unsigned int DWORD;
typedef const char *LPCSTR;

int main(int argc, char *argv[]);
uint32_t pal_port_heap_used(void);

void pal_platform_main(void)
{
    static char *argv[] = {"sdlpal", NULL};
    uart_puts("\nPAL-Navy RV32 port: DDR image started\n");
    pal_video_init();
    pal_port_message("PAL: MOUNTING SD CARD...", NULL);
    if (pal_port_storage_init()) {
        uart_puts("PAL: SD card / GAMES/PAL not found\n");
        pal_port_message("PAL: SD CARD OR GAMES/PAL NOT FOUND", "PRESS RESET");
        for (;;) { }
    }
    pal_port_message("PAL: LOADING GAME DATA...", NULL);
    exit(main(1, argv));
}

/* ------------------------------------------------------------ SDL general */
int SDL_Init(uint32_t flags)
{
    (void)flags;
    pal_sdl_events_reset();
    pal_sdl_timer_reset();
    return 0;
}

void SDL_Quit(void) { }
char *SDL_GetError(void) { return (char *)pal_sdl_events_error(); }
int SDL_SetError(const char *fmt, ...) { (void)fmt; return -1; }
int SDL_ShowCursor(int toggle) { (void)toggle; return 0; }

void SDL_WM_SetCaption(const char *title, const char *icon)
{
    (void)icon;
    uart_puts("PAL: ");
    uart_puts(title);
    uart_puts(" heap=");
    uart_putu(pal_port_heap_used());
    uart_puts("\n");
}

SDL_TimerID SDL_AddTimer(uint32_t interval, SDL_NewTimerCallback callback, void *param)
{
    (void)interval; (void)callback; (void)param;
    return NULL;
}

int SDL_RemoveTimer(SDL_TimerID id) { (void)id; return 1; }

/* ------------------------------------------------------------ audio: none */
int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained) { (void)desired; (void)obtained; return -1; }
void SDL_CloseAudio(void) { }
void SDL_PauseAudio(int pause_on) { (void)pause_on; }
void SDL_LockAudio(void) { }
void SDL_UnlockAudio(void) { }

/* ------------------------------------------------------------ RWops: none */
SDL_RWops *SDL_RWFromFile(const char *filename, const char *mode) { (void)filename; (void)mode; return NULL; }
SDL_RWops *SDL_RWFromMem(void *mem, int size) { (void)mem; (void)size; return NULL; }

/* ------------------------------------------------------------ SDLPAL OS layer */
BOOL UTIL_GetScreenSize(DWORD *width, DWORD *height)
{
    if (!width || !height) return 0;
    *width = 320;
    *height = 200;
    return 1;
}

BOOL UTIL_IsAbsolutePath(LPCSTR name) { return name && *name == '/'; }
int UTIL_Platform_Startup(int argc, char *argv[]) { (void)argc; (void)argv; return 0; }
int UTIL_Platform_Init(int argc, char *argv[]) { (void)argc; (void)argv; return 0; }
void UTIL_Platform_Quit(void) { }
