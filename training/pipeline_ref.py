"""v1 end-to-end integer reference: 1280x720 frame -> person box -> crop -> 12 body joints.

Only numpy + the exported integer parameters; this is what hardware + firmware
must reproduce.  Steps per frame:

 1. detector input (only when there is no track): 160x96 RGB,
        det[v][u] = frame[8*(v-3)][8*u]   for v = 3..92,   black (0,0,0) for v = 0..2, 93..95
    (plain 8x decimation; identical to the training-time warp at this scale)
 2. detector integer net -> heat (1x6x10), box (4x6x10)
 3. top-1 cell = first maximum of heat; box centre = cell*16 + 7.5 + dequant(dy, dx),
    size = exp(dequant(log h, log w)); x 8 back to frame pixels, minus the 24 letterbox rows
    (dequant: pow2 export q * 2^out_exp; npu export (q - output_zero) * output_scale)
 4. crop window: box -> 2:3 (w:h) by growing the short side, x1.25; bilinear resample to 128x192,
        src_x = cx + (u - 63.5) * W / 128 ... (exactly cv2.warpAffine of data.crop_matrix,
        INTER_LINEAR, outside the frame = black)
 5. pose integer net -> heat (12 x H/s x W/s), offset (24 x H/s x W/s)
 6. per joint: first maximum cell (row, col); x = col*s + (s-1)/2 + dequant(dx), likewise y
    (crop pixels) -> frame pixels with the inverse of step 4; score = dequant(heat) (logit)
 7. tracking: if >= 2 torso joints and >= 4 joints have logit >= T, next frame's box comes from
    the joints (video_track.box_from_skeleton, EMA 0.5); otherwise run the detector again.
 8. output smoothing: One Euro filter per joint (smooth.py), reset on every detection.

  python pipeline_ref.py --det runs/det_s16_wide/export_pow2 --pose runs/poseB_plain_s16_body12/export_pow2 \
      --frames D:/body_videos/frames/body_20261003_100609 --limit 30
"""
import argparse
import json
import math
from pathlib import Path

import cv2
import numpy as np

from data import box_to_center_scale, crop_matrix
from verify_export import run as int_run
from smooth import OneEuro
from video_track import box_from_skeleton

LOGIT_T = math.log(0.3 / 0.7)          # keypoint probability 0.3


class IntModel:
    def __init__(self, d):
        d = Path(d)
        self.meta = json.loads((d / 'layers.json').read_text())
        self.P = dict(np.load(d / 'params.npz'))
        self.heads = self.meta['layers'][-2:]
        self.stride = self.meta['stride']

    def dq(self, h, q):
        """Dequantize head h (0 = heat, 1 = offset/box) of an integer output."""
        L = self.heads[h]
        if self.meta['mode'].startswith('pow2'):
            return q * 2.0 ** L['out_exp']
        return (q - L['output_zero']) * L['output_scale']

    def __call__(self, rgb):
        outs = int_run(self.meta, self.P, rgb)
        return outs[-2], outs[-1]           # integer heads (C,H,W)


def det_input(frame):
    x = np.zeros((96, 160, 3), np.uint8)
    x[3:93] = frame[0:720:8, 0:1280:8]
    return x


def det_top1(det, frame):
    heat, box = det(det_input(frame))
    s = det.stride
    i = int(np.argmax(heat[0]))
    r, c = divmod(i, heat.shape[2])
    dy, dx, lh, lw = det.dq(1, box[:, r, c].astype(float)).tolist()
    cy, cx = r * s + (s - 1) / 2 + dy, c * s + (s - 1) / 2 + dx
    h, w = math.exp(lh), math.exp(lw)
    x0, y0 = (cx - w / 2) * 8, (cy - h / 2 - 3) * 8
    score = det.dq(0, float(heat[0, r, c]))
    fx0, fy0 = max(0.0, x0), max(0.0, y0)
    fx1, fy1 = min(1280.0, x0 + w * 8), min(720.0, y0 + h * 8)
    return [fx0, fy0, max(fx1 - fx0, 2), max(fy1 - fy0, 2)], score


def pose_on_box(pose, frame, box):
    center, size = box_to_center_scale(box)
    m = crop_matrix(center, size)
    crop = cv2.warpAffine(frame, m, (128, 192), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0))
    heat, off = pose(crop)
    k, s = heat.shape[0], pose.stride
    flat = heat.reshape(k, -1)
    idx = flat.argmax(1)
    r, c = idx // heat.shape[2], idx % heat.shape[2]
    dy = pose.dq(1, off[np.arange(k), r, c].astype(float))
    dx = pose.dq(1, off[np.arange(k) + k, r, c].astype(float))
    pts = np.stack([c * s + (s - 1) / 2 + dx, r * s + (s - 1) / 2 + dy], 1)
    inv = cv2.invertAffineTransform(m)
    xy = np.c_[pts, np.ones(k)] @ inv.T
    logit = pose.dq(0, flat[np.arange(k), idx].astype(float))
    return xy, logit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--det', required=True)
    ap.add_argument('--pose', required=True)
    ap.add_argument('--frames', required=True)
    ap.add_argument('--limit', type=int, default=30)
    ap.add_argument('--out', default='runs/pipeline_ref')
    args = ap.parse_args()
    det, pose = IntModel(args.det), IntModel(args.pose)
    assert len(pose.meta['keypoints']) == 12
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    box, results, filt = None, [], OneEuro(12)
    for f in sorted(Path(args.frames).glob('*.jpg'))[:args.limit]:
        frame = np.ascontiguousarray(cv2.imread(str(f))[:, :, ::-1])
        src = 'track'
        if box is None:
            box, dscore = det_top1(det, frame)
            src = 'det'
        used = box
        xy, logit = pose_on_box(pose, frame, used)
        full_xy, full_p = np.zeros((17, 2)), np.zeros(17)
        full_xy[5:], full_p[5:] = xy, 1 / (1 + np.exp(-logit))
        nb = box_from_skeleton(full_xy, full_p, 'body12')
        if src == 'det':
            filt.reset()
        xy = filt(xy, full_p[5:] >= 0.3)
        box = None if nb is None else (nb if src == 'det' else list(0.5 * np.array(nb) + 0.5 * np.array(used)))
        results.append(dict(file=f.name, src=src, box=[round(v, 1) for v in used],
                            joints={n: [round(float(a), 1), round(float(b), 1), round(float(l), 3)]
                                    for n, (a, b), l in zip(pose.meta['keypoints'], xy, logit)}))
    (out / 'pipeline_ref.json').write_text(json.dumps(results, indent=1))
    print(f'{len(results)} frames, detector calls {sum(r["src"] == "det" for r in results)} -> {out / "pipeline_ref.json"}')


if __name__ == '__main__':
    main()
