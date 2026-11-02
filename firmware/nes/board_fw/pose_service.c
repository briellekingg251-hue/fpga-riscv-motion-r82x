#include "pose_service.h"
#include "p2_model.h"
#include <string.h>

static int forward(uint32_t a, uint32_t b) { uint32_t d=a-b; return d && d<0x80000000u; }
static void release_bank(pose_service_t *s) {
    if(s->lease) { s->io.release(s->io.ctx); s->lease=0; }
}
static void drop(pose_service_t *s) {
    release_bank(s); s->stats.dropped++; s->state=PS_IDLE;
}
int pose_service_init(pose_service_t *s, const pose_service_source_t *io, uint32_t epoch,
                      uint32_t track, uint32_t age, uint32_t timeout) {
    if(!s || !io || !io->acquire || !io->read_word || !io->validate || !io->release ||
       !io->counters || !epoch || !age || age>=0x80000000u || !timeout || timeout>=0x80000000u) return 0;
    memset(s,0,sizeof(*s)); s->io=*io; s->session_epoch=epoch; s->track_epoch=track;
    s->max_age_ms=age; s->timeout_ms=timeout; return 1;
}
void pose_service_reset(pose_service_t *s, uint32_t epoch, uint32_t track) {
    pose_service_source_t io=s->io; uint32_t age=s->max_age_ms, timeout=s->timeout_ms;
    release_bank(s);
    memset(s,0,sizeof(*s)); s->io=io; s->session_epoch=epoch; s->track_epoch=track;
    s->max_age_ms=age; s->timeout_ms=timeout;
}
static void counters(pose_service_t *s, uint32_t c, uint32_t p, uint32_t d) {
    if(s->count_valid) {
        uint32_t dc=c-s->camera_base, dp=p-s->pose_base, dd=d-s->drop_base;
        if(dc<0x80000000u && dp<0x80000000u && dd<0x80000000u) {
            s->stats.captured+=dc; s->stats.completed+=dp; s->stats.hardware_dropped+=dd;
        } else s->stats.source_errors++; /* hardware reset requires service_reset */
    }
    s->count_valid=1; s->camera_base=c; s->pose_base=p; s->drop_base=d;
}
static void unpack_word(pose_service_t *s, uint32_t v) {
    uint32_t n=s->word*4u;
    for(uint32_t b=0;b<4u;b++) {
        uint32_t byte=(v>>(8u*b))&255u;
        int8_t q=(int8_t)(byte<128u?(int32_t)byte:(int32_t)byte-256);
        uint32_t i=n+b;
        if(i<2592u) s->heat[i/12u][i%12u]=q;
        else { i-=2592u; s->off[i/24u][i%24u]=q; }
    }
}
/* Extracted arithmetic from read-only p2_pose_decode; tests compare every joint
 * against its unchanged whole-frame implementation, including first-index ties.
 */
