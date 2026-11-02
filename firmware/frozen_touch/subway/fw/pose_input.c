#include "pose_input.h"
#include <string.h>
#ifndef POSE_SUBWAY_ZONES
#define POSE_SUBWAY_ZONES 0   /* default lane mode: relative step */
#endif

typedef struct { int32_t x,y,dx,dy,raw_x,raw_y; uint32_t ms,on; } euro_t;
static pose_input_config_t c;
static uint32_t configured, game, session, input_seq, have_seq, track, have_track;
static control_frame_t frame;
static uint32_t unread, event_id, have_capture, have_timestamp, last_capture, have_clock, clock_ms;
static uint32_t calibrated, stable_on, stable_start, armed, candidate, candidate_ms;
static uint32_t last_event_ms, had_event;
static int32_t stable_x, stable_y, anchor_x, base_shoulder_y, base_hip_y;
static int32_t base_width, base_torso, base_leg;
static uint32_t duck_candidate, duck_candidate_ms;
static uint32_t zone, zone_candidate, zone_candidate_ms;
static euro_t blade[2];
/* Display-only copy of the last snapshot that passed every gate. */
static control_pose_snapshot_t view; static uint32_t view_ok;
static int32_t ab(int32_t x) { return x < 0 ? -x : x; }
static int newer(uint32_t a,uint32_t b) { uint32_t d=a-b; return d && d<0x80000000u; }
static int elapsed(uint32_t a,uint32_t b,uint32_t lim) { return a-b >= lim; }
static int32_t frac(int32_t v,uint32_t q) { return (int32_t)((int64_t)v*q/256); }
static int32_t clamp(int32_t v,int32_t lo,int32_t hi) { return v<lo?lo:v>hi?hi:v; }

