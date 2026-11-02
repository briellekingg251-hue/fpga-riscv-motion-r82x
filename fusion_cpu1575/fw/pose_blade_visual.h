#ifndef FN_POSE_BLADE_VISUAL_H
#define FN_POSE_BLADE_VISUAL_H
#include <stdint.h>
/* Display only. Never feed these interpolated points to collision detection. */
typedef struct {
    int32_t xq,yq,from_xq,from_yq,target_xq,target_yq;
    uint32_t start_ms,duration_ms,capture_ms,active;
} pose_blade_visual_t;
void pose_blade_visual_advance(pose_blade_visual_t *v,uint32_t now);
void pose_blade_visual_sample(pose_blade_visual_t *v,int x,int y,
                              uint32_t capture,uint32_t now,int continuous);
#endif
