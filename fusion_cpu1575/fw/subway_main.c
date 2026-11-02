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
#include "game_control.h"
#include "pose_ui.h"
static game_control_t game_control;
/* POSE mode only: live skeleton/cursor UI, wait-for-player and auto pause. */
static pose_ui_t pose_ui;
static int pose_waiting=1,pose_lost_pause;

static struct {
    touch_sample_t sample;
    app_input_t input;
    unsigned track_id;
    int seen,stale_frames,press_armed;
} touch;
static uint32_t rng=0x2545f491u;
static uint32_t saved_best;
static int returning_to_menu;

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

/* A player standing away from the screen holds a hand over a button. */
static void pose_buttons(app_input_t *in)
{
    const button_t *b[3];unsigned n=0;pose_ui_rect_t r[3];
    if(sw_state_now()==SW_PAUSE){b[n++]=&SW_BTN_RESUME;b[n++]=&SW_BTN_RESTART;b[n++]=&SW_BTN_MENU_P;}
    else if(sw_state_now()==SW_OVER){b[n++]=&SW_BTN_RETRY;b[n++]=&SW_BTN_MENU_O;}
    for(unsigned k=0;k<n;k++)r[k]=(pose_ui_rect_t){b[k]->x,b[k]->y,b[k]->w,b[k]->h};
    int i=pose_ui_dwell(&pose_ui,r,n);
    if(i>=0 && !in->pressed){
        in->x=b[i]->x+b[i]->w/2;in->y=b[i]->y+b[i]->h/2;
        in->pressed=in->down=in->fresh=1;in->blocked=0;
    }
}

static int update_game(const app_input_t *input,int fresh);
static int step_game(void)
{
    app_input_t input=sample_input();int before=sw_state_now();
    int fresh=game_control.mode==CONTROL_POSE?
        game_control_poll(&game_control,game_control_now(&game_control,MTIME_LO)):0;
    if(game_control.mode==CONTROL_POSE){
        pose_ui_update(&pose_ui,game_control.ms);
        pose_buttons(&input);
        if(before==SW_PLAY){
            /* The run starts only once the camera has the player; losing the
             * player mid-run pauses instead of crashing into a train. */
            if(pose_waiting){
                if(!pose_ui.body || !(pose_input_state()&POSE_INPUT_CALIBRATED)){
                    if(input.pressed && app_button_hit(&input,&SW_BTN_PAUSE)){sw_pause();app_consume_touch("SUBWAY PAUSE");}
                    return SW_STAY;
                }
                pose_waiting=0;
            }
            if(pose_ui_lost_for(&pose_ui,POSE_UI_LOST_MS)){
                sw_pause();pose_lost_pause=1;app_consume_touch("SUBWAY AUTO PAUSE");
                game_control_flush(&game_control);sw_break_pose_actions();return SW_STAY;
            }
        }
    }
    return update_game(&input,fresh);
}

static int update_game(const app_input_t *input,int fresh)
{
    int before=sw_state_now();
    int exit=game_control.mode==CONTROL_POSE?
        sw_update_pose(input,&game_control.frame,fresh):sw_update(input);
    if(game_control.mode==CONTROL_POSE && before!=sw_state_now()){
        game_control_flush(&game_control);sw_break_pose_actions();
        if(sw_state_now()==SW_PLAY){pose_waiting=1;pose_lost_pause=0;} /* resume/restart */
    }
    if(exit==SW_EXIT_MENU || (before==SW_PLAY && sw_state_now()==SW_OVER))save_best();
    return exit;
}

enum { SW_TIMED_BACKLOG=2 };
#define SW_TICK_CYCLES (CPU_CLOCK_HZ/60u)
static uint32_t simulation_ticks;
/* Keep the original per-tick rules and collision sweep. Presenting at 30Hz
 * executes two original ticks; at 20Hz three. Never skip distance/collisions.
 * Old ticks use previously held input; current edges are consumed once on
 * the newest tick. Eight ticks per batch bound camera service latency, and
 * a backlog is carried forward without rendering or discarding simulation time. */
