/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <stdio.h>
#include <stdlib.h>
#include "../touch.h"
#include "doomgeneric.h"
#include "doomstat.h"
#include "doom_port.h"
#include "../storage.h"
static uint64_t start_cycles;
static uint32_t last_sequence, last_sample_ms;
static int sample_seen;
static uint64_t cycles64(void)
{
    uint32_t hi,lo,again;
    do {hi=MTIME_HI;lo=MTIME_LO;again=MTIME_HI;} while(hi!=again);
    return (uint64_t)hi<<32|lo;
}
uint32_t doom_ticks_ms(void) { return (uint32_t)((cycles64()-start_cycles)*1000/CPU_CLOCK_HZ); }
void doom_poll_touch(void)
{
    touch_sample_t s=touch_read();
    uint32_t now=doom_ticks_ms();
    int valid=(s.status&TOUCH_READY) && !(s.status&TOUCH_FAULT);
    if (!sample_seen || s.sequence!=last_sequence) {
        last_sample_ms=now;last_sequence=s.sequence;sample_seen=1;
    }
    if ((uint32_t)(now-last_sample_ms)>200) valid=0;
    /* Legacy hardware publishes the first contact. The extended MMIO ABI
     * returns a magic ID and four more coherent contacts at 0x110..0x11c. */
    unsigned count=(s.status&TOUCH_DOWN)?1u:0u;
    uint32_t xy[5]={s.xy,0,0,0,0};
    uint8_t ids[5]={(uint8_t)(s.status>>8),0,0,0,0};
    const uint8_t *track_ids=ids;
    if (FN_TOUCH_READ_REG(0x124u)==0x54435035u) {
        count=(s.status>>4)&15u;
        for(unsigned i=1;i<5;++i)xy[i]=FN_TOUCH_READ_REG(0x10cu+4u*i);
        if (FN_TOUCH_READ_REG(0x12cu)==0x54494435u) {
            uint32_t packed=FN_TOUCH_READ_REG(0x120u);
            for(unsigned i=0;i<4;++i)ids[i]=(uint8_t)(packed>>(8u*i));
            ids[4]=(uint8_t)FN_TOUCH_READ_REG(0x128u);
        } else if(count>1) track_ids=NULL;
    }
    if (!!(s.status&TOUCH_DOWN) != !!count) valid=0;
    doom_input_context(menuactive ? DOOM_INPUT_MENU : automapactive ? DOOM_INPUT_MAP : DOOM_INPUT_GAME);
    doom_input_sample(now,valid,count,xy,track_ids);
}
void DG_Init(void)
{
    start_cycles=cycles64();doom_input_reset();doom_video_init();
    printf("DOOM_CLOCK_START absolute_ms=%llu\n",(unsigned long long)(start_cycles*1000/CPU_CLOCK_HZ));
}
void DG_DrawFrame(void)
{
    static unsigned frames;
    static unsigned old_menu=~0u, old_map=~0u, old_pause=~0u;
    static int old_sensitivity=-1;
    doom_poll_touch();doom_video_frame(DG_ScreenBuffer);
    if(old_menu != menuactive || old_map != automapactive || old_pause != paused || old_sensitivity != mouseSensitivity) {
        printf("DOOM_UI menu=%u map=%u paused=%u demo=%u sensitivity=%d\n", menuactive,automapactive,paused,demoplayback,mouseSensitivity);
        old_menu=menuactive;old_map=automapactive;old_pause=paused;old_sensitivity=mouseSensitivity;
    }
    ++frames;
    if(frames%35u==0 && gamestate==GS_LEVEL && players[0].mo)
        printf("DOOM_FRAME %u ms=%lu x=%ld y=%ld ammo=%d health=%d angle=%lu\n",frames,
               (unsigned long)doom_ticks_ms(),(long)players[0].mo->x,(long)players[0].mo->y,
               players[0].ammo[0],players[0].health,(unsigned long)players[0].mo->angle);
}
void DG_SleepMs(uint32_t ms)
{
    uint32_t begin=doom_ticks_ms();
    while((uint32_t)(doom_ticks_ms()-begin)<ms)doom_poll_touch();
}
uint32_t DG_GetTicksMs(void) { return doom_ticks_ms(); }
int DG_GetKey(int *pressed,unsigned char *key)
{
    doom_poll_touch();
    return doom_input_event(pressed,key);
}
int DG_GetMouseDelta(void)
{
    doom_poll_touch();
    int dx=doom_input_mouse_delta();
    return gamestate==GS_LEVEL && !menuactive && !paused && !demoplayback ? dx : 0;
}
void DG_SetWindowTitle(const char *title) { printf("DOOM: %s\n",title); }
void doom_platform_main(void)
{
    static char *argv[]={"doom","-iwad","DOOM1.WAD","-mb","12","-nosound","-nomouse",NULL};
    setvbuf(stdout,NULL,_IONBF,0);
    uart_puts("\nDoomGeneric RV32 DDR port\n");
    /* Exercise the high stack area within the CPU window, below GPU memory.
     * This address is 64 KiB below the initial SP, beyond startup call frames. */
    volatile uint32_t *probe=(volatile uint32_t *)(uintptr_t)0x83ef0000u;
    for(unsigned i=0;i<8;++i)probe[i]=0x51ac0000u^i;
    __asm__ volatile("fence rw,rw" ::: "memory");
    for(unsigned i=0;i<8;++i)if(probe[i]!=(0x51ac0000u^i)) {
        uart_puts("DOOM_STACK_DDR_FAIL\n");for(;;){}
    }
    printf("DOOM_STACK_DDR_PASS top=0x83f00000 cpu_hz=%lu ddr_status=%lu\n",
           (unsigned long)CPU_CLOCK_HZ,(unsigned long)DDR_STATUS);
    start_cycles=cycles64();doom_video_init();doom_message("DOOM: MOUNTING SD...");
    if(doom_storage_init()) { doom_message("GAMES/DOOM MISSING - PRESS RESET");for(;;){} }
    doomgeneric_Create(7,argv);
    for(;;)doomgeneric_Tick();
}
