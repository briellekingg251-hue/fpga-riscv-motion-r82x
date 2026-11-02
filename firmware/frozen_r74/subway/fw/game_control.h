/* Game-owned adapter; production service uses the hardware capture ms clock. */
#ifndef FN_GAME_CONTROL_H
#define FN_GAME_CONTROL_H
#include "control_boot.h"
#include "pose_input.h"
#include "soc.h"
#if FN_POSE_PRODUCTION
#include "game_pose_service.h"
#endif
#ifndef GAME_CONTROL_BOOT_PTR
#define GAME_CONTROL_BOOT_PTR ((const volatile control_boot_t *)(uintptr_t)CONTROL_BOOT_ADDR)
#endif
typedef struct {
    control_mode_t mode;
    uint32_t epoch,last_seq,last_event,cycles,ms,remainder;
    int have_seq,have_event,fresh;
    control_frame_t frame;
} game_control_t;
static inline void game_control_init(game_control_t *g,
                                      const volatile control_boot_t *p,
                                      uint32_t id,uint32_t cycles) {
    control_boot_t b;
    *g=(game_control_t){0}; g->cycles=cycles;
    if(control_boot_read(p,id,&b)) {
        g->mode=(control_mode_t)b.mode; g->epoch=b.session_epoch;
    }
#if defined(FN_TOUCH_VERSION) && FN_TOUCH_VERSION
    g->mode=CONTROL_TOUCH;
#endif
    pose_input_config_t cfg; pose_input_defaults(&cfg);
    if(g->mode==CONTROL_POSE && !pose_input_configure(&cfg,id))g->mode=CONTROL_TOUCH;
    control_reset(g->epoch); /* also drain backend when returning to TOUCH */
#if FN_POSE_PRODUCTION
    if(g->mode==CONTROL_POSE)game_pose_start(g->epoch,id);
#endif
}
static inline uint32_t game_control_now(game_control_t *g,uint32_t cycles) {
#if FN_POSE_PRODUCTION
    (void)cycles;g->ms=game_pose_now();return g->ms;
#else
    uint32_t delta=cycles-g->cycles; g->cycles=cycles;
    uint64_t total=(uint64_t)delta*1000u+g->remainder;
    g->ms+=(uint32_t)(total/CPU_CLOCK_HZ);
    g->remainder=(uint32_t)(total%CPU_CLOCK_HZ);
    return g->ms;
#endif
}
static inline void game_control_flush(game_control_t *g) {
    control_reset(g->epoch); g->frame=(control_frame_t){0}; g->fresh=0;g->have_event=0;
#if FN_POSE_PRODUCTION
    if(g->mode==CONTROL_POSE)game_pose_flush();
#endif
    /* Keep consumed identities across UI transitions within this session. */
}
static inline void game_control_service(game_control_t *g) {
#if FN_POSE_PRODUCTION
    if(g->mode==CONTROL_POSE){game_pose_step();game_pose_debug();}
#else
    (void)g;
#endif
}
static inline int game_control_stop(game_control_t *g) {
#if FN_POSE_PRODUCTION
    if(g->mode==CONTROL_POSE)return game_pose_stop_step();
#else
    (void)g;
#endif
    return 1;
}
static inline int game_control_poll(game_control_t *g,uint32_t now_ms) {
    g->fresh=0;
    if(g->mode!=CONTROL_POSE){g->frame=(control_frame_t){0};return 0;}
    pose_input_tick(now_ms);
    int fresh=control_poll(&g->frame);
    if(!g->epoch || g->frame.session_epoch!=g->epoch) {
        g->frame=(control_frame_t){0}; return 0;
    }
    if(fresh && g->frame.seq && (!g->have_seq || g->last_seq!=g->frame.seq)) {
        g->last_seq=g->frame.seq;g->have_seq=1;g->fresh=1;
    }
    if(!g->fresh || !g->frame.pose_valid) {
        g->frame.actions.move=CONTROL_MOVE_NONE;g->frame.actions.event_seq=0;
        for(unsigned h=0;h<2;h++)g->frame.hand[h].segment_valid=0;
    } else if(g->frame.actions.event_seq) {
        if(g->have_event && g->last_event==g->frame.actions.event_seq) {
            g->frame.actions.move=CONTROL_MOVE_NONE;g->frame.actions.event_seq=0;
        } else {g->last_event=g->frame.actions.event_seq;g->have_event=1;}
    }
    if(!g->frame.pose_valid){g->frame.actions.duck_held=0;for(unsigned h=0;h<2;h++)g->frame.hand[h]=(control_blade_t){0};}
    return g->fresh;
}
#endif
