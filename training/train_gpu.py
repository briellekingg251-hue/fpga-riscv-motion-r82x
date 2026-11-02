"""P2 training with the GPU data pipeline (gpu_data.py); model/loss/eval contract as train.py.

  python train_gpu.py --name p2_s16 --cfg s16 --source /dev/shm/p2/coco_train --epochs 60
  python train_gpu.py --name p2_s16_ft --cfg s16 --resume runs/p2_s16/best.pt \
      --source /dev/shm/p2/coco_train|1|0.2 --source /dev/shm/p2/ov_train|4 --epochs 12 --lr 1e-3

--source STEM[|REPEAT[|FRAC]] may repeat.  --kp-weight limbs up-weights wrists/ankles/elbows/knees.
Every eval writes COCO AP + per-joint PCK@0.2 (upright val, GT boxes) to metrics.jsonl.
"""
import argparse
import json
import math
import os
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

from data import CocoTopDown, collate, decode, crop_matrix
from gpu_data import GpuTrainLoader, Source
from model import IN_H, IN_W, build, hw_check
from threadloader import ThreadLoader
from train import evaluate, load_gts

COCO_DIR = Path(os.environ.get('COCO_DIR', str(Path(__file__).resolve().parents[1] / 'data/coco')))
JOINTS = ['Lsho', 'Rsho', 'Lelb', 'Relb', 'Lwri', 'Rwri', 'Lhip', 'Rhip', 'Lkne', 'Rkne', 'Lank', 'Rank']
KP_WEIGHTS = {'none': [1.0] * 12,
              'limbs': [1.0, 1.0, 1.25, 1.25, 2.0, 2.0, 1.0, 1.0, 1.25, 1.25, 1.5, 1.5],
              'limbs2': [1.0, 1.0, 1.5, 1.5, 3.0, 3.0, 1.0, 1.0, 1.5, 1.5, 2.0, 2.0]}


def loss_fn(heat_logit, off_pred, heat_t, off_t, off_w, kpw):
    """train.loss_fn with a per-keypoint weight on both heat and offset terms."""
    w_k = kpw[None, :, None, None]
    p = heat_logit.sigmoid().clamp(1e-4, 1 - 1e-4)
    pos = heat_t.ge(0.99).float()
    neg_w = (1 - heat_t) ** 4
    l_pos = -(w_k * pos * (1 - p) ** 2 * torch.log(p)).sum()
    l_neg = -(w_k * (1 - pos) * neg_w * p ** 2 * torch.log(1 - p)).sum()
    l_heat = (l_pos + l_neg) / pos.sum().clamp(min=1)
    w = torch.cat([off_w * w_k, off_w * w_k], 1)
    l_off = (F.smooth_l1_loss(off_pred, off_t, reduction='none', beta=1.0) * w).sum() / \
        torch.cat([off_w, off_w], 1).sum().clamp(min=1)
    return l_heat + 0.1 * l_off, l_heat.detach(), l_off.detach()


@torch.no_grad()
def per_joint_pck(model, val_set, loader, device, thr=0.2):
    """PCK@thr normalised by GT torso length on upright val persons (GT boxes), per joint."""
    model.eval()
    by_id = {a['id']: a for a in val_set.items}
    hit, cnt = np.zeros(12), np.zeros(12)
    for x, *_, meta in loader:
        h, o = model(x.to(device, non_blocking=True))
        pred = decode(h.float(), o.float(), model.stride)[0].cpu().numpy()
        for i, m in enumerate(meta):
            a = by_id[m['ann_id']]
            kp = np.array(a['keypoints'], np.float32).reshape(17, 3)[val_set.kp_idx]
            g = np.c_[kp[:, :2], np.ones(12)] @ crop_matrix(m['center'], m['size']).T
            v = kp[:, 2] > 0
            v &= (g[:, 0] >= 0) & (g[:, 0] < IN_W) & (g[:, 1] >= 0) & (g[:, 1] < IN_H)
            if not (v[0] or v[1]) or not (v[6] or v[7]):
                continue
            torso = np.linalg.norm(g[[k for k in (0, 1) if v[k]]].mean(0) - g[[k for k in (6, 7) if v[k]]].mean(0))
            if torso < 8:
                continue
            d = np.linalg.norm(pred[i] - g, axis=1) / torso
            cnt += v
            hit += v & (d < thr)
    model.train()
    return {j: round(float(hit[k] / max(cnt[k], 1)), 4) for k, j in enumerate(JOINTS)}


