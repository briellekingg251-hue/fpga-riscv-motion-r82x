#ifndef P2_ALGO_H
#define P2_ALGO_H
#include <stdint.h>

/* Geometry contract (HANDOFF_P2_MODEL_ADAPTATION_20261004.md sec. 4). */
#define P2_CAM_W 1280
#define P2_CAM_H 720
#define P2_CROP_W 192
#define P2_CROP_H 288
#define P2_POSE_GH 18
#define P2_POSE_GW 12
#define P2_DET_GH 6
#define P2_DET_GW 10
#define P2_NJ 12
#define P2_NSEG 12
/* Display mapping of the 1280x720 camera picture.
 * HDMI build (-DP2_HDMI): 1280x720 shown 1:1.  LCD build: 1024x576 at (0,12), i.e. x4/5. */
#ifdef P2_HDMI
#define P2_DISP_NUM 1
#define P2_DISP_DEN 1
#define P2_LCD_Y0 0
#else
#define P2_DISP_NUM 4
#define P2_DISP_DEN 5
#define P2_LCD_Y0 12
#endif

typedef struct { int32_t x0, y0, x1, y1; int32_t score_q; int valid; } p2_box;   /* camera px, Q8 */
typedef struct { int32_t x0_q16, y0_q16; uint32_t step_q16; } p2_roi;
typedef struct { int32_t x_q8, y_q8; int32_t logit_q; int valid; } p2_kp;         /* camera px, Q8 */
typedef struct { int32_t c00, d00; int16_t dx, dy; int32_t lim, len2; } p2_seg;

/* D1 heads: heat[60] int8, box[60][4] int8 (dy, dx, log h, log w). */
void p2_det_decode(const int8_t *heat, const int8_t (*box)[4], p2_box *out);
/* Box -> 2:3 crop, enlarged 1.25x, as the ROI registers (cv2 crop_matrix mapping). */
void p2_box_to_roi(const p2_box *b, p2_roi *roi);
/* Pose heads, HWC: heat[216][12], off[216][24] (dy 0..11, dx 12..23). */
void p2_pose_decode(const int8_t (*heat)[12], const int8_t (*off)[24], const p2_roi *roi, p2_kp kp[P2_NJ]);
/* Camera Q8 -> LCD integer pixel. */
void p2_cam_to_lcd(int32_t x_q8, int32_t y_q8, int32_t *lx, int32_t *ly);
/* Segment parameters for p2_overlay (half-width in px). */
void p2_make_seg(int32_t x1, int32_t y1, int32_t x2, int32_t y2, int32_t half_width, p2_seg *s);
extern const uint8_t p2_edges[P2_NSEG][2];
#endif

/* ---- temporal smoothing (One Euro on joints, EMA on the D1 box) ----
 * Integer form of p2/src/smooth.py at a fixed frame period 1/P2_FPS (camera rate). */
#ifndef P2_FPS_X10
#define P2_FPS_X10 156            /* OV5640 as configured: 15.6 fps */
#endif
typedef struct { int32_t x, y, dx, dy; int on; } p2_oe_joint;   /* Q8 camera px, Q8 px/frame */
typedef struct { p2_oe_joint j[P2_NJ]; } p2_oe;
void p2_oe_reset(p2_oe *f);
/* min_cutoff_q8 [Hz*256], beta_q16 [1/(px/s) * 65536]; filters kp in place (valid joints only). */
void p2_oe_apply(p2_oe *f, p2_kp kp[P2_NJ], int32_t min_cutoff_q8, int32_t beta_q16);
/* box EMA: s = a*b + (1-a)*s, a in Q8 (256 = off); first valid box initialises. */
void p2_box_smooth(p2_box *s, int *have, const p2_box *b, int32_t a_q8);

/* ---- hardware joint post-processing (rtl/p2_kp_post.sv); this is its bit-exact reference ----
 * CPU writes per joint a packed word {valid[31], y_q4[30:16], x_q4[14:0]} (camera px, Q4, clamped
 * to 0..2047.9375).  The block runs One Euro (LUT alpha), maps to display pixels and computes the
 * overlay segment parameters. */
#define P2_OE_MC_Q8 179           /* min cutoff 0.7 Hz */
#define P2_OE_KB_Q16 51118        /* beta 0.05 /(px/s) * 15.6 fps, Q16 (per-frame |dx| in Q8) */
#ifdef P2_HDMI
#define P2_DISP_MUL_Q16 65536
#else
#define P2_DISP_MUL_Q16 52429     /* 4/5 */
#endif
typedef struct { int32_t xh[P2_NJ], yh[P2_NJ], dxh[P2_NJ], dyh[P2_NJ]; uint8_t on[P2_NJ]; } p2_post_state;
uint32_t p2_pack_joint(const p2_kp *k);
void p2_post_reset(p2_post_state *s);
/* raw: 12 packed words.  Outputs: dots[12] {y,x} words, segs[12][5], enables. */
void p2_post(p2_post_state *s, const uint32_t raw[P2_NJ], uint32_t dots[P2_NJ], uint32_t segs[P2_NSEG][5],
             uint32_t *dot_en, uint32_t *seg_en);
