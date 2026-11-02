#include "game_pose_service.h"
#include "pose_mmio_source.h"
#include "pose_input.h"
#include <string.h>
#include "soc.h"
#include "p2_model.h"
#ifndef POSE_MMIO_REG
#define POSE_MMIO_REG(o) (*(volatile uint32_t *)(uintptr_t)(0x10008000u+(o)))
#endif
static uint32_t display_seq,display_track,display_visible;
/* Shared HDMI/LCD publication. Control keeps its original coordinates and gates.
 * A busy postprocessor is retried by the next service iteration, never waited on. */
static void display_pose(uint32_t now,int enable) {
    control_pose_snapshot_t v;
    int visible=enable && pose_input_view(&v,now,180u);
    if(POSE_MMIO_REG(0x064)&1u)return;
    if(!visible && !display_visible)return;
    if(visible && display_visible && v.seq==display_seq)return;
    for(unsigned j=0;j<12;j++) {
        uint32_t word=0;
        if(visible && v.joint[j].valid && v.joint[j].x>=0 && v.joint[j].x<1280 && v.joint[j].y>=0 && v.joint[j].y<720)
            word=0x80000000u|((uint32_t)v.joint[j].y<<20)|((uint32_t)v.joint[j].x<<4);
        POSE_MMIO_REG(0x300+4*j)=word;
    }
    POSE_MMIO_REG(0x04c)=0; /* Box is optional; do not show an unconfirmed ROI. */
    POSE_MMIO_REG(0x060)=(!visible || !display_visible || v.track_epoch!=display_track)?1u:0u;
    display_visible=(uint32_t)visible;
    if(visible){display_seq=v.seq;display_track=v.track_epoch;}
}
static pose_mmio_source_t source;
static pose_service_t service;
static control_pose_snapshot_t pending;
static uint32_t epoch, capture_floor,game_id;
static int active, have_pending, stopping;
static uint32_t gpu_write_budget;
static struct {
    uint32_t confirmed,track_epoch,have_seq,last_seq,last_frame,last_count,last_capture;
    uint32_t det_breaks,pose_faults,pending_checked,pending_identity,rejections,last_reject;
    int32_t x,y,width,torso;
    p2_roi roi;
} trajectory;
static int forward_ms(uint32_t a,uint32_t b) { uint32_t d=a-b;return d && d<0x80000000u; }
static int32_t distance32(int32_t a) { return a<0?-a:a; }
enum { TRACK_REJECT_AGE=1u, TRACK_REJECT_BODY=2u, TRACK_REJECT_KNEES=4u,
       TRACK_REJECT_GEOMETRY=8u, TRACK_REJECT_CONTINUITY=16u,
       TRACK_REJECT_DETECTOR=32u, TRACK_REJECT_SOURCE=64u };
static void break_track(uint32_t floor,uint32_t reason) {
    if(forward_ms(floor,capture_floor))capture_floor=floor;
    trajectory.confirmed=0;
    trajectory.last_reject=reason;++trajectory.rejections;
    /* Clears mailbox, held duck and both wrist anchors synchronously. Runtime
     * retains accepted hardware/seq history; replay cannot establish a track. */
    control_reset(epoch);display_pose(pose_mmio_now(),0);
}
static uint32_t pose_faults(void) {
    return service.stats.dropped+service.stats.late+service.stats.missing_frame+service.stats.source_errors;
}
static int joint_ok(const control_pose_snapshot_t *s,unsigned j) {
    const control_joint_t *p=&s->joint[j];
    return p->valid && p->logit>=-6 && p->x>=0 && p->x<1280 && p->y>=0 && p->y<720;
}
/* Small single-player policy from the actual leased ROI, detector and decoded
 * shoulders/hips. No face/person identity or unseen people count is asserted.
 * First valid observation of a new epoch is an anchor, never a motion segment. */
