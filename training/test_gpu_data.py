"""Equivalence check: GPU canvas pipeline (augment off) vs original CPU CocoTopDown val crop/targets."""
import os
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

from anncache import slim_coco
from data import CocoTopDown
from gpu_data import GpuTrainLoader, Source
from precrop import _group, build

COCO = Path(os.environ.get('COCO_DIR', 'D:/datasets/coco'))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 300


def main():
    ref = CocoTopDown(COCO / 'annotations/person_keypoints_val2017.json', COCO / 'val2017', train=False,
                      kp_set='body12', stride=16)
    d = slim_coco(COCO / 'annotations/person_keypoints_val2017.json')
    files = {i: name for i, name, _, _ in d['images']}
    items = ref.items[:N]
    jobs = [(f'{COCO}/val2017/{files[a["image_id"]]}', [(a['bbox'], np.array(a['keypoints'], np.float32).reshape(17, 3)[5:])])
            for a in items]                       # one job per person keeps order identical
    out = Path(tempfile.gettempdir()) / 'p2_val_canvas'
    build(jobs, out, workers=4)
    gl = GpuTrainLoader([Source(out)], batch=N, device='cuda', stride=16, augment=False, drop_last=False)
    x, heat, off, off_w, vis = gl.make_batch(torch.arange(N))
    rx = torch.stack([ref[i][0] for i in range(N)]).cuda()
    rh = torch.stack([ref[i][1] for i in range(N)]).cuda()
    ro = torch.stack([ref[i][2] for i in range(N)]).cuda()
    rw = torch.stack([ref[i][3] for i in range(N)]).cuda()
    rv = torch.stack([ref[i][4] for i in range(N)]).cuda()
    pix = ((x - rx).abs() * 127.5)
    print(f'pixel |diff| mean {pix.mean():.2f}  p99 {pix.flatten().quantile(0.99) if pix.numel() < 2**24 else pix.flatten()[:2**24].quantile(0.99):.1f}  (0-255 scale; JPEG + 2nd resample)')
    print(f'vis equal {(vis == rv).float().mean():.5f}')
    print(f'heat max|diff| {(heat - rh).abs().max():.4f}  off_w equal {(off_w == rw).float().mean():.5f}')
    m = rw.repeat(1, 2, 1, 1) > 0
    print(f'offset max|diff| on supervised cells {(off - ro)[m].abs().max():.4f} px')


if __name__ == '__main__':
    main()


def jpeg_check():
    """GPU JPEG simulation vs real libjpeg (cv2) on the same crops: mean |diff| should be ~1 grey level."""
    import cv2
    from gpu_data import jpeg_sim
    d = np.load(Path(tempfile.gettempdir()) / 'p2_val_canvas.npy', mmap_mode='r')[:32, :192, :128]
    for q in (40, 70, 90):
        ref = np.stack([cv2.cvtColor(cv2.imdecode(cv2.imencode('.jpg', cv2.cvtColor(im, cv2.COLOR_RGB2BGR),
                        [cv2.IMWRITE_JPEG_QUALITY, q])[1], 1), cv2.COLOR_BGR2RGB) for im in d])
        x = torch.from_numpy(np.ascontiguousarray(d)).permute(0, 3, 1, 2).float().cuda()
        sim = jpeg_sim(x, torch.full((32,), float(q), device='cuda')).permute(0, 2, 3, 1).cpu().numpy()
        print(f'jpeg q{q}: sim vs libjpeg mean|diff| {np.abs(sim - ref).mean():.2f}, '
              f'libjpeg vs original {np.abs(ref.astype(float) - d).mean():.2f}')


if __name__ == '__main__' and len(sys.argv) > 2:
    jpeg_check()
