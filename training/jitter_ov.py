"""Temporal stability on OV5640 held-out blocks: excess frame-to-frame joint motion vs the teacher.

jitter = median over consecutive labelled frame pairs of |d_pred - d_teacher| / torso, per joint group,
where d = joint displacement between the two frames.  Raw outputs (no smoothing), deployment chain
(D1 top-1 box every frame -> crop -> pose).

  python jitter_ov.py --frames-root R --tests STEM... --det D1 --pose NAME=PATH ... --out j.json
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
import torch

from eval_e2e import detect_top1, load_det, load_pose, pose_on_box
from eval_ov import DET_T, GROUPS


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--frames-root', required=True)
    ap.add_argument('--tests', nargs='+', required=True)
    ap.add_argument('--det', required=True)
    ap.add_argument('--pose', action='append', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    device = 'cuda'
    detm = load_det(args.det, device)
    poses = {s.split('=', 1)[0]: load_pose(s.split('=', 1)[1], device) for s in args.pose}
    diffs = {n: {g: [] for g in GROUPS} for n in poses}
    for stem in args.tests:
        d = json.load(open(Path(args.frames_root) / f'{stem}_rtm_body12_test.json'))
        files = {im['id']: im['file_name'] for im in d['images']}
        anns = {a['image_id']: np.array(a['keypoints'], np.float32).reshape(17, 3)[5:] for a in d['annotations']}
        prev = None
        for fid in sorted(anns):
            kp = anns[fid]
            rgb = cv2.imread(str(Path(args.frames_root) / stem / files[fid]))[:, :, ::-1].copy()
            hit = detect_top1(detm, rgb, device)
            preds = {}
            if hit is not None and hit[1] >= DET_T:
                for n, (pm, ks) in poses.items():
                    preds[n] = pose_on_box(pm, ks, rgb, hit[0], device)[0][5:]
            if prev is not None and prev[0] == fid - 1 and preds and prev[2]:
                pk, ppred = prev[1], prev[2]
                v = (kp[:, 2] > 0) & (pk[:, 2] > 0)
                if v[[0, 1, 6, 7]].all():
                    torso = np.linalg.norm(kp[[0, 1], :2].mean(0) - kp[[6, 7], :2].mean(0))
                    dt = kp[:, :2] - pk[:, :2]
                    for n in poses:
                        e = np.linalg.norm((preds[n] - ppred[n]) - dt, axis=1) / torso
                        for g, ix in GROUPS.items():
                            diffs[n][g] += [float(e[k]) for k in ix if v[k]]
            prev = (fid, kp, preds)
    res = {n: {g: round(float(np.median(x)), 4) for g, x in gs.items()} for n, gs in diffs.items()}
    Path(args.out).write_text(json.dumps(dict(tests=args.tests, metric='median excess motion / torso', models=res), indent=1))
    for n, r in res.items():
        print(f'{n:22s} ' + ' '.join(f'{g}={v:.4f}' for g, v in r.items()))


if __name__ == '__main__':
    main()
