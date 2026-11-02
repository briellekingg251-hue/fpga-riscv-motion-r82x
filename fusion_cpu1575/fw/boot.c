/* Menu/UI code is not speed critical: size-optimise this unit only so the
 * richer menu fits the 0x18000..0x20000 loader window; drivers stay -O2. */
#pragma GCC optimize("Os")
#include "soc.h"
#include "gpu.h"
#include "touch.h"
#include "storage.h"
#include "control_menu.h"
#include "loader_ui.h"
static uint8_t chunk[512];
void uartlink_listen(void);
void uartlink_poll(uint32_t capacity);
void uartlink_release(void);
int uartlink_active(void);
static uint32_t game_dir[8];
static char names[8][9];
#ifndef PLATFORM_BOOT_INFO
#define PLATFORM_BOOT_INFO ((volatile boot_info_t *)BOOT_INFO_ADDR)
#endif
static uint32_t selected_mode,session_epoch;
#ifndef PLATFORM_CONTROL_BOOT
#define PLATFORM_CONTROL_BOOT ((volatile control_boot_t *)CONTROL_BOOT_ADDR)
#endif
#ifndef PLATFORM_DDR_RAM
#define PLATFORM_DDR_RAM(address) ((volatile uint8_t *)(uintptr_t)(address))
#endif
static void clear_handoff(void){
    PLATFORM_BOOT_INFO->magic=0;
    volatile control_boot_t *b=PLATFORM_CONTROL_BOOT;
    b->magic=0;b->version=b->size=b->mode=b->capabilities=b->game_id=b->checksum=0;
    b->session_epoch=0;
    for(unsigned i=0;i<8;i++)b->reserved[i]=0;
    if(++session_epoch==0)session_epoch=1;
}
static void publish_mode(uint32_t game_id){
    control_boot_t b={CONTROL_BOOT_MAGIC,CONTROL_BOOT_VERSION,CONTROL_BOOT_SIZE,
                      selected_mode,control_game_caps(game_id),session_epoch,game_id,{0},0};
    b.checksum=control_boot_checksum(&b);
    volatile control_boot_t *p=PLATFORM_CONTROL_BOOT;
    p->magic=0;p->version=b.version;p->size=b.size;p->mode=b.mode;
    p->capabilities=b.capabilities;p->session_epoch=b.session_epoch;p->game_id=b.game_id;
    for(unsigned i=0;i<8;i++)p->reserved[i]=0;
    p->checksum=b.checksum;p->magic=b.magic;
}
static int manifest_allowed(uint32_t mode,uint32_t abi,uint32_t id){
    return control_game_allowed(mode,id) &&
           ((abi==1u && id==CONTROL_GAME_FRUIT) ||
            (abi==2u && id==CONTROL_GAME_SUBWAY) ||
            (abi==3u && id==CONTROL_GAME_PAL));
}
#ifndef PLATFORM_GAME_RAM
#define PLATFORM_GAME_RAM ((volatile uint8_t *)0x80000000u)
#endif
static uint32_t word(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void wait_gpu(void){while(!(GPU_REG_STATUS&4u));}
/* Loader text uses palette 255 (near-black in the default palette): make it
 * white. The full loader palette (224..254) is uploaded by the menu; load
 * screens rewrite only 255 so a game's palette upload count stays exact. */
static void loader_palette(void){gpu_palette(255,0xffffffu);}
#define BACKLIGHT MMIO32(0x10004f04u) /* LCD backlight PWM high time, percent */
/* Full redraw each time: both framebuffers always hold a complete screen.
 * bar<0 hides the progress bar, else 0..400 pixels. */
UI_FN void screen_draw(const char *message,int bar) {
    wait_gpu();loader_palette();ui_background();ui_header(BACKLIGHT);
    ui_card(36,100,440,100,UI_CYAN);
    gpu_rect(38,102,436,4,UI_CYAN_DK);
    ui_text_c(256,120,"SD GAME CONSOLE",UI_DIM,1);
    ui_text_c(256,146,message,UI_WHITE,1);
    if(bar>=0){gpu_rect(56,176,400,8,UI_PANEL_HI);gpu_rect(56,176,bar,8,UI_CYAN);}
    gpu_swap();wait_gpu();
}
static void screen(const char *message) {
    screen_draw(message,-1);
    uart_puts(message);uart_puts("\n");
}
/* Resource ABI 3: a large program executed from DDR3 (PAL).  Manifest words:
 * magic, abi=3, size, program crc, load address, entry, game id, crc.  The game
 * reads its own resources from its SD directory; no sprite/palette upload. */
static int ddr_ready(void){
    uint32_t t=MTIME_LO;
    while(!(DDR_STATUS&1u))if((uint32_t)(MTIME_LO-t)>CPU_CLOCK_HZ*2u)return 0;
    return 1;
}
static int load_ddr_game(unsigned selected) {
    sd_file_t manifest, program;
    uint32_t size,pcrc,load,entry,game_id,crc;
    volatile boot_info_t *info=PLATFORM_BOOT_INFO;
    if(fat_find(game_dir[selected],"MANIFESTBIN",&manifest) || fat_read(&manifest,0,chunk,32))return -1;
    size=word(chunk+8);pcrc=word(chunk+12);load=word(chunk+16);entry=word(chunk+20);game_id=word(chunk+24);
    if(!manifest_allowed(selected_mode,3u,game_id) || word(chunk)!=0x53444731u || word(chunk+4)!=3u ||
       word(chunk+28)!=~storage_crc(0xffffffffu,chunk,28) || !size || (load&63u) ||
       load<DDR_GAME_MIN || load>DDR_GAME_MAX || size>DDR_GAME_MAX-load ||
       entry<load || entry-load>=size || (entry&3u))return -1;
    if(fat_find(game_dir[selected],"GAME    BIN",&program) || program.size!=size || (program.attr&0x10))return -1;
    if(!ddr_ready()){screen("DDR3 NOT READY - CHECK BITSTREAM");return -1;}
    screen("LOADING GAME INTO DDR3...");
    crc=0xffffffffu;
    for(uint32_t off=0;off<size;) {
        unsigned n=size-off>512?512:(unsigned)(size-off);
        if(fat_read(&program,off,chunk,n))return -1;
        crc=storage_crc(crc,chunk,n);
        volatile uint8_t *ram=PLATFORM_DDR_RAM(load+off);
        for(unsigned i=0;i<n;i++)ram[i]=chunk[i];
        off+=n;
        if(!(off&0xffffu) || off==size)screen_draw("LOADING GAME INTO DDR3...",(int)(off/(size/400u+1u)));
    }
    if(~crc!=pcrc)return -1;
    /* Read back through the cache hierarchy before trusting DDR3. */
    crc=0xffffffffu;
    for(uint32_t off=0;off<size;off+=512){
        unsigned n=size-off>512?512:(unsigned)(size-off);
        volatile uint8_t *ram=PLATFORM_DDR_RAM(load+off);
        for(unsigned i=0;i<n;i++)chunk[i]=ram[i];
        crc=storage_crc(crc,chunk,n);
    }
    if(~crc!=pcrc){screen("DDR3 READBACK MISMATCH");return -1;}
    wait_gpu();
    info->abi=3u;info->game_id=game_id;info->save_lba[0]=info->save_lba[1]=0;
    info->volume_start=fat_volume_start();info->volume_end=fat_volume_end();
    publish_mode(game_id);info->magic=BOOT_INFO_MAGIC;
    uartlink_release();
    storage_jump(entry);
}
static int load_game_impl(unsigned selected) {
    sd_file_t manifest, program, sprites, palette, save;
    uint32_t size,pcrc,scrc,palcrc,crc, lbas[2], resource_abi, sprite_base, sprite_size;
    volatile boot_info_t *info=PLATFORM_BOOT_INFO;
    info->magic=0;
    if(fat_find(game_dir[selected],"MANIFESTBIN",&manifest) || manifest.size!=32 ||
       fat_read(&manifest,0,chunk,32) || word(chunk)!=0x53444731u)return -1;
    resource_abi=word(chunk+4);
    if(resource_abi==3u)return load_ddr_game(selected);
    if(resource_abi==1u){sprite_base=4096u;sprite_size=18u*4096u;}
    else if(resource_abi==2u){sprite_base=0;sprite_size=64u*4096u;}
    else return -1;
    size=word(chunk+8);pcrc=word(chunk+12);scrc=word(chunk+16);palcrc=word(chunk+20);
    uint32_t game_id=word(chunk+24);
    if(!manifest_allowed(selected_mode,resource_abi,game_id) ||
       word(chunk+28)!=~storage_crc(0xffffffffu,chunk,28) || !size || size>GAME_RAM_LIMIT-8192u)return -1;
    if(fat_find(game_dir[selected],"GAME    BIN",&program) || program.size!=size || (program.attr&0x10) ||
       fat_find(game_dir[selected],"SPRITES BIN",&sprites) || sprites.size!=sprite_size || (sprites.attr&0x10) ||
       fat_find(game_dir[selected],"PALETTE BIN",&palette) || palette.size!=768 || (palette.attr&0x10) ||
       fat_find(game_dir[selected],"SAVE    DAT",&save) || save.size!=1024 || (save.attr&0x11) ||
       fat_sector(&save,0,&lbas[0]) || fat_sector(&save,1,&lbas[1]) || lbas[0]==lbas[1])return -1;
    screen("LOADING GAME...");
    crc=0xffffffffu;
    for(uint32_t off=0;off<size;) {
        unsigned n=size-off>512?512:(unsigned)(size-off);
        if(fat_read(&program,off,chunk,n))return -1;
        crc=storage_crc(crc,chunk,n);
        volatile uint8_t *ram=PLATFORM_GAME_RAM+off;
        for(unsigned i=0;i<n;i++)ram[i]=chunk[i];
        off+=n;
    }
    if(~crc!=pcrc)return -1;
    wait_gpu();crc=0xffffffffu;
    for(uint32_t off=0;off<sprites.size;off+=512) {
        if(fat_read(&sprites,off,chunk,512))return -1;
        crc=storage_crc(crc,chunk,512);
        for(unsigned i=0;i<512;i++)gpu_wr(26,((off+i+sprite_base)<<8)|chunk[i]);
    }
    if(~crc!=scrc)return -1;
    crc=0xffffffffu;
    /* 256 palette triples; read 384-byte chunks to keep RGB triplets intact. */
    for(unsigned off=0;off<768;off+=384) {
        if(fat_read(&palette,off,chunk,384))return -1;
        crc=storage_crc(crc,chunk,384);
        for(unsigned i=0;i<384;i+=3)gpu_palette((off+i)/3,(uint32_t)chunk[i]<<16|(uint32_t)chunk[i+1]<<8|chunk[i+2]);
    }
    if(~crc!=palcrc)return -1;
    wait_gpu();
    info->abi=GAME_ABI;info->game_id=game_id;info->save_lba[0]=lbas[0];info->save_lba[1]=lbas[1];
    info->volume_start=fat_volume_start();info->volume_end=fat_volume_end();
    publish_mode(game_id);info->magic=BOOT_INFO_MAGIC;
    /* Core implements FENCE.I with D-cache maintenance and I-cache invalidation. */
    uartlink_release();
    storage_jump(0x80000000u);
}
/* Every attempt starts a new epoch; failures cannot leave a usable handoff. */
static int load_game(unsigned selected){
    clear_handoff();
    if(selected>=CONTROL_MENU_MAX || load_game_impl(selected)){
        clear_handoff();return -1;
    }
    return -1; /* successful jump never returns */
}
static void wait_lift(uint32_t press_seq){
    for(;;){touch_sample_t s=touch_read();
        if((s.status&(TOUCH_READY|TOUCH_FAULT|TOUCH_DOWN))==TOUCH_READY &&
           s.sequence!=press_seq)return;}
}
UI_FN void mode_card(const control_menu_t *m,unsigned mode,int x,unsigned t){
    int pose=mode==CONTROL_POSE,cx=x+116;
    unsigned accent=pose?UI_ORANGE:UI_CYAN,dark=pose?UI_ORANGE_DK:UI_CYAN_DK;
    ui_card(x,62,232,170,accent);
    gpu_rect(x+2,64,228,96,dark);
    ui_dither(x+2,64,228,96,UI_PANEL);
    if(pose)ui_icon_pose(cx,112,t);else ui_icon_touch(cx,112,t);
    ui_text_sh(cx-ui_text_w(pose?"BODY POSE":"TOUCH",2)/2,162,pose?"BODY POSE":"TOUCH",UI_WHITE,2);
    ui_text_c(cx,192,pose?"CAMERA + AI SKELETON":"TAP AND SWIPE",accent,1);
    /* badges for installed packages this mode can run */
    unsigned visible[CONTROL_MENU_MAX],n=0;int w=0;
    for(unsigned i=0;i<m->count;i++)if(control_game_allowed(mode,m->ids[i]))visible[n++]=i;
    for(unsigned j=0;j<n && j<3;j++)w+=ui_text_w(names[visible[j]],1)+16;
    int bx=cx-w/2;
    for(unsigned j=0;j<n && j<3;j++){
        ui_pill(bx,210,names[visible[j]],dark,UI_WHITE);bx+=ui_text_w(names[visible[j]],1)+16;
    }
    if(!n)ui_text_c(cx,210,"NO GAME INSTALLED",UI_DIM,1);
}
UI_FN void footer_status(const control_menu_t *m){
    int ddr=(DDR_STATUS&1u)!=0;char txt[2];
    ui_circ(22,262,5,ddr?UI_GREEN:UI_YELLOW);
    gpu_text(32,254,ddr?"DDR3 READY":"DDR3 CALIBRATING",ddr?UI_GREEN:UI_YELLOW,1);
    txt[0]=(char)('0'+m->count%10);txt[1]=0;
    ui_circ(22,282,5,m->count?UI_CYAN:UI_RED);
    gpu_text(32,274,txt,UI_WHITE,1);gpu_text(44,274,"GAMES ON SD",UI_DIM,1);
    gpu_text(160,274,"RISC-V 162MHZ",UI_DIM,1);
}
UI_FN void draw_menu(const control_menu_t *m,unsigned t){
    wait_gpu();ui_palette();loader_palette();ui_background();ui_header(BACKLIGHT);
    if(m->stage==MENU_MODE){
        gpu_text(16,46,"SELECT CONTROL",UI_DIM,1);
        mode_card(m,CONTROL_TOUCH,16,t);mode_card(m,CONTROL_POSE,264,t);
        footer_status(m);
    }else if(m->stage==MENU_FAILED){
        ui_card(56,88,400,120,UI_RED);
        ui_circ(256,120,14,UI_RED);gpu_rect(254,110,4,12,UI_WHITE);gpu_rect(254,126,4,4,UI_WHITE);
        ui_text_c(256,146,"LOAD FAILED - TOUCH TO RETURN",UI_WHITE,1);
        ui_text_c(256,172,"CHECK THE GAME FILES ON THE SD CARD",UI_DIM,1);
    }else{
        int pose=m->mode==CONTROL_POSE;
        unsigned visible[CONTROL_MENU_MAX],n=control_menu_visible(m,visible);
        gpu_text(16,46,pose?"POSE GAMES":"TOUCH GAMES",pose?UI_ORANGE:UI_CYAN,1);
        for(unsigned j=0;j<4 && m->page*4+j<n;j++){
            unsigned g=visible[m->page*4+j];uint32_t id=m->ids[g];int y=62+(int)j*40;
            unsigned accent=ui_game_accent(id);
            ui_card(16,y,480,36,UI_PANEL_HI);
            gpu_rect(18,y+2,5,32,accent);
            ui_game_icon(id,46,y+18);
            ui_text_sh(70,y+2,ui_game_title(id,names[g]),UI_WHITE,2);
            int bx=478;
            if(control_game_allowed(CONTROL_POSE,id)){bx-=ui_text_w("POSE",1)+16;ui_pill(bx,y+10,"POSE",UI_ORANGE_DK,UI_ORANGE);}
            bx-=ui_text_w("TOUCH",1)+16;ui_pill(bx,y+10,"TOUCH",UI_CYAN_DK,UI_CYAN);
        }
        if(!n)ui_text_c(256,120,"NO COMPATIBLE GAME",UI_DIM,1);
        ui_text_c(256,224,pose?"TAP A GAME, THEN STAND 2M FROM THE CAMERA":
                               "TAP A GAME TO START",UI_DIM,1);
        if(n>4)ui_button(10,248,120,40,"NEXT PAGE",UI_PANEL_HI,UI_WHITE);
        ui_button(144,248,142,40,"< MODE",pose?UI_ORANGE:UI_CYAN,UI_WHITE);
    }
    ui_button(304,248,196,40,"PC INSTALL",UI_PANEL_HI,UI_DIM);
    gpu_swap();wait_gpu();
}
int main(void) {
    sd_file_t games,e;char n[12];
    /* Explicit field reset (no memset in the loader runtime). */
    static control_menu_t menu;
    menu.count=menu.stage=menu.mode=menu.page=menu.armed=0;
    menu.sequence=0;menu.have_sequence=0;
    /* BSS restarts on return. Retain only a validated last epoch, no events. */
    volatile control_boot_t *old=PLATFORM_CONTROL_BOOT;
    control_boot_t prior;
    prior.magic=old->magic;prior.version=old->version;prior.size=old->size;prior.mode=old->mode;
    prior.capabilities=old->capabilities;prior.session_epoch=old->session_epoch;prior.game_id=old->game_id;
    for(unsigned i=0;i<8;i++)prior.reserved[i]=old->reserved[i];
    prior.checksum=old->checksum;
    session_epoch=control_boot_valid(&prior,prior.game_id)?prior.session_epoch:0;
    clear_handoff();selected_mode=CONTROL_TOUCH;
    ui_palette();
    screen("INITIALIZING SD...");
    if(sd_init()){screen("SD INITIALIZATION FAILED - RESET");for(;;);}
    uint32_t capacity=0;
    if(sd_capacity(&capacity)){screen("SD CAPACITY FAILED - RESET");for(;;);}
    uart_puts("SD INIT OK capacity sectors ");uart_putu(capacity);uart_puts("\n");
    if(fat_mount()){screen("PC INSTALL: UDP 8081 / RESET WHEN DONE");cardlink_run();}
    if(fat_find(fat_root(),"GAMES      ",&games) || !(games.attr&0x10)){screen("PC INSTALL: UDP 8081 / RESET WHEN DONE");cardlink_run();}
    for(unsigned i=0;i<4096 && menu.count<CONTROL_MENU_MAX;i++) {
        int r=fat_dir_entry(games.cluster,i,n,&e);
        if(r==1)break;
        if(r<0){screen("DIRECTORY READ ERROR");for(;;);}
        if(r==2 || !(e.attr&0x10) || n[0]=='.')continue;
        sd_file_t m;
        if(fat_find(e.cluster,"MANIFESTBIN",&m) || m.size!=32 || (m.attr&0x10) ||
           fat_read(&m,0,chunk,32) || word(chunk)!=0x53444731u ||
           word(chunk+28)!=~storage_crc(0xffffffffu,chunk,28) ||
           !manifest_allowed(CONTROL_TOUCH,word(chunk+4),word(chunk+24)))continue;
        unsigned c=menu.count++;game_dir[c]=e.cluster;menu.ids[c]=word(chunk+24);
        unsigned k=0;for(;k<8 && n[k]!=' ';k++)names[c][k]=n[k];names[c][k]=0;
    }
    for(;;) {
        uint32_t anim=gpu_frame();
        draw_menu(&menu,anim/4u);uartlink_listen();
        for(;;){
            uartlink_poll(capacity);
            /* Idle animation of the mode cards (15 Hz); never while a PC
             * install session owns the UART or between menu transitions. */
            if(menu.stage==MENU_MODE && !uartlink_active() && ((gpu_frame()-anim)&0xffffu)>=4u){
                anim=gpu_frame();draw_menu(&menu,anim/4u);
            }
            touch_sample_t s=touch_read();int x=0,y=0;
            int down=(s.status&TOUCH_DOWN)!=0;
            int healthy=(s.status&(TOUCH_READY|TOUCH_FAULT))==TOUCH_READY &&
                        (!down || touch_map(s.xy,&x,&y));
            unsigned selected=0,stage=menu.stage,mode=menu.mode;
            int action=control_menu_touch(&menu,s.sequence,healthy,down,x,y,&selected);
            if(action==MENU_NONE)continue;
            if(action==MENU_LIGHT){
                unsigned v=BACKLIGHT;
                if(x<330 && v>=10)v-=10;else if(x>=460 && v<=90)v+=10;
                BACKLIGHT=v;break;
            }
            if(action==MENU_INSTALL){clear_handoff();screen("PC INSTALL: UDP 8081 / RESET WHEN DONE");cardlink_run();}
            if(action==MENU_REDRAW){
                if(stage!=menu.stage || mode!=menu.mode){clear_handoff();selected_mode=menu.mode;}
                break;
            }
            if(action==MENU_LOAD){
                /* Consume selection and wait for healthy physical release before
                 * entering a game; UI press cannot leak into first game frame. */
                wait_lift(s.sequence);selected_mode=menu.mode;
                if(load_game(selected)){menu.stage=MENU_FAILED;menu.armed=0;}
                break;
            }
        }
    }
}