def parse_source(spec):
    parts = spec.split('|')
    return Source(parts[0], float(parts[1]) if len(parts) > 1 else 1.0, float(parts[2]) if len(parts) > 2 else 1.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--name', required=True)
    ap.add_argument('--cfg', default='s16')
    ap.add_argument('--source', action='append', required=True)
    ap.add_argument('--epochs', type=int, default=60)
    ap.add_argument('--batch', type=int, default=256)
    ap.add_argument('--lr', type=float, default=4e-3)
    ap.add_argument('--wd', type=float, default=1e-4)
    ap.add_argument('--kp-weight', default='none', choices=sorted(KP_WEIGHTS))
    ap.add_argument('--max-rot', type=float, default=30.0)
    ap.add_argument('--no-board-aug', action='store_true')
    ap.add_argument('--eval-every', type=int, default=5)
    ap.add_argument('--resume', default='', help='initial weights (fine-tune)')
    ap.add_argument('--continue', dest='cont', action='store_true', help='resume this run from last.pt')
    ap.add_argument('--compile', action='store_true')
    ap.add_argument('--allow-hw-violation', action='store_true', help='only for baseline/control runs (e.g. old P1)')
    ap.add_argument('--loader-threads', type=int, default=6)
    ap.add_argument('--cpu-threads', type=int, default=4)
    args = ap.parse_args()

    ok, rep = hw_check(args.cfg)
    print('hw_check', json.dumps(rep), flush=True)
    if not ok and not args.allow_hw_violation:
        raise SystemExit(f'{args.cfg} violates n111116 rules: {rep["errors"]}')
    device = 'cuda'
    torch.set_num_threads(args.cpu_threads)          # default = all 208 host cores; quota is 50
    torch.backends.cudnn.benchmark = True
    run = Path('runs') / args.name
    run.mkdir(parents=True, exist_ok=True)
    model = build('plain', 12, cfg=args.cfg).to(device).to(memory_format=torch.channels_last)
    if args.resume:
        model.load_state_dict(torch.load(args.resume, map_location=device, weights_only=False)['model'])
    fwd = torch.compile(model) if args.compile else model

    val_ann = COCO_DIR / 'annotations/person_keypoints_val2017.json'
    val_set = CocoTopDown(val_ann, COCO_DIR / 'val2017', train=False, kp_set='body12', stride=model.stride)
    val_loader = ThreadLoader(val_set, 256, collate, workers=8)
    up_set = CocoTopDown(val_ann, COCO_DIR / 'val2017', train=False, subset='upright', kp_set='body12',
                         stride=model.stride)
    up_loader = ThreadLoader(up_set, 256, collate, workers=8)
    gts = load_gts(val_ann, run, 'body12')

    loader = GpuTrainLoader([parse_source(s) for s in args.source], args.batch, device, stride=model.stride,
                            max_rot=args.max_rot, board_aug=not args.no_board_aug, threads=args.loader_threads)
    kpw = torch.tensor(KP_WEIGHTS[args.kp_weight], device=device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.wd)
    steps = args.epochs * len(loader)
    warmup = min(500, steps // 10 + 1)
    sched = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: min(1.0, (s + 1) / warmup) * 0.5 * (1 + math.cos(math.pi * min(s, steps) / steps)))
    scaler = torch.amp.GradScaler()
    best, start = -1.0, 0
    if args.cont and (run / 'last.pt').exists():
        ck = torch.load(run / 'last.pt', map_location=device, weights_only=False)
        model.load_state_dict(ck['model']); opt.load_state_dict(ck['opt'])
        sched.load_state_dict(ck['sched']); scaler.load_state_dict(ck['scaler'])
        start, best = ck['epoch'] + 1, ck['best']
    (run / 'args.json').write_text(json.dumps(dict(vars(args), hw=rep), indent=1))   # rep['mac'] = MACs
    print(f'{args.name}: {len(loader)} steps/epoch x {args.epochs}, sources '
          f'{[(s.path, len(s.rows), s.repeat) for s in loader.sources]}', flush=True)
    log = open(run / 'log.txt', 'a')
    ck_args = dict(vars(args), arch='plain', kp_set='body12', width=128, blocks=8, width_mult=1.0,
                   in_hw=[IN_H, IN_W])  # eval_e2e.load_pose
    for epoch in range(start, args.epochs):
        t0, tot, n = time.time(), torch.zeros(3, device=device), 0
        for x, heat_t, off_t, off_w, vis in loader:
            x = x.contiguous(memory_format=torch.channels_last)
            with torch.autocast('cuda', dtype=torch.float16):
                heat, off = fwd(x)
            loss, lh, lo = loss_fn(heat.float(), off.float(), heat_t, off_t, off_w, kpw)
            opt.zero_grad(set_to_none=True)
            scaler.scale(loss).backward()
            scaler.step(opt); scaler.update(); sched.step()
            tot += torch.stack([loss.detach(), lh, lo]); n += 1
        tot = (tot / max(n, 1)).tolist()
        dt = time.time() - t0
        msg = (f'epoch {epoch + 1}/{args.epochs} loss {tot[0]:.4f} heat {tot[1]:.4f} off {tot[2]:.3f} '
               f'lr {sched.get_last_lr()[0]:.2e} {dt:.0f}s {n * args.batch / dt:.0f} samp/s')
        if (epoch + 1) % args.eval_every == 0 or epoch + 1 == args.epochs:
            res = evaluate(model, val_loader, gts, device, run, 'body12')
            pck = per_joint_pck(model, up_set, up_loader, device)
            msg += ''.join(f'  {k} AP {v[0]:.4f}' for k, v in res.items())
            msg += f'  PCK wri {(pck["Lwri"] + pck["Rwri"]) / 2:.3f} ank {(pck["Lank"] + pck["Rank"]) / 2:.3f}'
            with open(run / 'metrics.jsonl', 'a') as f:
                f.write(json.dumps(dict(epoch=epoch + 1, ap=res, pck=pck)) + '\n')
            if res['upright_body'][0] > best:
                best = res['upright_body'][0]
                torch.save(dict(model=model.state_dict(), args=ck_args, ap=res, pck=pck, epoch=epoch + 1),
                           run / 'best.pt')
        torch.save(dict(model=model.state_dict(), args=ck_args, epoch=epoch, opt=opt.state_dict(),
                        sched=sched.state_dict(), scaler=scaler.state_dict(), best=best), run / 'last.pt')
        print(msg, flush=True)
        log.write(msg + '\n'); log.flush()


if __name__ == '__main__':
    main()
