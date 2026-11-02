/* Independent SD-loaded Subway Run program. Touch semantics match the
 * established arcade game; the game logic always runs on the s80 CPU. */
#include <stdint.h>
#include "soc.h"
#include "gpu.h"
#include "assets.h"
#include "touch.h"
#include "storage.h"
#include "app.h"
#include "subway.h"
#include "subway_int.h"

static struct {
    touch_sample_t sample;
    app_input_t input;
    unsigned track_id;
    int seen,stale_frames,press_armed;
} touch;
static uint32_t rng=0x2545f491u;
static uint32_t saved_best;

uint32_t app_rnd(void){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
int app_rnd_range(int lo,int hi){return lo+(int)(app_rnd()%(unsigned)(hi-lo+1));}
void app_log(const char *s){uart_puts(s);uart_puts("\n");}
void app_fmt_uint(char *dst,const char *prefix,int value)
{
    char digits[12];unsigned n=0;
    while(*prefix)*dst++=*prefix++;
    if(value<0)value=0;
    do{digits[n++]=(char)('0'+value%10);value/=10;}while(value);
    while(n)*dst++=digits[--n];
    *dst=0;
}
void app_draw_center(const char *s,int y,unsigned color,unsigned shadow,int scale)
{gpu_text_shadow((FB_W-gpu_text_width(s,scale))/2,y,s,color,shadow,scale);}
void app_draw_button(const button_t *b)
{
    gpu_rect(b->x,b->y,b->w,b->h,COL_GOLD);gpu_rect(b->x+2,b->y+2,b->w-4,b->h-4,COL_INK);
    gpu_text_shadow(b->x+(b->w-gpu_text_width(b->label,1))/2,b->y+(b->h-16)/2,b->label,COL_WHITE,COL_SHADOW,1);
}
int app_button_hit(const app_input_t *in,const button_t *b)
{return in->x>=b->x && in->x<b->x+b->w && in->y>=b->y && in->y<b->y+b->h;}
void app_consume_touch(const char *action)
{
    touch.input.blocked=1;touch.press_armed=0;
    touch.input.pressed=touch.input.new_stroke=0;app_log(action);
}

static app_input_t sample_input(void)
{
    touch_sample_t s=touch_read();app_input_t *in=&touch.input;
    unsigned count=(s.status>>4)&15u,id=(s.status>>8)&255u;
    int was_down=in->down,x=in->x,y=in->y;
    in->fresh=!touch.seen || s.sequence!=touch.sample.sequence;
    if(in->fresh)touch.stale_frames=0;
    else if(touch.stale_frames<FN_TOUCH_STALE_FRAMES)touch.stale_frames++;
    int healthy=(s.status&(TOUCH_READY|TOUCH_FAULT))==TOUCH_READY;
    int down=healthy && (s.status&TOUCH_DOWN) && count>=1 && count<=5 &&
        touch.stale_frames<FN_TOUCH_STALE_FRAMES && touch_map(s.xy,&x,&y);
    if(healthy && in->fresh && !(s.status&TOUCH_DOWN) && count==0){
        touch.press_armed=1;in->blocked=0;
    }
    in->pressed=down && in->fresh && !was_down && touch.press_armed && !in->blocked;
    in->new_stroke=down && (!was_down || id!=touch.track_id);
    if(down)touch.press_armed=0;
    in->down=down;in->x=x;in->y=y;touch.track_id=id;touch.sample=s;touch.seen=1;
    return *in;
}

static int save_best(void)
{
    uint32_t score=(uint32_t)sw_best_now();
    if(score<=saved_best)return 0;
    if(game_record_save(score)){uart_puts("SUBWAY SD SAVE FAILED\n");return -1;}
    saved_best=score;uart_puts("SUBWAY SD SAVE OK best ");uart_putu(score);uart_puts("\n");return 0;
}

static int step_game(void)
{
    app_input_t input=sample_input();int before=sw_state_now();
    int exit=sw_update(&input);
    if(exit==SW_EXIT_MENU || (before==SW_PLAY && sw_state_now()==SW_OVER))save_best();
    return exit;
}

int main(void)
{
    uint32_t sent=gpu_swaps(),t_mark=MTIME_LO;unsigned frames=0,f_mark=0;
    /* Loading was selected by touch: require its real lift before playing. */
    touch.input.blocked=1;
    saved_best=game_record_load();sw_best=saved_best>0x7fffffffu?0x7fffffff:(int)saved_best;
    sw_new_run();
    uart_puts("\nSUBWAY SD LOADED: s80 RV32 @162MHz / ABI1\n");
    uart_puts("best ");uart_putu(saved_best);uart_puts("\n");
    for(;;){
        while((uint16_t)(sent-gpu_swaps())!=0u){}
        if(step_game()==SW_EXIT_MENU){
            while(!(GPU_REG_STATUS&4u)){}
            storage_jump(0x80018000u);
        }
        sw_draw();gpu_swap();sent++;frames++;
        GPIO_OUT=((frames>>5)&1u)|(sw_state_now()==SW_PLAY?2u:0u);
        if(frames-f_mark>=300u){
            uint32_t now=MTIME_LO,kcycles=(now-t_mark)/1000u;
            uart_puts("subway frame ");uart_putu(frames);uart_puts(" fps x10 ");
            uart_putu(kcycles?(frames-f_mark)*1620000u/kcycles:0);
            uart_puts(" score ");uart_putu((uint32_t)sw_score_now());uart_puts(" state ");
            uart_putu((uint32_t)sw_state_now());uart_puts("\n");t_mark=now;f_mark=frames;
        }
    }
}
