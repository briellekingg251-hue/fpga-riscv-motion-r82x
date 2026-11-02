/* Standalone SD application. Recognition keeps the production confidence,
 * identity and freshness gates. LCD shows status/exit; HDMI owns the camera. */
#include "soc.h"
#include "gpu.h"
#include "touch.h"
#include "storage.h"
#include "control_boot.h"
#include "pose_input.h"
#include "game_pose_service.h"

#define PREG(o) MMIO32(0x10008000u+(o))
static uint32_t rates[3],last_counts[3],rate_mark,last_hud=0xffffffffu;
static void decimal(char *dst,uint32_t v) {
    dst[0]=(char)('0'+v/10u%10u);dst[1]=(char)('0'+v%10u);dst[2]=0;
}
static void status_screen(int tracking) {
    char digits[3];
    gpu_palette(240,0x101828);gpu_palette(241,0xffffff);
    gpu_palette(242,0x38d8ff);gpu_palette(243,0xff9b2f);
    gpu_clear(240);
    gpu_text(24,26,"POSE VIEW",241,3);
    gpu_text(24,66,"HDMI: CAMERA 1280 X 720",242,1);
    const char *names[3]={"CAM","DET","POSE"};
    for(unsigned i=0;i<3;i++) {
        gpu_text(24,108+(int)i*26,names[i],241,1);
        decimal(digits,rates[i]);gpu_text(152,108+(int)i*26,digits,242,1);
        gpu_text(188,108+(int)i*26,"FPS",241,1);
    }
    gpu_text(24,196,tracking?"TRACK: ON":"TRACK: OFF",tracking?242:243,1);
    gpu_rect(328,234,168,50,243);gpu_text(356,250,"EXIT",241,2);
    gpu_swap();
}
int main(void) {
    control_boot_t boot;
    uint32_t epoch=1;
    if(control_boot_read((const volatile control_boot_t *)(uintptr_t)CONTROL_BOOT_ADDR,
                         CONTROL_GAME_VIEW,&boot))epoch=boot.session_epoch;
    pose_input_config_t cfg;pose_input_defaults(&cfg);
    if(!pose_input_configure(&cfg,CONTROL_GAME_FRUIT))storage_jump(LOADER_ENTRY_ADDR);
    control_reset(epoch);game_pose_start(epoch,CONTROL_GAME_FRUIT);
    PREG(0x058)=0;PREG(0x0a0)=0;PREG(0x05c)=1;
    rate_mark=game_pose_now();
    last_counts[0]=PREG(0x004);last_counts[1]=PREG(0x008);last_counts[2]=PREG(0x010);
    status_screen(0);
    uint32_t sequence=0,screen_mark=rate_mark;
    int have_sequence=0,armed=0,leaving=0;
    for(;;) {
        game_pose_step();game_pose_debug();
        uint32_t now=game_pose_now();
        pose_input_tick(now);
        control_frame_t events;(void)control_poll(&events); /* drain each publication */
        control_pose_snapshot_t snapshot;
        int tracking=pose_input_view(&snapshot,now,180u);
        uint32_t elapsed=now-rate_mark;
        if(elapsed>=1000u) {
            const unsigned off[3]={0x004,0x008,0x010};
            for(unsigned i=0;i<3;i++) {
                uint32_t count=PREG(off[i]);
                uint64_t fps=(uint64_t)(count-last_counts[i])*1000u/elapsed;
                rates[i]=(uint32_t)(fps>99u?99u:fps);last_counts[i]=count;
            }
            rate_mark=now;
        }
        uint32_t hud=rates[0]|rates[1]<<8|rates[2]<<16|(uint32_t)tracking<<24;
        if(hud!=last_hud){PREG(0x0a0)=hud;last_hud=hud;}
        if(now-screen_mark>=1000u){status_screen(tracking);screen_mark=now;}
        touch_sample_t t=touch_read();
        if((t.status&(TOUCH_READY|TOUCH_FAULT))==TOUCH_READY &&
           (!have_sequence || t.sequence!=sequence)) {
            have_sequence=1;sequence=t.sequence;
            if(!(t.status&TOUCH_DOWN))armed=1;
            else if(armed) {
                int x,y;armed=0;
                if(touch_map(t.xy,&x,&y)&&x>=328&&x<496&&y>=234&&y<284)leaving=1;
            }
        }
        if(leaving) {
            PREG(0x05c)=0;PREG(0x0a0)=0;
            if(game_pose_stop_step())storage_jump(LOADER_ENTRY_ADDR);
        }
    }
}