static void decode_joint(pose_service_t *s) {
    uint32_t j=s->joint, p=s->best[j];
    int32_t y=(int32_t)(p/12u)*16*256+1920+(int32_t)s->off[p][j]*128;
    int32_t x=(int32_t)(p%12u)*16*256+1920+(int32_t)s->off[p][j+12u]*128;
    int32_t xq=(int32_t)(((int64_t)s->job.roi.x0_q16+(((int64_t)x*s->job.roi.step_q16)>>8))>>8);
    int32_t yq=(int32_t)(((int64_t)s->job.roi.y0_q16+(((int64_t)y*s->job.roi.step_q16)>>8))>>8);
    int32_t xp=(xq+128)>>8, yp=(yq+128)>>8;
    control_joint_t *k=&s->building.joint[j];
    k->logit=s->heat[p][j];
    /* Preserve original CPUdecode semantics: validity is raw logit only.
     * pose_input owns camera-bounds/body rejection, not the decode producer.
     * The validated ROI range above keeps rounded coordinates in int16. */
    k->valid=(uint32_t)(k->logit>=P2_KP_T_Q);
    k->x=(int16_t)xp; k->y=(int16_t)yp;
}
uint32_t pose_service_step(pose_service_t *s, uint32_t now, uint32_t budget) {
    uint32_t used=0;
    if(budget>POSE_SERVICE_MAX_BUDGET) budget=POSE_SERVICE_MAX_BUDGET;
    s->stats.last_step_units=0;
    if(!s->session_epoch) return 0;
    if(s->publication) { s->stats.latest_age_valid=1; s->stats.latest_age_ms=now-s->latest.capture_ms; }
    if(s->state>=PS_READ && ((uint32_t)(now-s->start_ms)>s->timeout_ms ||
                            (uint32_t)(now-s->job.capture_ms)>s->max_age_ms)) {
        if(!budget) return 0;
        s->stats.late++; drop(s); s->stats.last_step_units=1; return 1;
    }
    while(used<budget) {
        int rc; used++;
        switch(s->state) {
        case PS_IDLE: {
            uint32_t c,p,d;
            rc=s->io.counters(s->io.ctx,&c,&p,&d);
            if(rc<=0) { if(rc<0) s->stats.source_errors++; goto done; }
            counters(s,c,p,d); s->state=PS_ACQUIRE; break;
        }
        case PS_ACQUIRE:
            rc=s->io.acquire(s->io.ctx,&s->job);
            if(rc<=0) { if(rc<0) s->stats.source_errors++; s->state=PS_IDLE; goto done; }
            s->lease=1;
            if(s->seen_valid && !forward(s->job.pose_count,s->seen_count)) {
                /* A replay/reordering cannot reconnect an application's track. */
                s->stats.source_errors++;
                release_bank(s); s->state=PS_IDLE; goto done;
            }
            if(s->seen_valid) s->stats.dropped+=s->job.pose_count-s->seen_count-1u;
            s->seen_count=s->job.pose_count; s->seen_valid=1;
            if(s->job.timestamp_valid && (uint32_t)(now-s->job.capture_ms)>s->max_age_ms) {
                s->stats.late++; drop(s); goto done;
            }
            if(s->job.bank>1u || s->job.frame_id>0x7fffffffu || !s->job.timestamp_valid ||
               (s->last_frame_valid && (((s->job.frame_id-s->last_frame)&0x7fffffffu)==0 ||
                 ((s->job.frame_id-s->last_frame)&0x7fffffffu)>=0x40000000u)) ||
               (s->publication && !forward(s->job.capture_ms,s->latest.capture_ms))) {
                s->stats.missing_frame++; drop(s); goto done;
            }
            // Reject corrupt/unbounded ROI math; normal crop step <= 10 camera px.
            if((s->job.flags & ~1u) || !s->job.roi.step_q16 || s->job.roi.step_q16>16u*65536u ||
               s->job.roi.x0_q16 < -4096*65536 || s->job.roi.x0_q16 > 4096*65536 ||
               s->job.roi.y0_q16 < -4096*65536 || s->job.roi.y0_q16 > 4096*65536) {
                s->stats.source_errors++; drop(s); goto done;
            }
            s->start_ms=now; s->word=0; s->state=PS_READ; break;
        case PS_READ: {
            uint32_t v;
            rc=s->io.read_word(s->io.ctx,POSE_SERVICE_RAM+s->job.bank*0x2000u+s->word*4u,&v);
            if(rc<=0) { if(rc<0) { s->stats.source_errors++; drop(s); } goto done; }
            unpack_word(s,v); s->word++;
            if(s->word==POSE_SERVICE_WORDS) s->state=PS_VERIFY;
            break;
        }
        case PS_VERIFY:
            rc=s->io.validate(s->io.ctx,&s->job);
            release_bank(s);
            if(rc!=1) { s->stats.source_errors++; drop(s); goto done; }
            memset(&s->building,0,sizeof(s->building));
            memset(s->best,0,sizeof(s->best)); s->pixel=1; s->state=PS_SCAN; break;
        case PS_SCAN:
            for(uint32_t j=0;j<12u;j++)
                if(s->heat[s->pixel][j]>s->heat[s->best[j]][j]) s->best[j]=s->pixel;
            if(++s->pixel==216u) { s->joint=0; s->state=PS_JOINT; }
            break;
        case PS_JOINT:
            decode_joint(s);
            if(++s->joint==12u) s->state=PS_PUBLISH;
            break;
        case PS_PUBLISH:
            if(++s->publication==0) s->publication=1;
            s->building.seq=s->publication; s->building.session_epoch=s->session_epoch;
            s->building.track_epoch=s->track_epoch; s->building.capture_frame_id=s->job.frame_id;
            s->building.capture_ms=s->job.capture_ms; s->building.complete_ms=now;
            s->building.flags=CONTROL_POSE_VALID;
            s->latest=s->building; s->stats.published++;
            s->last_frame=s->job.frame_id; s->last_frame_valid=1;
            s->stats.latest_age_ms=now-s->job.capture_ms; s->stats.latest_age_valid=1;
            s->state=PS_IDLE; goto done;
        }
    }
done: s->stats.last_step_units=used; return used;
}
int pose_service_take(pose_service_t *s, control_pose_snapshot_t *out) {
    if(!out || !s->publication || s->taken==s->publication) return 0;
    *out=s->latest; s->taken=s->publication; return 1;
}