void pose_input_defaults(pose_input_config_t *v) {
    if (!v) return;
    *v=(pose_input_config_t){ .stale_ms=180, .stable_ms=165, .debounce_ms=66,
        .cooldown_ms=165, .min_logit=-6, .min_width_px=32, .min_torso_px=45,
        .step_q8=256, .release_q8=192, .stable_q8=20, .scale_tolerance_q8=64,
        .duck_enter_q8=77, .duck_exit_q8=38, .knee_compress_q8=179,
        .mirror_move=1, .mirror_blade=1, .blade_gain_q8=384,
        .framebuffer_w=512, .framebuffer_h=300,
        .blade_jump_px=420, .blade_speed_px_s=6000,
        .min_cutoff_q8=179, .beta_q16=3277,
        .lane_zones=POSE_SUBWAY_ZONES, .zone_hyst_q8=10, .zone_dwell_ms=132 };
}
static void break_motion(void) {
    calibrated=stable_on=armed=candidate=duck_candidate=had_event=0;
    stable_x=stable_y=anchor_x=base_shoulder_y=base_hip_y=0;
    base_width=base_torso=base_leg=0;
    stable_start=candidate_ms=last_event_ms=duck_candidate_ms=0;
    frame.actions.event_seq=0; frame.actions.move=CONTROL_MOVE_NONE; frame.actions.duck_held=0;
    zone=zone_candidate=zone_candidate_ms=0; frame.actions.target_lane=0;
    memset(blade,0,sizeof blade); memset(frame.hand,0,sizeof frame.hand);
}
/* Mode B keeps the lane zone across a crouch-baseline reset. */
static void break_duck(void) {
    calibrated=stable_on=duck_candidate=0; frame.actions.duck_held=0;
    base_shoulder_y=base_hip_y=base_width=base_torso=base_leg=0;
}
void control_reset(uint32_t epoch) {
    if (!configured) { pose_input_defaults(&c); game=CONTROL_GAME_SUBWAY; configured=1; }
    /* Track/UI resets clear motion but share the consumers' session namespace.
     * Preserve event identities across them; only a new/invalid session starts
     * a new counter. Increment in subway() still wraps and skips zero. */
    if (!epoch || epoch!=session) event_id=0;
    memset(&frame,0,sizeof frame); session=epoch; frame.session_epoch=epoch;
    view_ok=0;
    have_seq=have_track=unread=have_capture=have_timestamp=have_clock=0;
    input_seq=track=last_capture=clock_ms=0;
    break_motion();
}
int pose_input_configure(const pose_input_config_t *v,uint32_t id) {
    if (!v || !control_game_allowed(CONTROL_POSE,id) ||
        !v->stale_ms || v->stale_ms>=0x80000000u || !v->stable_ms ||
        v->stable_ms>=0x80000000u || v->debounce_ms>=0x80000000u ||
        v->cooldown_ms>=0x80000000u || v->min_width_px<1 ||
        v->min_width_px>1279 || v->min_torso_px<1 || v->min_torso_px>719 ||
        !v->step_q8 || v->step_q8>4096 || v->release_q8>=v->step_q8 ||
        !v->stable_q8 || v->stable_q8>=v->release_q8 ||
        !v->scale_tolerance_q8 || v->scale_tolerance_q8>128 ||
        v->duck_enter_q8<=v->duck_exit_q8 || v->duck_enter_q8>256 ||
        !v->knee_compress_q8 || v->knee_compress_q8>256 ||
        v->mirror_move>1 || v->mirror_blade>1 || !v->blade_gain_q8 ||
        v->blade_gain_q8>1024 || v->framebuffer_w!=512 || v->framebuffer_h!=300 ||
        !v->blade_jump_px || v->blade_jump_px>1469 ||
        !v->blade_speed_px_s || v->blade_speed_px_s>100000 ||
        v->min_cutoff_q8<1 || v->min_cutoff_q8>25600 ||
        v->beta_q16<0 || v->beta_q16>65536 || v->lane_zones>1 ||
        v->zone_hyst_q8>42 || v->zone_dwell_ms>=0x80000000u) return 0;
    c=*v; configured=1; game=id; control_reset(session); return 1;
}
void pose_input_tick(uint32_t now) {
    if (!configured) return;
    if (have_clock && newer(clock_ms,now)) {
        break_motion(); frame.pose_valid=0; have_capture=0;
    }
    clock_ms=now; have_clock=1;
    if (have_capture && elapsed(now,frame.capture_ms,c.stale_ms)) {
        break_motion(); frame.pose_valid=0; have_capture=0;
    }
}
static int valid(const control_pose_snapshot_t *s,unsigned j) {
    const control_joint_t *p=&s->joint[j];
    return p->valid && p->logit>=c.min_logit && p->x>=0 && p->x<1280 && p->y>=0 && p->y<720;
}
static int body(const control_pose_snapshot_t *s,int32_t *x,int32_t *sy,
                int32_t *hy,int32_t *w,int32_t *t,int32_t *leg) {
    const control_joint_t *p=s->joint;
    if (!valid(s,0)||!valid(s,1)||!valid(s,6)||!valid(s,7)) return 0;
    int32_t sx=(p[0].x+p[1].x)/2, hx=(p[6].x+p[7].x)/2;
    *sy=(p[0].y+p[1].y)/2; *hy=(p[6].y+p[7].y)/2;
    *w=ab(p[0].x-p[1].x); *t=*hy-*sy; *x=(sx+hx)/2;
    int32_t hw=ab(p[6].x-p[7].x);
    if (*w<c.min_width_px || *t<c.min_torso_px || hw<*w/3 || hw>*w*2 ||
        ab(sx-hx)>*t/3 || ab(p[0].y-p[1].y)>*t/3 ||
        ab(p[6].y-p[7].y)>*t/3) return 0;
    *leg=0;
    if (game==CONTROL_GAME_SUBWAY) {
        /* Mode B: lateral needs no knees; leg=0 then blocks crouch and
         * its calibration only. */
        if (!valid(s,8)||!valid(s,9)) return c.lane_zones ? 1 : 0;
        int32_t a=p[8].y-p[6].y, b=p[9].y-p[7].y;
        if (a<=0 || b<=0 || ab(a-b)>*t/2) return c.lane_zones ? 1 : 0;
        *leg=a>b?a:b; /* Both thighs must compress, not merely their mean. */
    }
    return 1;
}
/* Stable against a window seed, not only adjacent samples (slow drift cannot
 * masquerade as a stable stance). Returns 1 after a bounded stationary window. */
