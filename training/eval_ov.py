"""OV5640 held-out acceptance: per-joint PCK@0.2 (torso-normalised) against teacher labels.

Two modes per pose model (float checkpoint or pow2u export dir):
  gtbox : teacher person box -> crop -> pose          (pose network alone)
  e2e   : D1 top-1 box on every frame -> crop -> pose  (deployment chain, no tracking/smoothing)

  python eval_ov.py --frames-root D:/body_videos/frames --tests STEM... --det D1 --pose NAME=PATH ... --out ov.json
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import torch

from eval_e2e import detect_top1, load_det, load_pose, pose_on_box

JOINTS = ['Lsho', 'Rsho', 'Lelb', 'Relb', 'Lwri', 'Rwri', 'Lhip', 'Rhip', 'Lkne', 'Rkne', 'Lank', 'Rank']
GROUPS = {'shoulder': (0, 1), 'elbow': (2, 3), 'wrist': (4, 5), 'hip': (6, 7), 'knee': (8, 9), 'ankle': (10, 11)}
THR = 0.2
DET_T = 0.2


def load_tests(root, stems):
    items = []
    for stem in stems:
        d = json.load(open(Path(root) / f'{stem}_rtm_body12_test.json'))
        files = {im['id']: im['file_name'] for im in d['images']}
        for a in d['annotations']:
            kp = np.array(a['keypoints'], np.float32).reshape(17, 3)[5:]
            items.append((stem, Path(root) / stem / files[a['image_id']], a['bbox'], kp))
    return items


def score(pred, kp, hit, cnt):
    v = kp[:, 2] > 0
    if not (v[0] or v[1]) or not (v[6] or v[7]):
        return
    torso = np.linalg.norm(kp[[k for k in (0, 1) if v[k]], :2].mean(0) - kp[[k for k in (6, 7) if v[k]], :2].mean(0))
    if torso < 8:
        return
    d = np.linalg.norm(pred - kp[:, :2], axis=1) / torso
    cnt += v
    hit += v & (d < THR)


def summary(hit, cnt):
    per = {j: round(float(hit[k] / max(cnt[k], 1)), 4) for k, j in enumerate(JOINTS)}
    grp = {g: round(float(hit[list(ix)].sum() / max(cnt[list(ix)].sum(), 1)), 4) for g, ix in GROUPS.items()}
    return dict(groups=grp, joints=per, mean=round(float(hit.sum() / max(cnt.sum(), 1)), 4), n=int(cnt.max()))


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--frames-root', required=True)
    ap.add_argument('--tests', nargs='+', required=True)
    ap.add_argument('--det', required=True)
    ap.add_argument('--pose', action='append', required=True, help='NAME=PATH (best.pt or export dir)')
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    items = load_tests(args.frames_root, args.tests)
    detm = load_det(args.det, device)
    poses = {}
    for spec in args.pose:
        name, path = spec.split('=', 1)
        poses[name] = load_pose(path, device)
    acc = {(n, m): (np.zeros(12), np.zeros(12)) for n in poses for m in ('gtbox', 'e2e')}
    misses = 0
    for i, (stem, f, box, kp) in enumerate(items):
        rgb = cv2.imread(str(f))[:, :, ::-1].copy()
        hit = detect_top1(detm, rgb, device)
        dbox = hit[0] if hit is not None and hit[1] >= DET_T else None
        misses += dbox is None
        for name, (pm, kp_set) in poses.items():
            xy, _ = pose_on_box(pm, kp_set, rgb, box, device)
            score(xy[5:], kp, *acc[(name, 'gtbox')])
            if dbox is not None:
                xy, _ = pose_on_box(pm, kp_set, rgb, dbox, device)
                score(xy[5:], kp, *acc[(name, 'e2e')])
            else:                                   # a missed detection counts every joint as wrong
                h, c = acc[(name, 'e2e')]
                c += kp[:, 2] > 0
        if i % 500 == 0:
            print(f'{i}/{len(items)}', flush=True)
    res = dict(tests=args.tests, frames=len(items), det=args.det, det_misses=misses, thr=THR,
               models={n: {m: summary(*acc[(n, m)]) for m in ('gtbox', 'e2e')} for n in poses},
               paths=dict(s.split('=', 1) for s in args.pose))
    Path(args.out).write_text(json.dumps(res, indent=1))
    for n in poses:
        for m in ('gtbox', 'e2e'):
            g = res['models'][n][m]['groups']
            print(f'{n:22s} {m:5s} ' + ' '.join(f'{k}={v:.3f}' for k, v in g.items()) +
                  f'  mean={res["models"][n][m]["mean"]:.3f}')


if __name__ == '__main__':
    main()
