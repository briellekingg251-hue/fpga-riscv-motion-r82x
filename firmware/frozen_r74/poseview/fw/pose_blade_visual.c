#include "pose_blade_visual.h"
void pose_blade_visual_advance(pose_blade_visual_t *v,uint32_t now)
{
    uint32_t elapsed=now-v->start_ms;
    if(!v->active)return;
    if(!v->duration_ms || elapsed>=v->duration_ms) {
        v->xq=v->target_xq;v->yq=v->target_yq;return;
    }
    /* Q8 endpoints preserve subpixel motion, with no extrapolation/overshoot. */
    v->xq=v->from_xq+(v->target_xq-v->from_xq)*(int32_t)elapsed/(int32_t)v->duration_ms;
    v->yq=v->from_yq+(v->target_yq-v->from_yq)*(int32_t)elapsed/(int32_t)v->duration_ms;
}
void pose_blade_visual_sample(pose_blade_visual_t *v,int x,int y,
                              uint32_t capture,uint32_t now,int continuous)
{
    uint32_t dt=capture-v->capture_ms;
    int32_t tx=(int32_t)x*256,ty=(int32_t)y*256;
    if(!v->active || !continuous || dt>180u) {
        *v=(pose_blade_visual_t){.xq=tx,.yq=ty,.from_xq=tx,.from_yq=ty,
          .target_xq=tx,.target_yq=ty,.start_ms=now,.capture_ms=capture,.active=1};return;
    }
    pose_blade_visual_advance(v,now);
    int32_t dx=(tx-v->xq)/256,dy=(ty-v->yq)/256;
    uint32_t distance=(uint32_t)(dx<0?-dx:dx)+(uint32_t)(dy<0?-dy:dy);
    uint32_t duration=(dt?dt:33u)*24u/(distance+24u);
    if(duration<8u)duration=8u;
    if(duration>48u)duration=48u;
    v->from_xq=v->xq;v->from_yq=v->yq;v->target_xq=tx;v->target_yq=ty;
    v->start_ms=now;v->duration_ms=duration;v->capture_ms=capture;
}
