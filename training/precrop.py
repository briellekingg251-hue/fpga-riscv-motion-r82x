"""Pre-crop every training person once into a fixed-size raw "canvas" for GPU augmentation.

The CPU-side decode + warpAffine + augmentation starved the 5090s (50-core quota saturated).
Here each person is warped once to a canvas that covers the crop window under the training
augmentation (scale <= 1.35, shift +-8%, rotation; corners only at extreme rotation fall outside
and become black, like the original BORDER_CONSTANT).  Canvas pixel density is CANVAS_DENSITY x
the 192x128 input at scale 1, so the second (GPU) resample does not lose resolution.

Output <out>.npy: raw RGB uint8 (N, CANVAS_H, CANVAS_W, 3) -- meant for /dev/shm, memory-mapped and
shared by every training process -- and <out>.pt: dict(kp=(N,K,2) canvas px, vis=(N,K) bool, meta).
(nvJPEG decode was the GPU-loader bottleneck, so canvases stay raw.)

  python precrop.py coco  COCO_DIR /dev/shm/p2/coco_train
  python precrop.py video ANN_JSON FRAME_DIR /dev/shm/p2/video_x
"""
import argparse
import os
from multiprocessing import Pool
from pathlib import Path

import cv2
import numpy as np
import torch

from anncache import slim_coco
from data import KP_SETS, box_to_center_scale
from model import IN_H, IN_W

CANVAS_EXTENT = tuple(float(v) for v in os.environ.get('CANVAS_EXTENT', '2.2,1.8').split(','))  # x w, x h of crop window
CANVAS_DENSITY = float(os.environ.get('CANVAS_DENSITY', '1.2'))     # canvas px per input px at scale 1
CANVAS_W = int(round(IN_W * CANVAS_EXTENT[0] * CANVAS_DENSITY / 8)) * 8     # 336
CANVAS_H = int(round(IN_H * CANVAS_EXTENT[1] * CANVAS_DENSITY / 8)) * 8     # 416


def canvas_matrix(center, size):
    """2x3 affine original image -> canvas (no rotation)."""
    sx = CANVAS_W / (size[0] * CANVAS_EXTENT[0])
    sy = CANVAS_H / (size[1] * CANVAS_EXTENT[1])
    return np.array([[sx, 0, CANVAS_W / 2 - sx * center[0]],
                     [0, sy, CANVAS_H / 2 - sy * center[1]]], np.float32)


def _work(job):
    path, items = job
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        raise RuntimeError(f'cannot read {path}')
    out = []
    for bbox, kp in items:
        center, size = box_to_center_scale(bbox)
        m = canvas_matrix(center, size)
        canvas = cv2.warpAffine(img, m, (CANVAS_W, CANVAS_H), flags=cv2.INTER_LINEAR,   # same filter as the original single warp
                                borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0))
        kp = np.asarray(kp, np.float32)
        pts = np.c_[kp[:, :2], np.ones(len(kp))] @ m.T
        out.append((np.ascontiguousarray(canvas[:, :, ::-1]), pts.astype(np.float32), kp[:, 2] > 0))
    return out


def build(jobs, out_stem, workers):
    os.environ.setdefault('OMP_NUM_THREADS', '1')
    cv2.setNumThreads(1)
    out_stem = Path(out_stem)
    out_stem.parent.mkdir(parents=True, exist_ok=True)
    total = sum(len(items) for _, items in jobs)
    tmp_npy = out_stem.with_name(out_stem.name + '.npy.tmp')
    arr = np.lib.format.open_memmap(tmp_npy, mode='w+', dtype=np.uint8, shape=(total, CANVAS_H, CANVAS_W, 3))
    kps, vis, n = [], [], 0
    with Pool(workers) as pool:
        for i, res in enumerate(pool.imap(_work, jobs, chunksize=16)):
            for canvas, pts, v in res:
                arr[n] = canvas
                kps.append(pts)
                vis.append(v)
                n += 1
            if i % 5000 == 0:
                print(f'{i}/{len(jobs)} images, {n} persons', flush=True)
    assert n == total, (n, total)
    arr.flush()
    del arr
    tmp_npy.replace(out_stem.with_name(out_stem.name + '.npy'))
    meta = dict(kp=torch.from_numpy(np.stack(kps)), vis=torch.from_numpy(np.stack(vis)),
                canvas=(CANVAS_H, CANVAS_W), extent=CANVAS_EXTENT, in_hw=(IN_H, IN_W))
    torch.save(meta, out_stem.with_name(out_stem.name + '.pt'))
    print(f'{out_stem}: {n} persons, {total * CANVAS_H * CANVAS_W * 3 / 2**30:.1f} GiB raw', flush=True)


def coco_jobs(coco_dir, kp_set='body12', frac=1.0, seed=0):
    d = slim_coco(Path(coco_dir) / 'annotations/person_keypoints_train2017.json')
    files = {i: name for i, name, _, _ in d['images']}
    items = [a for a in d['persons'] if not a['iscrowd'] and a['num_keypoints'] >= 1
             and a['bbox'][2] > 1 and a['bbox'][3] > 1]
    if frac < 1:     # same subset rule as train.py --coco-frac
        rng = np.random.default_rng(seed)
        items = [items[i] for i in sorted(rng.choice(len(items), int(len(items) * frac), replace=False))]
    return _group(items, lambda a: f'{coco_dir}/train2017/{files[a["image_id"]]}', kp_set)


def video_jobs(ann_file, frame_dir, kp_set='body12'):
    d = slim_coco(ann_file)
    files = {i: name for i, name, _, _ in d['images']}
    items = [a for a in d['persons'] if not a['iscrowd'] and a['num_keypoints'] >= 1
             and a['bbox'][2] > 1 and a['bbox'][3] > 1]
    return _group(items, lambda a: f'{frame_dir}/{files[a["image_id"]]}', kp_set)


def _group(items, path_of, kp_set):
    idx = KP_SETS[kp_set]
    by_img = {}
    for a in items:
        kp = np.array(a['keypoints'], np.float32).reshape(17, 3)[idx]
        by_img.setdefault(path_of(a), []).append((a['bbox'], kp))
    return list(by_img.items())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('kind', choices=['coco', 'video'])
    ap.add_argument('paths', nargs='+')
    ap.add_argument('--workers', type=int, default=44)
    args = ap.parse_args()
    if args.kind == 'coco':
        coco_dir, out = args.paths
        jobs = coco_jobs(coco_dir)
    else:
        ann, frames, out = args.paths
        jobs = video_jobs(ann, frames)
    build(jobs, out, args.workers)


if __name__ == '__main__':
    main()
