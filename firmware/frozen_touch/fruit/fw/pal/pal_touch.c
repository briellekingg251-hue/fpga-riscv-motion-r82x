/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "pal_touch.h"
/* Overlaid on the full-screen game (512x300 logical, 2x on the LCD):
 * D-pad bottom-left, action buttons bottom-right, paging top-right. */
const pal_button_t pal_buttons[6]={
 {414,200,92,44,"OK",PAL_CONFIRM},{414,252,92,42,"BACK",PAL_MENU},
 {346,252,62,42,"AUTO",PAL_AUTO},{346,200,62,44,"STATUS",PAL_STATUS},
 {450,6,56,30,"PGUP",PAL_PAGEUP},{450,40,56,30,"PGDN",PAL_PAGEDOWN}
};
static uint32_t hit(int x,int y){
 if(x<0 || x>=512 || y<0 || y>=300)return 0;
 if(x<160 && y>=210){
  int dx=x-80,dy=y-255,ax=dx<0?-dx:dx,ay=dy<0?-dy:dy;
  if(ax<16 && ay<16)return 0;
  if(ax>ay)return dx<0?PAL_LEFT:PAL_RIGHT;
  return dy<0?PAL_UP:PAL_DOWN;
 }
 for(unsigned i=0;i<6;i++){
  const pal_button_t *b=pal_buttons+i;
  if(x>=b->x && x<b->x+b->w && y>=b->y && y<b->y+b->h)return b->key;
 }
 return 0;
}
pal_touch_events_t pal_touch_update(pal_touch_state_t *s,uint32_t ms,
                                  int valid,int down,int x,int y){
 uint32_t held=valid && down?hit(x,y):0;
 pal_touch_events_t e={held,held&~s->held,s->held&~held};
 if(held!=s->held)s->deadline=ms+300u;
 else if((held&(PAL_UP|PAL_DOWN|PAL_LEFT|PAL_RIGHT|PAL_PAGEUP|PAL_PAGEDOWN)) &&
         (int32_t)(ms-s->deadline)>=0){e.pressed=held;s->deadline=ms+80u;}
 s->held=held;return e;
}