static int stable(int32_t x,int32_t y,int32_t width,uint32_t ms) {
    int32_t eps=frac(width,c.stable_q8); if(eps<1) eps=1;
    if (!stable_on || ab(x-stable_x)>eps || ab(y-stable_y)>eps) {
        stable_on=1; stable_start=ms; stable_x=x; stable_y=y; return 0;
    }
    return elapsed(ms,stable_start,c.stable_ms);
}
/* Mode B: lane = third of the mirrored camera width holding the torso
 * centre. Leaving a zone needs zone_hyst past the 1/3 or 2/3 line, and a
 * new zone must persist zone_dwell_ms before it is published. */
static void subway_zone(int32_t x,uint32_t ms) {
    int32_t u=c.mirror_move?1279-x:x;
    int32_t h=frac(1280,c.zone_hyst_q8), b1=1280/3, b2=1280*2/3;
    uint32_t want=zone;
    if (!zone) want=u<b1?1u:u<b2?2u:3u;
    else if (zone==1u && u>=b1+h) want=u>=b2+h?3u:2u;
    else if (zone==2u && u<b1-h) want=1u;
    else if (zone==2u && u>=b2+h) want=3u;
    else if (zone==3u && u<b2-h) want=u<b1-h?1u:2u;
    if (want==zone) { zone_candidate=0; return; }
    if (zone_candidate!=want) { zone_candidate=want; zone_candidate_ms=ms; }
    if (elapsed(ms,zone_candidate_ms,c.zone_dwell_ms)) {
        zone=want; zone_candidate=0; frame.actions.target_lane=zone;
    }
}
static void subway(int32_t x,int32_t sy,int32_t hy,int32_t w,int32_t t,
                   int32_t leg,uint32_t ms) {
    if (c.lane_zones) subway_zone(x,ms);
    if (calibrated && (ab(w-base_width)>frac(base_width,c.scale_tolerance_q8) ||
        ab(t-base_torso)>frac(base_torso,c.scale_tolerance_q8))) {
        if (c.lane_zones) break_duck(); else break_motion();
    }
    if (!calibrated) {
        /* Startup must be an upright standing stance; do not calibrate a
         * compressed thigh pose as standing. Human variability needs tuning. */
        if (leg<t*3/4) { stable_on=0; return; }
        if (stable(x,hy,w,ms)) {
            calibrated=armed=1; stable_on=0; anchor_x=x;
            base_width=w; base_torso=t; base_leg=leg;
            base_shoulder_y=sy; base_hip_y=hy;
        }
        return;
    }
    uint32_t want=frame.actions.duck_held;
    int32_t ds=sy-base_shoulder_y, dh=hy-base_hip_y;
    if (!want && leg>0 && ds>=frac(base_torso,c.duck_enter_q8) &&
        dh>=frac(base_torso,c.duck_enter_q8) && leg<=frac(base_leg,c.knee_compress_q8)) want=1;
    if (want && (ds<=frac(base_torso,c.duck_exit_q8) ||
                 dh<=frac(base_torso,c.duck_exit_q8))) want=0;
    if (want!=frame.actions.duck_held) {
        if (duck_candidate!=want+1) { duck_candidate=want+1; duck_candidate_ms=ms; }
        if (elapsed(ms,duck_candidate_ms,c.debounce_ms)) {
            frame.actions.duck_held=want; duck_candidate=0;
        }
    } else duck_candidate=0;
    if (c.lane_zones) return;
    /* Suppress lateral interpretation of crouch and its transitions. Re-arm
     * only at the next stable standing location; no artificial release event. */
    if (frame.actions.duck_held || duck_candidate || ds>frac(base_torso,c.duck_exit_q8)) {
        armed=candidate=stable_on=0; return;
    }
    if (!armed) {
        if (stable(x,hy,base_width,ms) && (!had_event || elapsed(ms,last_event_ms,c.cooldown_ms))) {
            anchor_x=x; armed=1; stable_on=0;
        }
        return;
    }
    int32_t d=x-anchor_x;
    uint32_t dir=d<0?CONTROL_MOVE_LEFT:CONTROL_MOVE_RIGHT;
    if (c.mirror_move) dir=dir==CONTROL_MOVE_LEFT?CONTROL_MOVE_RIGHT:CONTROL_MOVE_LEFT;
    if (ab(d)<frac(base_width,c.release_q8)) candidate=0;
    else if (ab(d)>=frac(base_width,c.step_q8)) {
        if (candidate!=dir) { candidate=dir; candidate_ms=ms; }
        if (elapsed(ms,candidate_ms,c.debounce_ms) &&
            (!had_event || elapsed(ms,last_event_ms,c.cooldown_ms))) {
            if (++event_id==0) ++event_id;
            frame.actions.event_seq=event_id; frame.actions.move=dir;
            armed=candidate=stable_on=0; last_event_ms=ms; had_event=1;
        }
    } else if (candidate && candidate!=dir) candidate=0;
}
static int32_t alpha(int32_t hz_q8,uint32_t dt) {
    int64_t r=(int64_t)hz_q8*dt*1608/1000; /* 2*pi*256 rounded */
    return (int32_t)((r*65536)/(65536+r));
}
static int32_t axis(int32_t x,int32_t raw_prev,int32_t *xh,int32_t *dh,uint32_t dt) {
    int32_t d=(int32_t)((int64_t)(x-raw_prev)*1000/dt);
    *dh+=(int32_t)((int64_t)alpha(256,dt)*(d-*dh)/65536);
    int32_t fc=c.min_cutoff_q8+(int32_t)((int64_t)ab(*dh)*c.beta_q16/65536);
    *xh+=(int32_t)((int64_t)alpha(fc,dt)*(x-*xh)/65536);
    return *xh;
}
static int16_t map(int32_t q8,uint32_t extent,uint32_t camera,uint32_t mirror) {
    int64_t x=(int64_t)q8*(extent-1)/(camera-1);
    if (mirror) x=(int64_t)(extent-1)*256-x;
    x=(int64_t)(extent-1)*128+(x-(int64_t)(extent-1)*128)*c.blade_gain_q8/256;
    return (int16_t)clamp((int32_t)((x+128)/256),0,(int32_t)extent-1);
}
static void fruit(const control_pose_snapshot_t *s) {
    for(unsigned i=0;i<2;i++) {
        euro_t *b=&blade[i]; control_blade_t *o=&frame.hand[i];
        unsigned j=POSE_L_WRIST+i;
        if (!valid(s,j)) { memset(b,0,sizeof *b); memset(o,0,sizeof *o); continue; }
        int32_t x=s->joint[j].x*256,y=s->joint[j].y*256;
        uint32_t dt=s->capture_ms-b->ms;
        int32_t dx=(x-b->raw_x)/256,dy=(y-b->raw_y)/256;
        int64_t dist2=(int64_t)dx*dx+(int64_t)dy*dy;
        int64_t speed=(int64_t)c.blade_speed_px_s*dt/1000;
        int segment=b->on && dt && dt<c.stale_ms &&
            dist2<=(int64_t)c.blade_jump_px*c.blade_jump_px && dist2<=speed*speed;
        int16_t px=o->x,py=o->y;
        if (!segment) { b->x=x; b->y=y; b->dx=b->dy=0; }
        else { axis(x,b->raw_x,&b->x,&b->dx,dt); axis(y,b->raw_y,&b->y,&b->dy,dt); }
        b->raw_x=x; b->raw_y=y; b->ms=s->capture_ms; b->on=1;
        o->x=map(b->x,c.framebuffer_w,1280,c.mirror_blade);
        o->y=map(b->y,c.framebuffer_h,720,0);
        o->point_valid=1; o->segment_valid=(uint32_t)segment;
        o->x0=segment?px:o->x; o->y0=segment?py:o->y;
    }
}
int pose_input_submit(const control_pose_snapshot_t *s,uint32_t now,uint32_t identity) {
    if (!s) return -1;
    pose_input_tick(now);
    if (!configured || !session || !s->seq || s->session_epoch!=session ||
        (have_seq && !newer(s->seq,input_seq)) ||
        (have_track && s->track_epoch!=track && !newer(s->track_epoch,track))) return 0;
    int32_t x=0,sy=0,hy=0,w=0,t=0,leg=0;
    int track_reset=!have_track || s->track_epoch!=track || (s->flags&CONTROL_POSE_TRACK_RESET);
    int ok=identity && (s->flags&CONTROL_POSE_VALID) &&
        !(s->flags&~(CONTROL_POSE_VALID|CONTROL_POSE_TRACK_RESET)) &&
        now-s->capture_ms<c.stale_ms && now-s->complete_ms<c.stale_ms &&
        s->complete_ms-s->capture_ms<c.stale_ms &&
        (!have_timestamp || newer(s->capture_ms,last_capture)) && body(s,&x,&sy,&hy,&w,&t,&leg);
    if (ok && unread && !track_reset) return -2;
    frame.actions.event_seq=0; frame.actions.move=CONTROL_MOVE_NONE;
    for (unsigned i=0;i<2;i++) frame.hand[i].segment_valid=0;
    if (!ok || track_reset) break_motion();
    input_seq=s->seq; have_seq=1; track=s->track_epoch; have_track=1;
    frame.seq=s->seq; frame.session_epoch=session; frame.track_epoch=track;
    frame.capture_ms=s->capture_ms; frame.complete_ms=s->complete_ms;
    frame.pose_valid=(uint32_t)ok; unread=1;
    view_ok=(uint32_t)ok; if (ok) view=*s;
    if (ok) {
        last_capture=s->capture_ms; have_capture=have_timestamp=1;
        if (game==CONTROL_GAME_SUBWAY) subway(x,sy,hy,w,t,leg,s->capture_ms);
        else fruit(s);
    } else have_capture=0;
    return 1;
}
int control_poll(control_frame_t *out) {
    if (!out) return 0;
    *out=frame;
    int result=(int)unread; unread=0;
    frame.actions.event_seq=0; frame.actions.move=CONTROL_MOVE_NONE;
    for(unsigned i=0;i<2;i++) frame.hand[i].segment_valid=0;
    return result;
}
int pose_input_view(control_pose_snapshot_t *out,uint32_t now_ms,uint32_t max_age_ms) {
    if (!out || !view_ok || !session || view.session_epoch!=session ||
        now_ms-view.capture_ms>=max_age_ms) return 0;
    *out=view; return 1;
}
uint32_t pose_input_state(void) {
    return (frame.pose_valid?POSE_INPUT_BODY:0u) |
        (calibrated?POSE_INPUT_CALIBRATED:0u) | (armed?POSE_INPUT_ARMED:0u) |
        (candidate?POSE_INPUT_MOVE_PENDING:0u) | (frame.actions.duck_held?POSE_INPUT_DUCK:0u) |
        (duck_candidate?POSE_INPUT_DUCK_PENDING:0u) | (zone?POSE_INPUT_ZONE:0u);
}
void pose_input_set_lane_zones(uint32_t on) {
    if (!configured) { pose_input_defaults(&c); game=CONTROL_GAME_SUBWAY; configured=1; }
    c.lane_zones=on?1u:0u; break_motion();
}
uint32_t pose_input_lane_zones(void) { return configured ? c.lane_zones : POSE_SUBWAY_ZONES; }
uint32_t pose_input_zone(void) { return zone; }
