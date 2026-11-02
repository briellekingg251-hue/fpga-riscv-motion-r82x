#ifndef FN_POSE_INPUT_H
#define FN_POSE_INPUT_H
#include "control.h"

/* Verified model layers.json order and p2_algo.c p2_edges (12 joints). */
enum { POSE_L_SHOULDER=0, POSE_R_SHOULDER=1, POSE_L_ELBOW=2,
       POSE_R_ELBOW=3, POSE_L_WRIST=4, POSE_R_WRIST=5, POSE_L_HIP=6,
       POSE_R_HIP=7, POSE_L_KNEE=8, POSE_R_KNEE=9,
       POSE_L_ANKLE=10, POSE_R_ANKLE=11 };

/* Fractions use Q8, filter beta Q16 /(camera pixel/s), cutoff Q8 Hz.
 * Defaults are synthetic-test starting points, not human/board acceptance.
 * Contract dimensions: camera 1280x720, output framebuffer 512x300. Config
 * dimension fields document the binding; incompatible dimensions are rejected.
 * mirror_move maps increasing camera x to LEFT when 1, RIGHT when 0.
 * mirror_blade and blade_gain_q8 apply about the framebuffer center. */
typedef struct {
    uint32_t stale_ms, stable_ms, debounce_ms, cooldown_ms;
    int32_t min_logit, min_width_px, min_torso_px;
    uint32_t step_q8, release_q8, stable_q8, scale_tolerance_q8;
    uint32_t duck_enter_q8, duck_exit_q8, knee_compress_q8;
    uint32_t mirror_move, mirror_blade, blade_gain_q8;
    uint32_t framebuffer_w, framebuffer_h;
    uint32_t blade_jump_px, blade_speed_px_s;
    int32_t min_cutoff_q8, beta_q16;
    /* Subway lane mode: 0 relative step (mature), 1 absolute thirds of the
     * camera width (PiP zones) with hysteresis and dwell. */
    uint32_t lane_zones, zone_hyst_q8, zone_dwell_ms;
} pose_input_config_t;

void pose_input_defaults(pose_input_config_t *cfg);
/* Supported POSE games only. Invalid config leaves prior state untouched.
 * Configure before control_reset(session). Single CPU, no interrupt/thread use. */
int pose_input_configure(const pose_input_config_t *cfg, uint32_t game_id);
/* identity_confirmed is an application gate, not biometric authentication.
 * In the single-player production game it means a fresh selected
 * detector ROI + plausible body + continuous frame/ROI/body trajectory.
 * Bump track_epoch and break anchors on observable loss, gaps or jumps. A top-1 result
 * alone is insufficient; indistinguishable people replacing one another at the
 * same location cannot be identified by these tensors. 0 fails closed.
 * Returns 1 committed, 0 duplicate/out-of-order/wrong session, -1 bad pointer,
 * -2 unread mailbox: poll first and retry the same snapshot with current now_ms.
 * Safety-invalid or track-reset snapshots supersede unread actions.
 * seq is monotonic across track epochs,
 * modulo 2^32, with 0 reserved, <2^31 publication distance. */
int pose_input_submit(const control_pose_snapshot_t *snapshot,
                      uint32_t now_ms, uint32_t identity_confirmed);
/* Required even without new inference, before every control_poll. Unsigned
 * wrapping ms; intervals must be <2^31 ms. Timeout clears held/segments now.
 * poll ALWAYS fills state, even returning 0; only return 1 authorizes one
 * event/segment consumption. Repeated polls have move/segments cleared. */
void pose_input_tick(uint32_t now_ms);
/* Display/UI only (skeleton panel, menu cursors): copies the latest committed
 * snapshot that passed identity, freshness and body checks while it is younger
 * than max_age_ms. Never a source of hits, lane events or duck state. Cleared
 * by control_reset and by any rejected/lost snapshot. Returns 1 when copied. */
int pose_input_view(control_pose_snapshot_t *out, uint32_t now_ms, uint32_t max_age_ms);
/* Read-only UART diagnostics: no event polling or motion-state mutation. */
enum { POSE_INPUT_BODY=1u, POSE_INPUT_CALIBRATED=2u, POSE_INPUT_ARMED=4u,
       POSE_INPUT_MOVE_PENDING=8u, POSE_INPUT_DUCK=16u, POSE_INPUT_DUCK_PENDING=32u,
       POSE_INPUT_ZONE=64u };
uint32_t pose_input_state(void);
/* Lane mode switch (Subway pause menu). Clears motion state. */
void pose_input_set_lane_zones(uint32_t on);
uint32_t pose_input_lane_zones(void);
/* Committed zone in mode B: 0 none, 1..3 left/middle/right. */
uint32_t pose_input_zone(void);
#endif
