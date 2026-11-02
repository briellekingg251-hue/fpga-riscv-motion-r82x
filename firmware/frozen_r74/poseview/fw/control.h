/* Frozen control contract v1. No joint-index/17-point assumptions. */
#ifndef FN_CONTROL_H
#define FN_CONTROL_H
#include <stdint.h>
#define CONTROL_CONTRACT_VERSION 1u
#define CONTROL_POSE_JOINTS 12u
#define CONTROL_GAME_FRUIT 0x46525549u
#define CONTROL_GAME_SUBWAY 0x53554257u
#define CONTROL_GAME_PAL 0x50414c31u
#define CONTROL_GAME_DOOM 0x444f4f4du
#define CONTROL_GAME_SLUG 0x534c5547u
#define CONTROL_GAME_VIEW 0x50564945u
#define CONTROL_CAP_TOUCH 1u
#define CONTROL_CAP_POSE 2u
typedef enum { CONTROL_TOUCH=0, CONTROL_POSE=1 } control_mode_t;
/* Share the catalog lookup instead of cloning it at each menu/load gate.
 * This lookup runs only while selecting/loading a game, outside game loops. */
static __attribute__((noinline)) uint32_t control_game_caps(uint32_t id) {
    if(id==CONTROL_GAME_FRUIT || id==CONTROL_GAME_SUBWAY || id==CONTROL_GAME_VIEW)
        return CONTROL_CAP_TOUCH|CONTROL_CAP_POSE;
    if(id==CONTROL_GAME_PAL || id==CONTROL_GAME_DOOM || id==CONTROL_GAME_SLUG)return CONTROL_CAP_TOUCH;
    return 0;
}
static inline int control_game_allowed(uint32_t mode,uint32_t id) {
    return mode<=CONTROL_POSE && (control_game_caps(id)&(1u<<mode))!=0;
}
/* All timestamps: wrapping monotonic milliseconds, unsigned delta comparisons.
 * seq is publication identity (0 reserved), not camera/display FPS. Single CPU
 * producer commits complete snapshots after verifying AI bank consistency.
 * x/y: original 1280x720 camera pixels. logit: CPUdecode raw signed score,
 * not probability. Joint indices remain the original 12-joint model layout. */
typedef struct { int16_t x,y; int32_t logit; uint32_t valid; } control_joint_t;
#define CONTROL_POSE_VALID 1u
#define CONTROL_POSE_TRACK_RESET 2u
#define CONTROL_POSE_ERROR 4u
typedef struct {
    uint32_t seq,session_epoch,track_epoch,capture_frame_id;
    uint32_t capture_ms,complete_ms,flags;
    control_joint_t joint[CONTROL_POSE_JOINTS];
} control_pose_snapshot_t;
typedef enum { CONTROL_MOVE_NONE=0, CONTROL_MOVE_LEFT=1,
               CONTROL_MOVE_RIGHT=2 } control_move_t;
/* event_seq=0 means no lateral event; nonzero identities wrap, compare equality.
 * At most one lateral event per output seq; poll consumes it even if a wall
 * blocks it. duck_held is level state, released on loss/reset. Games may refresh
 * the original duck timer while held; never replay DOWN events each frame. */
typedef struct { uint32_t event_seq,move,duck_held; } control_actions_t;
/* hand[0/1]: left/right wrists mapped by backend, not model joint indices.
 * Latest valid point follows immediately in framebuffer 512x300 coordinates.
 * segment_valid permits ONE collision segment x0/y0 -> x/y. First point after
 * loss/timeout/new track/session/identity change/jump: point_valid=1,
 * segment_valid=0. Display interpolation never creates collision segments.
 * Invalid points carry no usable coordinates. */
typedef struct {
    int16_t x,y,x0,y0;
    uint32_t point_valid,segment_valid;
} control_blade_t;
typedef struct {
    uint32_t seq,session_epoch,track_epoch,capture_ms,complete_ms,pose_valid;
    control_actions_t actions;
    control_blade_t hand[2];
} control_frame_t;
/* Implemented ONLY by pose/control backend owner, not loader.
 * reset synchronously clears events, held state, calibration and blade anchors.
 * poll consumes discrete events/segments: 1 once per committed seq, 0 otherwise.
 * It always fills out. On return 0: move=NONE, event_seq=0, segment_valid=0;
 * held/latest-point levels may persist only while the source is still fresh.
 * Stale/loss/error MUST publish invalid/held=0/broken output. Game reads modeinfo
 * on entry and calls reset(session_epoch) before polling. UI uses app_input_t.
 */
void control_reset(uint32_t session_epoch);
int control_poll(control_frame_t *out);
#endif