static int confirm_track(control_pose_snapshot_t *s,uint32_t count,const p2_roi *roi,uint32_t now) {
    if(trajectory.have_seq && !forward_ms(s->seq,trajectory.last_seq))return 0;
    if(!forward_ms(s->capture_ms,capture_floor) || now-s->capture_ms>=180u ||
       !source.det_result_valid || now-source.det_result_ms>=180u ||
       !forward_ms(source.det_result_ms,capture_floor)) {
        break_track(s->capture_ms,TRACK_REJECT_AGE);return 0;
    }
    if(!joint_ok(s,0) || !joint_ok(s,1) || !joint_ok(s,6) || !joint_ok(s,7)) {
        break_track(s->capture_ms,TRACK_REJECT_BODY);return 0;
    }
    const control_joint_t *p=s->joint;
    if(game_id==CONTROL_GAME_SUBWAY && (!joint_ok(s,8) || !joint_ok(s,9) ||
       p[8].y<=p[6].y || p[9].y<=p[7].y ||
       distance32((p[8].y-p[6].y)-(p[9].y-p[7].y))>((p[6].y+p[7].y-p[0].y-p[1].y)/4))) {
        break_track(s->capture_ms,TRACK_REJECT_KNEES);return 0;
    }
    int32_t sx=(p[0].x+p[1].x)/2,hx=(p[6].x+p[7].x)/2;
    int32_t sy=(p[0].y+p[1].y)/2,hy=(p[6].y+p[7].y)/2;
    int32_t x=(sx+hx)/2,y=(sy+hy)/2,w=distance32(p[0].x-p[1].x),t=hy-sy;
    int32_t hw=distance32(p[6].x-p[7].x);
    int32_t rx=roi->x0_q16/65536,ry=roi->y0_q16/65536;
    int32_t rw=(int32_t)(((uint64_t)roi->step_q16*192u)>>16);
    int32_t rh=(int32_t)(((uint64_t)roi->step_q16*288u)>>16);
    const p2_box *b=&source.raw_box;
    int32_t margin=(b->x1-b->x0)/1024+8;
    if(w<32 || t<45 || hw<w/3 || hw>w*2 || distance32(sx-hx)>t/3 ||
       distance32(p[0].y-p[1].y)>t/3 || distance32(p[6].y-p[7].y)>t/3 ||
       x<rx || x>rx+rw || y<ry || y>ry+rh ||
       x<b->x0/256-margin || x>b->x1/256+margin ||
       y<b->y0/256-margin || y>b->y1/256+margin) {
        break_track(s->capture_ms,TRACK_REJECT_GEOMETRY);return 0;
    }
    if(trajectory.confirmed) {
        uint32_t dt=s->capture_ms-trajectory.last_capture;
        int32_t oldw=(int32_t)(((uint64_t)trajectory.roi.step_q16*192u)>>16);
        int32_t cx=rx+rw/2,cy=ry+rh/2;
        int32_t oldcx=trajectory.roi.x0_q16/65536+oldw/2;
        int32_t oldh=(int32_t)(((uint64_t)trajectory.roi.step_q16*288u)>>16);
        int32_t oldcy=trajectory.roi.y0_q16/65536+oldh/2;
        int32_t move=trajectory.width*3/4+32+(int32_t)dt*2;
        if(count-trajectory.last_count!=1u ||
           ((s->capture_frame_id-trajectory.last_frame)&0x7fffffffu)!=1u ||
           !forward_ms(s->capture_ms,trajectory.last_capture) || dt>=180u ||
           distance32(x-trajectory.x)>move || distance32(y-trajectory.y)>move ||
           distance32(w-trajectory.width)>trajectory.width/4 ||
           distance32(t-trajectory.torso)>trajectory.torso/4 ||
           distance32(rw-oldw)>oldw/4+4 || distance32(cx-oldcx)>oldw/2+32+(int32_t)dt*2 ||
           distance32(cy-oldcy)>oldh/2+32+(int32_t)dt*2) {
            /* Current fresh body may seed a new track; it cannot replay the
             * prior lane/calibration or form a blade across the discontinuity. */
            break_track(trajectory.last_capture,TRACK_REJECT_CONTINUITY);
        }
    }
    if(!trajectory.confirmed) {
        if(++trajectory.track_epoch==0)++trajectory.track_epoch;
        trajectory.confirmed=1;s->flags|=CONTROL_POSE_TRACK_RESET;
    }
    service.track_epoch=trajectory.track_epoch;s->track_epoch=trajectory.track_epoch;
    trajectory.have_seq=1;trajectory.last_seq=s->seq;trajectory.last_frame=s->capture_frame_id;
    trajectory.last_count=count;trajectory.last_capture=s->capture_ms;
    trajectory.x=x;trajectory.y=y;trajectory.width=w;trajectory.torso=t;trajectory.roi=*roi;
    return 1;
}
uint32_t game_pose_now(void) { return pose_mmio_now(); }
void game_pose_start(uint32_t session,uint32_t id) {
    POSE_MMIO_REG(0x058)=1;
    display_seq=display_track=0;display_visible=1;display_pose(game_pose_now(),0);
    pose_service_source_t io;
    pose_mmio_source_init(&source,&io);
    epoch=session;game_id=id; capture_floor=game_pose_now();
    active=pose_service_init(&service,&io,session,0,200,100);
    have_pending=stopping=0;
    gpu_write_budget=0;
    memset(&trajectory,0,sizeof trajectory);
}
void game_pose_flush(void) {
    if(!active)return;
    /* Do not rewind seq within an entry session: game/UI dedup retains it. */
    uint32_t seq=service.publication;
    pose_service_reset(&service,epoch,service.track_epoch);
    service.publication=service.taken=seq;
    memset(&service.latest,0,sizeof service.latest);
    capture_floor=game_pose_now(); have_pending=0;
    pose_mmio_cancel(&source);
    trajectory.confirmed=trajectory.pending_checked=0;display_pose(game_pose_now(),0);
    trajectory.det_breaks=source.det_breaks;trajectory.pose_faults=pose_faults();
}
void game_pose_step(void) {
    if(!active || stopping)return;
    uint32_t now=game_pose_now();
    pose_input_tick(now);display_pose(now,1);
    pose_mmio_det_step(&source,8);
    uint32_t faults=pose_faults();
    int broken=0;
    if(source.det_breaks!=trajectory.det_breaks) {
        /* A fresh re-observation may seed its own first point; older captures
         * may not survive a detector jump/gap. Invalid/error results use now. */
        break_track(source.det_result_valid?source.det_result_ms-1u:now,TRACK_REJECT_DETECTOR);broken=1;
    }
    if(faults!=trajectory.pose_faults) {
        uint32_t floor=service.state>=PS_READ && service.job.timestamp_valid?
                       service.job.capture_ms-1u:now;
        break_track(floor,TRACK_REJECT_SOURCE);broken=1;
    }
    if(trajectory.confirmed && (now-trajectory.last_capture>=180u ||
       !source.det_result_valid || now-source.det_result_ms>=180u)) {
        break_track(now,TRACK_REJECT_AGE);broken=1;
    }
    if(broken) {
        trajectory.pending_checked=0;
        if(have_pending && !forward_ms(pending.capture_ms,capture_floor))have_pending=0;
    }
    trajectory.det_breaks=source.det_breaks;trajectory.pose_faults=faults;
    if(have_pending) {
        if(!trajectory.pending_checked) {
            trajectory.pending_identity=(uint32_t)confirm_track(&pending,service.job.pose_count,&service.job.roi,now);
            trajectory.pending_checked=1;
        }
        /* -2 preserves this exact seq until the game's only poll drains it. */
        int rc=pose_input_submit(&pending,now,trajectory.pending_identity);
        if(rc==-2)return;
        have_pending=0;trajectory.pending_checked=0;display_pose(now,1);return;
    }
    pose_service_step(&service,now,64);
    if(pose_service_take(&service,&pending)) {
        uint32_t dt=pending.capture_ms-capture_floor;
        /* Entry/UI reset rejects old hardware publication, including a job
         * that was already computing when the new software session began. */
        have_pending=(dt!=0 && dt<0x80000000u);
        trajectory.pending_checked=0;
    }
}
int game_pose_stop_step(void) {
    if(!active)return 1;
    if(!stopping) {
        pose_service_reset(&service,0,service.track_epoch);
        pose_mmio_cancel(&source);
        have_pending=0; stopping=1;
    }
    /* One bounded attempt per outer-loop iteration; never wait for inference.
     * Stop returns only once ROI disable is committed and acknowledged. */
    if(!pose_mmio_stop_step(&source))return 0;
    display_pose(game_pose_now(),0);POSE_MMIO_REG(0x058)=0;
    active=stopping=0;return 1;
}

