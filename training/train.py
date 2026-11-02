"""Train / evaluate the pose nets on COCO keypoints (top-down, ground-truth person boxes).

  python train.py --epochs 1 --limit 2000          # smoke test
  python train.py --epochs 140 --width 128          # full run
  python train.py --eval-only --resume runs/x/best.pt
"""
import argparse
import json
import os
import math
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval
from torch.utils.data import ConcatDataset, Subset

from threadloader import ThreadLoader

from data import CocoTopDown, collate, decode, to_coco17, to_image
from model import build, macs, receptive_field
from subsets import write_subset

COCO_DIR = Path(os.environ.get('COCO_DIR', str(Path(__file__).resolve().parents[1] / 'data/coco')))


def loss_fn(heat_logit, off_pred, heat_t, off_t, off_w, vis):
    # focal-style BCE on the Gaussian targets (CenterNet), keypoint-masked
    p = heat_logit.sigmoid().clamp(1e-4, 1 - 1e-4)
    pos = heat_t.ge(0.99).float()
    neg_w = (1 - heat_t) ** 4
    l_pos = -(pos * (1 - p) ** 2 * torch.log(p)).sum()
    l_neg = -((1 - pos) * neg_w * p ** 2 * torch.log(1 - p)).sum()
    n_pos = pos.sum().clamp(min=1)
    l_heat = (l_pos + l_neg) / n_pos
    w = torch.cat([off_w, off_w], 1)
    l_off = (F.smooth_l1_loss(off_pred, off_t, reduction='none', beta=1.0) * w).sum() / w.sum().clamp(min=1)
    return l_heat + 0.1 * l_off, l_heat.item(), l_off.item()


def coco_ap(gt, results, out_json):
    json.dump(results, open(out_json, 'w'))
    if not results:
        return 0.0, 0.0
    ev = COCOeval(gt, gt.loadRes(str(out_json)), 'keypoints')
    ev.params.imgIds = sorted({r['image_id'] for r in results})
    ev.evaluate(); ev.accumulate(); ev.summarize()
    return float(ev.stats[0]), float(ev.stats[1])          # AP, AP50


@torch.no_grad()
def evaluate(model, loader, gts, device, run, kp_set):
    """One inference pass over val, scored on each GT subset: {name: (COCO, ann ids)}."""
    model.eval()
    results = []
    for x, *_, meta in loader:
        heat, off = model(x.to(device, non_blocking=True))
        pts, score = decode(heat.float(), off.float(), model.stride)
        prob = score.sigmoid().cpu().numpy()
        pts = pts.cpu().numpy()
        for i, m in enumerate(meta):
            xy, p = to_coco17(to_image(pts[i], m['center'], m['size']), prob[i], kp_set)
            kps = np.c_[xy, p].reshape(-1).tolist()
            results.append(dict(image_id=m['image_id'], category_id=1, keypoints=kps,
                                score=float(prob[i].mean()), ann_id=m['ann_id']))
    model.train()
    return {name: coco_ap(gt, [r for r in results if r['ann_id'] in ids], run / f'val_{name}.json')
            for name, (gt, ids) in gts.items()}


