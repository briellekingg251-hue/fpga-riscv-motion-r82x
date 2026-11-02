#ifndef FN_POSE_MMIO_SOURCE_H
#define FN_POSE_MMIO_SOURCE_H
#include "pose_service.h"
/* Single CPU owner; initialize/reset together with hardware session reset.
 * Exposes decoded detector continuity to the game policy (not biometrics).
 * now_ms must use pose_mmio_now(), the SAME
 * hardware clock as capture_ms (not an independently phased CPU ms clock).
 */
typedef struct {
    uint32_t held, count, bank, det_held, det_count, det_bank, det_word;
    uint32_t det_seen, lost, roi_pending, max_units;
    uint32_t det_capture_ms,det_errors,det_late,det_skipped;
    uint32_t det_frame,det_result_frame,det_result_ms,det_result_valid,det_breaks,det_have_result;
    uint32_t det_ambiguous;  /* frames with a second strong peak (diagnostic only) */
    /* FLAGS bits 1..6 are STICKY hardware events (crop overrun, camera FIFO
     * overflow, detector overflow/short frame, net errors) until AI reset.
     * A result is rejected only when a bit is NEW since that consumer's last
     * check; one glitch (e.g. the half frame after reset) cannot disable
     * recognition for the rest of the session. */
    uint32_t det_flag_seen,pose_flag_seen;
    int have_box;
    int8_t heat[60], box[60][4];
    p2_box smooth;
    p2_box raw_box;
    p2_roi roi;
} pose_mmio_source_t;
void pose_mmio_source_init(pose_mmio_source_t *, pose_service_source_t *);
uint32_t pose_mmio_now(void);
/* Each unit is one word, state transition, fixed 60-cell decode or fixed ROI
 * arithmetic. No whole-frame polling. Pending ROI commit returns immediately.
 * Call alongside pose_service_step; shared owner only, PAL must disable both.
 */
uint32_t pose_mmio_det_step(pose_mmio_source_t *, uint32_t budget);
void pose_mmio_cancel(pose_mmio_source_t *);
int pose_mmio_stop_step(pose_mmio_source_t *);
#endif