#ifndef POSE_GPU_STATUS
#define POSE_GPU_STATUS MMIO32(GPU_BASE+4u)
#endif
void game_pose_gpu_wait(void) {
    if(!active || stopping)return;
    if(gpu_write_budget) {--gpu_write_budget;return;}
    for(;;) {
        game_pose_step();
        uint32_t free_words=POSE_GPU_STATUS>>16;
        if(free_words>4u) {
            /* Status free_q is registered. Keep four words of margin and
             * refresh/service at least every 32 writes, even in long draws.
             * This CPU is the FIFO's only writer; the GPU only frees space. */
            gpu_write_budget=free_words-5u;
            if(gpu_write_budget>31u)gpu_write_budget=31u;
            return;
        }
    }
}

/* Board bring-up diagnostics (UART, about once per CPU second while POSE is
 * active). Snapshot reads never poll actions; transmission never waits.
 * cam/det/pose: hardware counters; heat: best detector cell (threshold P2_DET_T_Q);
 * brk/err/late: detector continuity breaks; pub/drop/late/miss/srcerr: pose
 * service; trk: single-player track confirmed; view: snapshot passed every gate. */
#if defined(FN_POSE_DEBUG) && FN_POSE_DEBUG
#define DBG_REG(o) POSE_MMIO_REG(o)
static uint32_t dbg_mark;
static char dbg_line[512];
static uint32_t dbg_len,dbg_pos;
static void dbg_char(char ch) { if(dbg_len<sizeof dbg_line-2u)dbg_line[dbg_len++]=ch; }
static void dbg_text(const char *s) { while(*s)dbg_char(*s++); }
static void dbg_kv(const char *k,uint32_t v) {
    char digits[10];unsigned n=0;dbg_text(k);
    do {digits[n++]=(char)('0'+v%10u);v/=10u;} while(v);
    while(n)dbg_char(digits[--n]);
}
#endif
void game_pose_debug(void) {
#if !defined(FN_POSE_DEBUG) || !FN_POSE_DEBUG
    return;
#else
    if(dbg_pos<dbg_len) {
        /* The CPU owns this UART while the game runs. A busy serializer is
         * retried next loop, with recognition serviced between every byte. */
        if(!(UART_STATUS&1u))UART_DATA=(uint32_t)(uint8_t)dbg_line[dbg_pos++];
        return;
    }
    if(!active || stopping)return;
    uint32_t now=MTIME_LO;
    if(now-dbg_mark<CPU_CLOCK_HZ)return;
    dbg_mark=now;dbg_len=dbg_pos=0;
    int best=0;for(int i=1;i<60;i++)if(source.heat[i]>source.heat[best])best=i;
    dbg_text("POSEDBG");
    dbg_kv(" ms=",DBG_REG(0x094));dbg_kv(" cam=",DBG_REG(0x004));
    dbg_kv(" det=",DBG_REG(0x008));dbg_kv(" pose=",DBG_REG(0x010));
    dbg_kv(" st=",DBG_REG(0x070));dbg_kv(" flg=",DBG_REG(0x024));
    dbg_kv(" roi=",DBG_REG(0x03C));
    dbg_kv(" heat=",(uint32_t)(source.heat[best]+128));dbg_kv("@",(uint32_t)best);
    dbg_kv(" thr=",(uint32_t)(P2_DET_T_Q+128));
    dbg_kv(" box=",(uint32_t)source.raw_box.valid);
    dbg_kv(" dres=",source.det_result_valid);dbg_kv(" brk=",source.det_breaks);dbg_kv(" amb=",source.det_ambiguous);
    dbg_kv(" derr=",source.det_errors);dbg_kv(" dlate=",source.det_late);
    dbg_kv(" pub=",service.stats.published);dbg_kv(" drop=",service.stats.dropped);
    dbg_kv(" late=",service.stats.late);dbg_kv(" miss=",service.stats.missing_frame);
    dbg_kv(" serr=",service.stats.source_errors);
    dbg_kv(" trk=",trajectory.confirmed);
    dbg_kv(" rej=",trajectory.last_reject);dbg_kv(" rejN=",trajectory.rejections);
    dbg_kv(" ctl=",pose_input_state());
    control_pose_snapshot_t v;dbg_kv(" view=",(uint32_t)pose_input_view(&v,game_pose_now(),300u));
    const control_pose_snapshot_t *l=&service.latest;
    dbg_text(" j");
    for(unsigned j=0;j<12;j++){dbg_char(l->joint[j].valid?'+':'-');}
    dbg_kv(" lg0=",(uint32_t)(l->joint[0].logit+1000));dbg_kv(" lg6=",(uint32_t)(l->joint[6].logit+1000));
    dbg_line[dbg_len++]='\r';dbg_line[dbg_len++]='\n';
#endif
}