def load_gts(val_ann, run, kp_set):
    names = ['all_body', 'upright_body'] + (['all', 'upright'] if kp_set == 'coco17' else [])
    gts = {}
    for name in names:
        gt = COCO(str(write_subset(val_ann, name, run)))
        gts[name] = (gt, set(gt.anns))
    return gts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--arch', default='npu', choices=['npu', 'plain'])
    ap.add_argument('--kp-set', default='coco17', choices=['coco17', 'body12'])
    ap.add_argument('--width', type=int, default=128, help='npu: deep-block width')
    ap.add_argument('--blocks', type=int, default=8, help='npu: deep blocks at stride 8')
    ap.add_argument('--cfg', default='s8', help='plain: layer plan in model.PLAIN_CFGS')
    ap.add_argument('--width-mult', type=float, default=1.0, help='plain: channel multiplier')
    ap.add_argument('--eval-every', type=int, default=10)
    ap.add_argument('--epochs', type=int, default=140)
    ap.add_argument('--batch', type=int, default=128)
    ap.add_argument('--lr', type=float, default=2e-3)
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--board-aug', action='store_true')
    ap.add_argument('--cpu-threads', type=int, default=2)
    ap.add_argument('--limit', type=int, default=0, help='use only N training samples (smoke test)')
    ap.add_argument('--train-split', default='train2017', help='train2017, or val2017 for a pipeline test')
    ap.add_argument('--train-subset', default='all', choices=['all', 'upright'])
    ap.add_argument('--max-rot', type=float, default=30.0, help='rotation augmentation limit, degrees')
    ap.add_argument('--extra', action='append', default=[],
                    help='extra training set "ann.json|img_dir|repeat" (e.g. pseudo-labelled board video)')
    ap.add_argument('--coco-frac', type=float, default=1.0, help='fixed random fraction of COCO train to use')
    ap.add_argument('--resume', default='')
    ap.add_argument('--continue', dest='cont', action='store_true',
                    help='continue the run in runs/<name> from its last.pt (after a crash)')
    ap.add_argument('--eval-only', action='store_true')
    ap.add_argument('--name', default='')
    args = ap.parse_args()
    torch.set_num_threads(args.cpu_threads)
    torch.set_num_interop_threads(1)

    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    run = Path('runs') / (args.name or f'{args.arch}_{args.kp_set}_{time.strftime("%m%d_%H%M")}')
    run.mkdir(parents=True, exist_ok=True)
    num_kp = 17 if args.kp_set == 'coco17' else 12
    model = build(args.arch, num_kp, args.width, args.blocks, args.cfg, args.width_mult)
    print(f'model: {args.arch} {args.kp_set} stride {model.stride}, '
          f'{sum(p.numel() for p in model.parameters()) / 1e6:.3f}M params, {macs(model) / 1e6:.1f}M MAC, '
          f'RF {receptive_field(model)}')
    model = model.to(device)
    if args.resume:
        model.load_state_dict(torch.load(args.resume, map_location=device)['model'])

    val_ann = COCO_DIR / 'annotations/person_keypoints_val2017.json'
    val_set = CocoTopDown(val_ann, COCO_DIR / 'val2017', train=False, kp_set=args.kp_set, stride=model.stride)
    val_loader = ThreadLoader(val_set, 256, collate, workers=args.workers)
    gts = load_gts(val_ann, run, args.kp_set)
    if args.eval_only:
        print(evaluate(model, val_loader, gts, device, run, args.kp_set))
        return

    tr_ann = COCO_DIR / f'annotations/person_keypoints_{args.train_split}.json'
    train_set = CocoTopDown(tr_ann, COCO_DIR / args.train_split, train=True,
                            subset=args.train_subset, max_rot=args.max_rot, kp_set=args.kp_set, stride=model.stride,
                            board_aug=args.board_aug)
    if args.coco_frac < 1:
        rng = np.random.default_rng(0)
        train_set.items = [train_set.items[i] for i in
                           sorted(rng.choice(len(train_set), int(len(train_set) * args.coco_frac), replace=False))]
    if args.limit:
        train_set = Subset(train_set, list(range(min(args.limit, len(train_set)))))
    parts = [train_set]
    for spec in args.extra:
        ann, img_dir, rep = spec.split('|')
        ex = CocoTopDown(ann, img_dir, train=True, max_rot=args.max_rot, kp_set=args.kp_set, stride=model.stride,
                         board_aug=args.board_aug)
        parts += [ex] * int(rep)
        print(f'extra {ann}: {len(ex)} persons x {rep}')
    if len(parts) > 1:
        train_set = ConcatDataset(parts)
    loader = ThreadLoader(train_set, args.batch, collate, workers=args.workers, shuffle=True, drop_last=True)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    steps = args.epochs * len(loader)
    warmup = min(500, steps // 10 + 1)
    sched = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: min(1.0, (s + 1) / warmup) * 0.5 * (1 + math.cos(math.pi * min(s, steps) / steps)))
    scaler = torch.amp.GradScaler(enabled=device == 'cuda')
    best, log, start = -1.0, open(run / 'log.txt', 'a'), 0
    if args.cont and (run / 'last.pt').exists():
        ck = torch.load(run / 'last.pt', map_location=device)
        model.load_state_dict(ck['model'])
        start = ck['epoch'] + 1
        if 'opt' in ck:
            opt.load_state_dict(ck['opt']); sched.load_state_dict(ck['sched']); scaler.load_state_dict(ck['scaler'])
            best = ck['best']
        else:                                  # older checkpoint: weights only, fresh Adam moments
            for _ in range(start * len(loader)):
                sched.step()
            if (run / 'best.pt').exists():
                r = torch.load(run / 'best.pt', map_location='cpu')
                best = r['ap']['upright_body'][0] if 'ap' in r else r['res']['single_top1_hit']
        print(f'continuing at epoch {start + 1}, best {best:.4f}, lr {sched.get_last_lr()[0]:.2e}', flush=True)
    print(f'train samples {len(train_set)}, val samples {len(val_set)}, steps {steps}, run {run}')
    for epoch in range(start, args.epochs):
        t0, tot = time.time(), np.zeros(3)
        for i, (x, heat_t, off_t, off_w, vis, _) in enumerate(loader):
            x, heat_t, off_t, off_w, vis = (t.to(device, non_blocking=True) for t in (x, heat_t, off_t, off_w, vis))
            with torch.autocast(device, dtype=torch.float16, enabled=device == 'cuda'):
                heat, off = model(x)
            loss, lh, lo = loss_fn(heat.float(), off.float(), heat_t, off_t, off_w, vis)
            opt.zero_grad(set_to_none=True)
            scaler.scale(loss).backward()
            scaler.step(opt); scaler.update(); sched.step()
            tot += (loss.item(), lh, lo)
            if i % 50 == 0:
                print(f'epoch {epoch+1} step {i+1}/{len(loader)} loss {loss.item():.4f}', flush=True)
        msg = f'epoch {epoch + 1}/{args.epochs} loss {tot[0] / (i + 1):.4f} heat {tot[1] / (i + 1):.4f} ' \
              f'off {tot[2] / (i + 1):.3f} lr {sched.get_last_lr()[0]:.2e} {time.time() - t0:.0f}s'
        if (epoch + 1) % args.eval_every == 0 or epoch + 1 == args.epochs:
            res = evaluate(model, val_loader, gts, device, run, args.kp_set)
            msg += ''.join(f'  {k} AP {v[0]:.4f} AP50 {v[1]:.4f}' for k, v in res.items())
            if res['upright_body'][0] > best:     # deployment scene: upright persons, body joints
                best = res['upright_body'][0]
                torch.save(dict(model=model.state_dict(), args=vars(args), ap=res), run / 'best.pt')
        torch.save(dict(model=model.state_dict(), args=vars(args), epoch=epoch, opt=opt.state_dict(),
                        sched=sched.state_dict(), scaler=scaler.state_dict(), best=best), run / 'last.pt')
        print(msg, flush=True)
        log.write(msg + '\n'); log.flush()


if __name__ == '__main__':
    main()
