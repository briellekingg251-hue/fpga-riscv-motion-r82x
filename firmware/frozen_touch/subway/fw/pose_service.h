#ifndef FN_POSE_SERVICE_H
#define FN_POSE_SERVICE_H
#include <stdint.h>
#include "control.h"
#include "p2_algo.h"
#define POSE_SERVICE_MAX_BUDGET 64u
#define POSE_SERVICE_RAM 0x4000u
#define POSE_SERVICE_WORDS 1944u
#define POSE_SERVICE_HW_ERROR_MASK 0xfeu /* V_FLAGS bit0 is ROI armed, NOT error */
/* SAME original 12-joint order: L/R shoulder, elbow, wrist, hip, knee, ankle.
 * No person authentication is made by this module. Game policy supplies the
 * single-player continuity gate and track_epoch. No joint post filter here.
 * All callbacks are bounded, nonblocking, single CPU; no ISR concurrency.
 */
typedef struct {
    uint32_t pose_count, frame_id, bank, capture_ms, timestamp_valid;
    uint32_t flags; /* raw V_FLAGS; armed bit0 allowed, all other bits rejected */
    p2_roi roi;
} pose_service_result_t;
typedef struct {
    void *ctx;
    /* Required: actually reserve completed bank against AI writes. Metadata/ROI
     * belongs to that bank. 1 acquired, 0 no completed result, -1 source failure.
     * Acquiring may return the same count; service releases without republishing.
     * task16/task17 MMIO implements this lease; pose_mmio_source is its adapter.
     */
    int (*acquire)(void *, pose_service_result_t *);
    /* Read exactly one aligned MMIO word while lease holds: 1 ready, 0 retry,
     * -1 error. Must not access a writer-owned bank. Timeout handled by step.
     */
    int (*read_word)(void *, uint32_t offset, uint32_t *);
    /* 1 lease/data still immutable, 0 revoked. Must detect partial overwrite. */
    int (*validate)(void *, const pose_service_result_t *);
    void (*release)(void *);
    /* 1 counters ready, 0 retry, -1 failure; source counters from +004/+010.
     * hardware_drop is optional supplied evidence, never inferred from camera.
     */
    int (*counters)(void *, uint32_t *captured, uint32_t *completed, uint32_t *hardware_drop);
} pose_service_source_t;
typedef struct {
    uint32_t captured, completed, hardware_dropped;
    uint32_t dropped, published, late, missing_frame, source_errors;
    uint32_t latest_age_ms, latest_age_valid, last_step_units;
} pose_service_stats_t;
typedef enum { PS_IDLE, PS_ACQUIRE, PS_READ, PS_VERIFY, PS_SCAN, PS_JOINT, PS_PUBLISH } pose_service_state_t;
typedef struct {
    pose_service_source_t io;
    pose_service_state_t state;
    pose_service_result_t job;
    pose_service_stats_t stats;
    control_pose_snapshot_t latest, building;
    uint32_t session_epoch, track_epoch, max_age_ms, timeout_ms;
    uint32_t lease, start_ms, word, pixel, joint, best[12];
    uint32_t seen_count, seen_valid, last_frame, last_frame_valid, publication, taken;
    uint32_t count_valid, camera_base, pose_base, drop_base;
    int8_t heat[216][12], off[216][24];
} pose_service_t;
/* Mandatory source functions; nonzero session; 0 < age/timeout < 2^31 ms.
 * track_epoch is supplied by integration policy, never inferred as identity.
 */
int pose_service_init(pose_service_t *, const pose_service_source_t *, uint32_t session_epoch,
                      uint32_t track_epoch, uint32_t max_age_ms, uint32_t timeout_ms);
/* Reset releases any lease and synchronously discards publication/session state. */
void pose_service_reset(pose_service_t *, uint32_t session_epoch, uint32_t track_epoch);
/* At most min(budget,64) units. Unit is one state transition: at most two
 * bounded callbacks (acquire/validate plus release), or one word, one pixel's
 * 12 comparisons, one joint's fixed arithmetic, or fixed-size snapshot commit.
 * No wait for a frame; a read retry returns immediately. This is a WORK budget,
 * not a measured CPU deadline. Caller clock must be monotonic wrapping ms.
 */
uint32_t pose_service_step(pose_service_t *, uint32_t now_ms, uint32_t budget);
/* Latest mailbox; one take per publication seq. Caller must manage task50 -2
 * mailbox backpressure and tick independently even with no new snapshot.
 */
int pose_service_take(pose_service_t *, control_pose_snapshot_t *);
#endif
