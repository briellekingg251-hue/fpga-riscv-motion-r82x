"""Detect -> crop -> pose with skeleton tracking on recorded board-camera video.

Policy (BlazePose / MoveNet style, what the firmware would do):
  * no track: run PersonDet on the whole frame, take the top-1 box (score >= DET_T)
  * pose on the crop; if the torso joints are confident the next crop comes from
    this skeleton (box of confident joints + head/feet margins, EMA smoothed),
    otherwise the track is dropped and the detector runs on the next frame.
Writes an annotated mp4 and stats (detector calls, confidence, joint jitter).

  python video_track.py --frames D:/hand_dataset/P01_S01/video_01 \
      --det runs/det_s16/best.pt --pose runs/poseB_plain_s16_body12/best.pt
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import torch

from data import KP_SETS, box_to_center_scale
from eval_e2e import detect_top1, load_det, load_pose, pose_on_box
from smooth import OneEuro

DET_T = 0.2         # detector score to accept a person
KP_T = 0.3          # keypoint probability counted as confident
SKELETON = [(5, 7), (7, 9), (6, 8), (8, 10), (5, 6), (5, 11), (6, 12), (11, 12),
            (11, 13), (13, 15), (12, 14), (14, 16)]
TORSO = (5, 6, 11, 12)


def box_from_skeleton(xy, p, kp_set):
    ok = p >= KP_T
    if ok[list(TORSO)].sum() < 2 or ok.sum() < 4:
        return None
    x0, y0 = xy[ok].min(0)
    x1, y1 = xy[ok].max(0)
    h = y1 - y0
    top = 0.25 * h if kp_set == 'body12' or p[:5].max() < KP_T else 0.08 * h   # head above shoulders
    bottom = 0.05 * h if ok[15] or ok[16] else 0.25 * h                        # feet below ankles
    w = x1 - x0
    return [x0 - 0.1 * w, y0 - top, w * 1.2, h + top + bottom]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--frames', required=True)
    ap.add_argument('--det', required=True)
    ap.add_argument('--pose', required=True)
    ap.add_argument('--out', default='runs/video')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--smooth', action='store_true', help='One Euro filter on the output joints')
    ap.add_argument('--tag', default='', help='suffix for output names')
    ap.add_argument('--ema', type=float, default=0.5, help='box smoothing (weight of the new box)')
    args = ap.parse_args()
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    detm = load_det(args.det, device)
    posem, kp_set = load_pose(args.pose, device)
    files = sorted(Path(args.frames).glob('*.jpg'))[:args.limit or None]
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    name = f'{Path(args.frames).parent.name}_{Path(args.frames).name}_{Path(args.pose).parent.name}{args.tag}'
    filt = OneEuro(17)
    vw = None
    box, prev, stats = None, None, dict(frames=0, det_calls=0, tracked=0, lost=0, conf=[], jitter=[])
    log = []
    for f in files:
        bgr = cv2.imread(str(f))
        rgb = np.ascontiguousarray(bgr[:, :, ::-1])
        stats['frames'] += 1
        src = 'track'
        if box is None:
            stats['det_calls'] += 1
            src = 'det'
            hit = detect_top1(detm, rgb, device)
            if hit is None or hit[1] < DET_T:
                log.append(dict(file=f.name, src='none'))
                prev = None
                vis = bgr
                if vw is None:
                    vw = cv2.VideoWriter(str(out / f'{name}.mp4'), cv2.VideoWriter_fourcc(*'mp4v'), 15, (640, 360))
                vw.write(cv2.resize(vis, (640, 360)))
                continue
            box = hit[0]
        used = box
        xy, p = pose_on_box(posem, kp_set, rgb, used, device)
        idx = KP_SETS[kp_set]
        conf = float(p[idx].mean())
        stats['conf'].append(conf)
        nb = box_from_skeleton(xy, p, kp_set)          # crop from the raw joints (responsive)
        if args.smooth:
            if src == 'det':
                filt.reset()
            xy = filt(xy, p >= KP_T)
        if prev is not None:
            both = (p >= KP_T) & (prev[1] >= KP_T)
            if both.any():
                stats['jitter'].append(float(np.linalg.norm(xy[both] - prev[0][both], axis=1).mean() / used[3]))
        if nb is None:
            stats['lost'] += src == 'track'
            box, prev = None, None
        else:
            stats['tracked'] += src == 'track'
            box = list(args.ema * np.array(nb) + (1 - args.ema) * np.array(box)) if src == 'track' else nb
            prev = (xy, p)
        log.append(dict(file=f.name, src=src, conf=round(conf, 3),
                        kps=[[round(float(a), 1), round(float(b), 1), round(float(c), 3)] for (a, b), c in zip(xy, p)]))
        vis = bgr.copy()
        c, s = box_to_center_scale(used)
        cv2.rectangle(vis, tuple((c - s / 2).astype(int)), tuple((c + s / 2).astype(int)),
                      (0, 255, 255) if src == 'det' else (255, 200, 0), 2)
        for a, b in SKELETON:
            if p[a] >= KP_T and p[b] >= KP_T:
                cv2.line(vis, tuple(xy[a].astype(int)), tuple(xy[b].astype(int)), (0, 255, 0), 4)
        for k in idx:
            if p[k] >= KP_T:
                cv2.circle(vis, tuple(xy[k].astype(int)), 6, (0, 0, 255), -1)
        cv2.putText(vis, f'{src} conf {conf:.2f}', (20, 50), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (255, 255, 255), 3)
        if vw is None:
            vw = cv2.VideoWriter(str(out / f'{name}.mp4'), cv2.VideoWriter_fourcc(*'mp4v'), 15, (640, 360))
        vw.write(cv2.resize(vis, (640, 360)))
    vw.release()
    summary = dict(video=name, frames=stats['frames'], det_calls=stats['det_calls'],
                   det_call_rate=round(stats['det_calls'] / max(1, stats['frames']), 3),
                   track_lost=stats['lost'], mean_conf=round(float(np.mean(stats['conf'])), 3) if stats['conf'] else 0,
                   median_jitter_rel=round(float(np.median(stats['jitter'])), 4) if stats['jitter'] else None)
    (out / f'{name}.json').write_text(json.dumps(dict(summary=summary, frames=log)))
    print(json.dumps(summary, indent=1))


if __name__ == '__main__':
    main()
