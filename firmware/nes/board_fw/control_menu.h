/* Pure loader menu state, shared with host tests. Max 8 packages, page 4. */
#ifndef FN_CONTROL_MENU_H
#define FN_CONTROL_MENU_H
#include "control.h"
#define CONTROL_MENU_MAX 8u
enum { MENU_MODE, MENU_GAMES, MENU_FAILED };
enum { MENU_NONE, MENU_REDRAW, MENU_LOAD, MENU_LIGHT, MENU_INSTALL };
typedef struct {
    uint32_t ids[CONTROL_MENU_MAX];
    unsigned count,stage,mode,page,armed;
    uint32_t sequence;
    unsigned have_sequence;
} control_menu_t;
static inline unsigned control_menu_visible(const control_menu_t *m,unsigned *out) {
    unsigned n=0;
    for(unsigned i=0;i<m->count;i++)
        if(m->ids[i]!=CONTROL_GAME_VIEW && control_game_allowed(m->mode,m->ids[i]))out[n++]=i;
    return n;
}
/* Only healthy fresh READY samples can arm on a real lift or press. */
static inline int control_menu_touch(control_menu_t *m,uint32_t sequence,
                                     int healthy,int down,int x,int y,unsigned *selected) {
    if(!healthy)return MENU_NONE;
    if(m->have_sequence && sequence==m->sequence)return MENU_NONE;
    m->have_sequence=1;m->sequence=sequence;
    if(!down){m->armed=1;return MENU_NONE;}
    if(!m->armed)return MENU_NONE;
    m->armed=0;
    if(m->stage==MENU_FAILED){m->stage=MENU_MODE;m->page=0;return MENU_REDRAW;}
    if(y<50 && x>=290)return MENU_LIGHT;
    if(x>=300 && y>=240)return MENU_INSTALL;
    if(m->stage==MENU_MODE){
        if(y>=240 && x<290){
            for(unsigned i=0;i<m->count;i++)if(m->ids[i]==CONTROL_GAME_VIEW){
                *selected=i;m->mode=CONTROL_POSE;return MENU_LOAD;
            }
            return MENU_NONE;
        }
        /* Two side-by-side cards: TOUCH left, BODY POSE right. */
        if(y<60 || y>=236)return MENU_NONE;
        m->mode=x<256?CONTROL_TOUCH:CONTROL_POSE;
        m->stage=MENU_GAMES;m->page=0;return MENU_REDRAW;
    }
    if(y>=240 && x>=140 && x<290){m->stage=MENU_MODE;m->page=0;return MENU_REDRAW;}
    unsigned visible[CONTROL_MENU_MAX],n=control_menu_visible(m,visible);
    if(y>=240 && x<140 && n>4){m->page=(m->page+1)%((n+3)/4);return MENU_REDRAW;}
    if(y>=60 && y<220){unsigned j=m->page*4+(unsigned)(y-60)/40;
        if(j<n){*selected=visible[j];return MENU_LOAD;}}
    return MENU_NONE;
}
#endif