static int step_timed_game(uint32_t *clock)
{
    uint32_t due=(MTIME_LO-*clock)/SW_TICK_CYCLES;
    for(uint32_t n=0;n<due && n<8u;n++) {
        int before=sw_state_now(),waiting=pose_waiting,rc=SW_STAY;
        *clock+=SW_TICK_CYCLES;simulation_ticks++;
        if(n+1u==due)rc=step_game();
        else if(before==SW_PLAY && !(game_control.mode==CONTROL_POSE && pose_waiting)) {
            app_input_t held=touch.input;held.pressed=held.fresh=held.new_stroke=0;
            rc=update_game(&held,0);
        }
        if(rc==SW_EXIT_MENU || before!=sw_state_now() || (waiting && !pose_waiting)) {
            *clock=MTIME_LO;return rc;
        }
    }
    return due>8u?SW_TIMED_BACKLOG:SW_STAY;
}

int main(void)
{
    uint32_t sent=gpu_swaps(),t_mark=MTIME_LO;unsigned frames=0,f_mark=0;
    /* Loading was selected by touch: require its real lift before playing. */
    touch.input.blocked=1;
    saved_best=game_record_load();sw_best=saved_best>0x7fffffffu?0x7fffffff:(int)saved_best;
    game_control_init(&game_control,GAME_CONTROL_BOOT_PTR,CONTROL_GAME_SUBWAY,MTIME_LO);
    sw_set_control(game_control.mode,game_control.epoch);
    pose_ui_reset(&pose_ui,game_control.ms);
    pose_waiting=1;pose_lost_pause=0;
    sw_new_run();
    uart_puts("\nSUBWAY SD LOADED: s80 RV32 @157.5MHz / ABI1\n");
    uart_puts("best ");uart_putu(saved_best);uart_puts("\n");
    uart_puts("build POSE-FEEDBACK-20261010 / SIM60 / TILE8\n");
    uint32_t sim_clock=MTIME_LO;simulation_ticks=0;
    for(;;){
        while((uint16_t)(sent-gpu_swaps())!=0u){game_control_service(&game_control);}
        if(returning_to_menu) {
            if(game_control_stop(&game_control))storage_jump(0x80018000u);
            continue;
        }
        game_control_service(&game_control);
        int tick_result=step_timed_game(&sim_clock);
        if(tick_result==SW_TIMED_BACKLOG)continue;
        if(tick_result==SW_EXIT_MENU){
            game_control_flush(&game_control);returning_to_menu=1;
            continue;
        }
        sw_draw();
        if(game_control.mode==CONTROL_POSE){
            int st=sw_state_now();
            if(st==SW_PLAY && pose_waiting)
                pose_ui_draw_prompt(&pose_ui,104,pose_ui.body?"STAND STILL TO START":"STEP INTO VIEW",
                                    "SHOW SHOULDERS, HIPS AND KNEES");
            if(st==SW_PAUSE && pose_lost_pause)app_draw_center("PLAYER LOST",245,COL_RED,COL_SHADOW,1);
#if !FN_DUAL_POSE_PIP
    pose_ui_draw_panel(&pose_ui,418,232);
#endif
            if(st!=SW_PLAY)pose_ui_draw_cursors(&pose_ui);
        }
        gpu_swap();sent++;frames++;
        GPIO_OUT=((frames>>5)&1u)|(sw_state_now()==SW_PLAY?2u:0u);
        if(frames-f_mark>=300u){
            uint32_t now=MTIME_LO,kcycles=(now-t_mark)/1000u;
            uart_puts("subway frame ");uart_putu(frames);uart_puts(" fps x10 ");
            uart_putu(kcycles?(frames-f_mark)*(CPU_CLOCK_HZ/100u)/kcycles:0);
            uart_puts(" ticks ");uart_putu(simulation_ticks);
            uart_puts(" score ");uart_putu((uint32_t)sw_score_now());uart_puts(" state ");
            uart_putu((uint32_t)sw_state_now());uart_puts("\n");t_mark=now;f_mark=frames;
        }
    }
}
