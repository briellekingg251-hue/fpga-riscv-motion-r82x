#include "pose_mmio_source.h"
#include <string.h>
#include "p2_model.h"
#ifndef POSE_MMIO_REG
#define POSE_MMIO_REG(o) (*(volatile uint32_t *)(uintptr_t)(0x10008000u+(o)))
#endif
#define V(o) POSE_MMIO_REG(o)
static int32_t abs32(int32_t x) { return x<0?-x:x; }
static int forward32(uint32_t a,uint32_t b) { uint32_t d=a-b;return d && d<0x80000000u; }
static void det_break(pose_mmio_source_t *s) {
    ++s->det_breaks;s->det_result_valid=0;s->have_box=0;s->lost=8;s->roi_pending=2;
}
/* Count another separated, near-score local maximum for diagnostics. This is a
 * bounded ambiguity heuristic on the actual 6x10 heat tensor, not a people counter.
 * Equal local plateaus elect their first index deterministically. */
static int ambiguous(const int8_t *heat) {
    int best=0;
    for(int i=1;i<60;i++)if(heat[i]>heat[best])best=i;
    for(int i=0;i<60;i++) {
        if(i==best || heat[i]<P2_DET_T_Q || heat[i]<(int)heat[best]-8)continue;
        int y=i/10,x=i%10,peak=1;
        if(abs32(y-best/10)<2 && abs32(x-best%10)<2)continue;
        for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++) {
            int yy=y+dy,xx=x+dx;if(yy<0 || yy>=6 || xx<0 || xx>=10)continue;
            int j=yy*10+xx;
            if(heat[j]>heat[i] || (j<i && heat[j]==heat[i]))peak=0;
        }
        if(peak)return 1;
    }
    return 0;
}
static int box_continuous(const p2_box *a,const p2_box *b,uint32_t dt) {
    int32_t aw=(a->x1-a->x0)/256,ah=(a->y1-a->y0)/256;
    int32_t bw=(b->x1-b->x0)/256,bh=(b->y1-b->y0)/256;
    int32_t dx=((a->x0+a->x1)-(b->x0+b->x1))/512;
    int32_t dy=((a->y0+a->y1)-(b->y0+b->y1))/512;
    return abs32(aw-bw)<=aw*3/8+8 && abs32(ah-bh)<=ah*3/8+8 &&
           abs32(dx)<=aw/2+24+(int32_t)dt*2 && abs32(dy)<=ah/2+24+(int32_t)dt*2;
}
uint32_t pose_mmio_now(void) { return V(0x094); }
static int acquire(void *v,pose_service_result_t *r) {
    pose_mmio_source_t *s=v;
    if(s->held) return -1;
    if(!(V(0x070)&1u)) return 0;
    V(0x074)=1;
    if(!(V(0x070)&2u)) return -1;
    s->held=1;s->count=V(0x010);s->bank=V(0x014)>>31;
    r->pose_count=s->count;r->bank=s->bank;r->frame_id=V(0x014)&0x7fffffffu;
    r->roi.x0_q16=(int32_t)V(0x018);r->roi.y0_q16=(int32_t)V(0x01c);r->roi.step_q16=V(0x020);
    r->capture_ms=V(0x084);r->timestamp_valid=(V(0x098)&2u)!=0;{uint32_t f=V(0x024);r->flags=(f&1u)|(f&0xfeu&~s->pose_flag_seen);s->pose_flag_seen|=f&0xfeu;}
    return 1;
}
static int read_word(void *v,uint32_t off,uint32_t *w) {
    pose_mmio_source_t *s=v;
    if(!s->held || off<0x4000u+s->bank*0x2000u || off>=0x4000u+s->bank*0x2000u+1957u*4u || (off&3u)) return -1;
    *w=V(off);return 1;
}
static int validate(void *v,const pose_service_result_t *r) {
    pose_mmio_source_t *s=v;
    return s->held && (V(0x070)&2u) && V(0x010)==r->pose_count && (V(0x014)>>31)==r->bank;
}
static void release(void *v) {
    pose_mmio_source_t *s=v;if(s->held) { V(0x078)=1;s->held=0; }
}
static int counters(void *v,uint32_t *c,uint32_t *p,uint32_t *d) {
    (void)v;*c=V(0x004);*p=V(0x010);*d=V(0x08c);return 1;
}
void pose_mmio_source_init(pose_mmio_source_t *s,pose_service_source_t *io) {
    memset(s,0,sizeof(*s));s->lost=8;
    /* R68: summary = keypoint summary words present (MMIO 0x098 bit 3). */
    *io=(pose_service_source_t){s,acquire,read_word,validate,release,counters,(V(0x098)&8u)!=0};
}
void pose_mmio_cancel(pose_mmio_source_t *s) {
    release(s);if(s->det_held) { V(0x080)=1;s->det_held=0; }
    s->det_word=0;s->roi_pending=0;s->have_box=0;s->lost=8;
    /* Disable only after prior commit ACK; caller continues det_step to commit. */
    s->roi_pending=2;
    s->det_result_valid=0;s->det_have_result=0;++s->det_breaks;
}
uint32_t pose_mmio_det_step(pose_mmio_source_t *s,uint32_t budget) {
    uint32_t n=0;if(budget>64)budget=64;
    while(n<budget) {
        if(s->roi_pending) {
            if(V(0x070)&16u)break;
            /* Three staging words plus commit are a fixed four MMIO accesses.
             * Hardware holds committed tuple until AI ACK; no tearing. */
            V(0x030)=(uint32_t)s->roi.x0_q16;V(0x034)=(uint32_t)s->roi.y0_q16;V(0x038)=s->roi.step_q16;
            V(0x03c)=(s->roi_pending==1u);s->roi_pending=0;++n;continue;
        }
        if(!s->det_held) {
            if(!(V(0x070)&4u))break;
            V(0x07c)=1;
            if(!(V(0x070)&8u)){++s->det_errors;det_break(s);break;}
            s->det_held=1;s->det_count=V(0x008);s->det_bank=V(0x00c)>>31;
            s->det_frame=V(0x00c)&0x7fffffffu;s->det_capture_ms=V(0x088);s->det_word=0;++n;continue;
        }
        if((uint32_t)(pose_mmio_now()-s->det_capture_ms)>200u){
            V(0x080)=1;s->det_held=0;++s->det_late;det_break(s);++n;break;
        }
        if(s->det_word<120u) {
            /* Hardware admits the next detection frame only after this lease is
             * released, and at 30 fps the window is the ~5 ms vertical blanking.
             * Copy all 120 words in one burst (~10 us) instead of budgeted chunks. */
            uint32_t a=0x1000u+s->det_bank*0x200u;
            while(s->det_word<120u) {
                uint32_t k=s->det_word++;
                if(k<60u)s->heat[k]=(int8_t)V(a+4u*k);
                else { uint32_t w=V(a+0x100u+4u*(k-60u));for(uint32_t j=0;j<4u;++j)s->box[k-60u][j]=(int8_t)(w>>(8u*j)); }
            }
            ++n;continue;
        }
        uint32_t new_flags=V(0x024)&0xfeu&~s->det_flag_seen;s->det_flag_seen|=new_flags;
        if(!(V(0x070)&8u) || V(0x008)!=s->det_count ||
           V(0x00c)!=((s->det_bank<<31)|s->det_frame) || new_flags){
            V(0x080)=1;s->det_held=0;++s->det_errors;det_break(s);++n;break;
        }
        /* Words copied and validated: release before decoding so detection can
         * admit the next frame inside the same blanking interval. */
        V(0x080)=1;s->det_held=0;
        p2_box b;p2_det_decode(s->heat,(const int8_t (*)[4])s->box,&b);
        if(s->det_have_result && (!forward32(s->det_count,s->det_seen) ||
                                 !forward32(s->det_capture_ms,s->det_result_ms))) {
            ++s->det_errors;det_break(s);++n;break; /* replay cannot reacquire */
        }
        uint32_t gap=s->det_count-s->det_seen;
        if(s->det_have_result && gap>1u && gap<0x80000000u)s->det_skipped+=gap-1u;
        /* Posefix: up to two skipped detector frames (15.6 fps, CPU lease
         * latency) keep continuity; box_continuous still catches jumps. */
        uint32_t fgap=(s->det_frame-s->det_result_frame)&0x7fffffffu;
        /* R72 62.3 fps: up to eight skipped frames, the same ~128 ms. */
        int continuity=s->det_result_valid && gap-1u<9u && fgap-1u<9u &&
            s->det_capture_ms-s->det_result_ms<300u &&
            box_continuous(&s->raw_box,&b,s->det_capture_ms-s->det_result_ms);
        /* Like the board-proven P2 firmware, take the strongest peak. A second
         * near-equal peak no longer drops the frame (with low scores that rejected
         * every frame); jumps between people are still caught by box continuity. */
        if(b.valid && ambiguous(s->heat))++s->det_ambiguous;
        if(!b.valid) {
            /* Posefix: like the board-proven standalone (LOST_LIMIT 8), keep the
             * committed ROI, box smoothing and last box through up to 7
             * consecutive frames without a person; drop them on the 8th. */
            if(s->det_result_valid && s->lost<30u) {   /* R72 62.3 fps: ~480 ms */
                ++s->lost;
                s->det_seen=s->det_count;s->det_result_ms=s->det_capture_ms;
                s->det_result_frame=s->det_frame;++n;continue;
            }
            det_break(s);
        } else {
            if(s->det_have_result && !continuity)det_break(s);
            s->det_result_valid=1;
            p2_box_smooth(&s->smooth,&s->have_box,&b,128);p2_box_to_roi(&s->smooth,&s->roi);
            s->lost=0;s->roi_pending=1;
        }
        s->raw_box=b;s->det_seen=s->det_count;s->det_result_ms=s->det_capture_ms;
        s->det_result_frame=s->det_frame;s->det_have_result=1;
        ++n;
    }
    if(n>s->max_units)s->max_units=n;
    return n;
}
int pose_mmio_stop_step(pose_mmio_source_t *s) {
    if(V(0x070)&16u)return 0;
    if(s->roi_pending) {
        V(0x03c)=0;s->roi_pending=0;return 0;
    }
    return 1;
}
