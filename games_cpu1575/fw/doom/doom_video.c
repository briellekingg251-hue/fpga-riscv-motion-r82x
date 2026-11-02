/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <string.h>
#include "../gpu.h"
#include "doom_port.h"
#include "doomkeys.h"
/* 320x200 indexed game -> 480x300 GPU -> 960x600 panel, centred horizontally.
 * Blend faces in RGB, then quantize to the current Doom palette. The original
 * engine framebuffer remains untouched. Palette index zero is transparent
 * to sprites: the destination is cleared to palette zero before every frame. */
static uint32_t rgb[256];
static uint8_t dark[256], active[256];
static uint8_t composite[200][320], shadow[200][320], valid[20];
static unsigned light;
static int palette_known;
static unsigned nearest(unsigned r, unsigned g, unsigned b)
{
    unsigned best = 0, distance = ~0u;
    for (unsigned j = 0; j < 256; ++j) {
        int dr = (int)r-(int)((rgb[j]>>16)&255), dg = (int)g-(int)((rgb[j]>>8)&255);
        int db = (int)b-(int)(rgb[j]&255);
        unsigned d = (unsigned)(dr*dr + dg*dg + db*db);
        if (d < distance) { best = j; distance = d; }
    }
    return best;
}
void doom_video_palette(const uint32_t *palette)
{
    unsigned brightest = 0;
    if (palette_known && !memcmp(rgb, palette, sizeof rgb)) return;
    memcpy(rgb, palette, sizeof rgb);
    for (unsigned i = 0; i < 256; ++i) {
        unsigned r=(rgb[i]>>16)&255, g=(rgb[i]>>8)&255, b=rgb[i]&255;
        unsigned brightness = 2*r+5*g+b;
        gpu_palette(i, rgb[i]);
        /* 38% black face; pressed face is 50% white. */
        dark[i] = (uint8_t)nearest((r*158+128)/256, (g*158+128)/256, (b*158+128)/256);
        active[i] = (uint8_t)nearest((r+255)/2, (g+255)/2, (b+255)/2);
        if (brightness >= brightest) { brightest = brightness; light = i; }
    }
    palette_known = 1;
}
static void wait_gpu(void)
{
    while (!(GPU_REG_STATUS & 4u)) doom_poll_touch();
}
void doom_video_init(void) { wait_gpu(); gpu_clear(0); gpu_swap(); memset(valid,0,sizeof valid); }
void doom_message(const char *message)
{
    wait_gpu(); gpu_palette(255,0xffffff); gpu_clear(0);
    gpu_text(20,120,message,255,1); gpu_swap();
}
static int draw_arrow(const doom_button_t *button)
{
    int cx=button->x+button->w/2,cy=button->y+button->h/2;
    int dx=button->key==KEY_LEFTARROW?-1:button->key==KEY_RIGHTARROW?1:0;
    int dy=button->key==KEY_UPARROW?-1:button->key==KEY_DOWNARROW?1:0;
    if(!dx && !dy)return 0;
    /* Filled 11x13-pixel arrows, independent of the ASCII font. */
    if(dy) {
        gpu_rect(cx-1,dy<0?cy-2:cy-5,3,8,light);
        for(int i=0;i<5;++i)gpu_rect(cx-i,cy+dy*(6-i),2*i+1,1,light);
    } else {
        gpu_rect(dx<0?cx-2:cx-5,cy-1,8,3,light);
        for(int i=0;i<5;++i)gpu_rect(cx+dx*(6-i),cy-i,1,2*i+1,light);
    }
    return 1;
}
void doom_video_frame(const uint8_t *pixels)
{
    wait_gpu();
    memcpy(composite, pixels, sizeof composite);
    for (unsigned i = 0; i < doom_button_count; ++i) {
        const doom_button_t *b = doom_buttons+i;
        const uint8_t *blend = b->key && doom_input_held(b->key) ? active : dark;
        for (int y = 0; y < 200; ++y) {
            int sy = y*3/2;
            if (sy < b->y || sy >= b->y+b->h) continue;
            for (int x = 0; x < 320; ++x) {
                int sx = 16+x*3/2;
                if (sx >= b->x && sx < b->x+b->w) composite[y][x]=blend[composite[y][x]];
            }
        }
    }
    for (unsigned ty = 0; ty < 4; ++ty) {
        unsigned rows = ty == 3 ? 8 : 64;
        for (unsigned tx = 0; tx < 5; ++tx) {
            unsigned slot = ty*5+tx;
            int changed = !valid[slot];
            for (unsigned y=0; !changed && y<rows; ++y)
                changed = memcmp(&composite[ty*64+y][tx*64], &shadow[ty*64+y][tx*64],64)!=0;
            if (!changed) continue;
            for (unsigned y=0; y<rows; ++y) {
                for (unsigned x=0; x<64; ++x)
                    gpu_wr(26, ((slot<<12 | y<<6 | x)<<8) | composite[ty*64+y][tx*64+x]);
                memcpy(&shadow[ty*64+y][tx*64], &composite[ty*64+y][tx*64],64);
            }
            valid[slot]=1;
        }
    }
    gpu_clear(0); gpu_wr(GPU_FLAGS,0);
    gpu_wr(GPU_U0,21846); gpu_wr(GPU_V0,21846);
    gpu_wr(GPU_DUDX,43691); gpu_wr(GPU_DVDX,0); gpu_wr(GPU_DUDY,0); gpu_wr(GPU_DVDY,43691);
    for (unsigned ty=0;ty<4;++ty) {
        gpu_wr(GPU_SIZE, ((ty==3?12u:96u)<<16)|96u);
        for (unsigned tx=0;tx<5;++tx) {
            gpu_wr(GPU_DST,(ty*96u<<16)|(16+tx*96u));
            gpu_wr(GPU_CMD_SPRITE,ty*5+tx);
        }
    }
    for (unsigned i=0;i<doom_button_count;++i) {
        const doom_button_t *b=doom_buttons+i;
        gpu_rect(b->x,b->y,b->w,1,light); gpu_rect(b->x,b->y+b->h-1,b->w,1,light);
        gpu_rect(b->x,b->y,1,b->h,light); gpu_rect(b->x+b->w-1,b->y,1,b->h,light);
        if(!draw_arrow(b))
            gpu_text(b->x+(b->w-gpu_text_width(b->label,1))/2,b->y+(b->h-16)/2,b->label,light,1);
    }
    if (doom_input_current_context() == DOOM_INPUT_MENU) {
        gpu_rect(164,210,166,86,0);
        gpu_text(170,214,"UP/DOWN: SELECT",light,1);
        gpu_text(170,230,"LEFT/RIGHT: ADJUST",light,1);
        gpu_text(170,246,"OK: ENTER",light,1);
        gpu_text(170,262,"BACK: PREVIOUS",light,1);
        gpu_text(170,278,"DIALOG: YES / NO",light,1);
        gpu_text(12,8,"SAVE/LOAD UNAVAILABLE",light,1);
    }
    gpu_swap();
}
