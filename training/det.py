"""Tiny single-class person detector for the FPGA (stage 1 of detect -> crop -> pose).

Whole camera frame (1280x720) downscaled to 160x96 (H 96 incl. letterbox rows).
Plain 3x3 conv + ReLU chain (streaming-dataflow friendly, same ops as PlainPose),
two 1x1 heads like the NPU:
  heat : 1 channel, person-centre logit (CenterNet)
  box  : 4 channels, (dy, dx) centre offset from the cell centre in input px,
         log(h), log(w) of the box in input px
Targets/eval use COCO person boxes (person_keypoints_*.json carries all of them).

  python det.py --epochs 60                     # train on train2017
  python det.py --train-split val2017 --limit 2000 --epochs 2 --name det_smoke
"""
import argparse
import json
import os
import math
import random
import time
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval
from torch.utils.data import ConcatDataset, Dataset, Subset

from model import conv_bn, macs, receptive_field
from anncache import slim_coco
from subsets import write_subset
from threadloader import ThreadLoader

cv2.setNumThreads(0)
COCO_DIR = Path(os.environ.get('COCO_DIR', str(Path(__file__).resolve().parents[1] / 'data/coco')))
DET_H, DET_W = 96, 160
DET_CFGS = {
    # (out_channels, stride) per 3x3 conv; output stride = product of strides
    's16': [(16, 2), (32, 2), (32, 1), (64, 2), (64, 1), (64, 2), (64, 1), (64, 1)],
    's16_small': [(8, 2), (16, 2), (16, 1), (32, 2), (32, 1), (48, 2), (48, 1), (48, 1)],
    # more capacity in the deep stride-16 stage (fewer false positives on objects)
    's16_wide': [(16, 2), (32, 2), (32, 1), (64, 2), (64, 1), (80, 2), (80, 1), (80, 1), (80, 1)],
    # D1 keeps the wide model's depth; 64 divides the adjacent streaming groups.
    's16_d1': [(16, 2), (32, 2), (32, 1), (64, 2), (64, 1), (64, 2), (64, 1), (64, 1), (64, 1)],
}


# Existing-NPU operator set (pose_network.sv): first full 3x3 conv s2 (16 ch), then
# depthwise 3x3 + pointwise 1x1 blocks with ReLU6, two 1x1 heads.  (out_channels, dw stride)
DET_NPU_CFGS = {
    'npu_s16': [(32, 1), (48, 2), (48, 1), (64, 2), (64, 1), (96, 2), (96, 1), (96, 1), (96, 1)],
}


class PersonDet(nn.Module):
    def __init__(self, cfg='s16'):
        super().__init__()
        if cfg in DET_NPU_CFGS:
            layers, cin, self.stride = [conv_bn(3, 16, 3, 2)], 16, 2
            for cout, s in DET_NPU_CFGS[cfg]:
                layers += [conv_bn(cin, cin, 3, s, groups=cin), conv_bn(cin, cout, 1, 1)]
                cin, self.stride = cout, self.stride * s
        else:
            layers, cin, self.stride = [], 3, 1
            for cout, s in DET_CFGS[cfg]:
                layers.append(conv_bn(cin, cout, 3, s, act=nn.ReLU))
                cin, self.stride = cout, self.stride * s
        self.backbone = nn.Sequential(*layers)
        self.heat = nn.Conv2d(cin, 1, 1)
        self.box = nn.Conv2d(cin, 4, 1)
        nn.init.constant_(self.heat.bias, -4.0)

    def forward(self, x):
        f = self.backbone(x)
        return self.heat(f), self.box(f)


def frame_matrix(cx, cy, w, flip=False):
    """Affine: source window centred (cx, cy), width w (height w*H/W) -> DET_W x DET_H."""
    s = DET_W / w
    m = np.array([[s, 0, DET_W / 2 - s * cx], [0, s, DET_H / 2 - s * cy]], np.float32)
    if flip:
        m = np.array([[-1, 0, DET_W - 1], [0, 1, 0]], np.float32) @ np.vstack([m, [0, 0, 1]])
    return m


def letterbox(h, w):
    """Whole image fitted inside the input window (what the board does with the camera frame)."""
    win_w = max(w, h * DET_W / DET_H)
    return w / 2, h / 2, win_w


class CocoPersons(Dataset):
    def __init__(self, ann_file, img_dir, train=True, stride=16, img_ids=None, board_aug=False):
        d = slim_coco(ann_file)
        self.img_dir, self.train, self.stride = img_dir, train, stride
        self.board_aug = board_aug
        self.oh, self.ow = DET_H // stride, DET_W // stride
        self.files = {i: (name, h, w) for i, name, h, w in d['images']}
        self.anns = {}
        for a in d['persons']:
            self.anns.setdefault(a['image_id'], []).append(dict(bbox=a['bbox'], iscrowd=a['iscrowd']))
        ids = sorted(self.files) if img_ids is None else sorted(img_ids)
        if train:      # keep person images plus ~10% person-free images as negatives
            ids = [i for i in ids if i in self.anns or random.random() < 0.1]
        self.ids = ids
        del d

    def __len__(self):
        return len(self.ids)

    def __getitem__(self, i):
        iid = self.ids[i]
        name, h, w = self.files[iid]
        img = cv2.imread(f'{self.img_dir}/{name}', cv2.IMREAD_COLOR)[:, :, ::-1]
        cx, cy, win = letterbox(h, w)
        flip = False
        if self.train:
            if random.random() < 0.6:      # zoom: person filling the frame, like standing near the camera
                win = win * random.uniform(0.35, 1.0)
            else:
                win = win * random.uniform(1.0, 1.4)
            cx = random.uniform(min(win / 2, w - win / 2), max(win / 2, w - win / 2))
            win_h = win * DET_H / DET_W
            cy = random.uniform(min(win_h / 2, h - win_h / 2), max(win_h / 2, h - win_h / 2))
            flip = random.random() < 0.5
        m = frame_matrix(cx, cy, win, flip)
        x = cv2.warpAffine(np.ascontiguousarray(img), m, (DET_W, DET_H), flags=cv2.INTER_AREA,
                           borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0))
        if self.train:
            x = color_jitter(x)
            if self.board_aug:
                from data import CocoTopDown
                x = CocoTopDown.board_quality(x)
        boxes, crowd = self.boxes(self.anns.get(iid, []), m)
        heat, box, box_w, ignore = self.targets(boxes, crowd)
        t = torch.from_numpy(np.ascontiguousarray(x.transpose(2, 0, 1))).float() / 127.5 - 1
        return t, heat, box, box_w, ignore, dict(image_id=iid, m=m)

    @staticmethod
    def boxes(anns, m):
        out, crowd = [], []
        for a in anns:
            x, y, bw, bh = a['bbox']
            pts = np.array([[x, y, 1], [x + bw, y, 1], [x, y + bh, 1], [x + bw, y + bh, 1]]) @ m.T
            x0, y0 = pts.min(0)
            x1, y1 = pts.max(0)
            full = (x1 - x0) * (y1 - y0)
            cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x1, DET_W), min(y1, DET_H)
            if cx1 <= cx0 or cy1 <= cy0:
                continue
            if a.get('iscrowd', 0):
                crowd.append((cx0, cy0, cx1, cy1))
            elif (cx1 - cx0) * (cy1 - cy0) >= 0.4 * full and (cx1 - cx0) >= 3 and (cy1 - cy0) >= 6:
                out.append((cx0, cy0, cx1, cy1))
        return out, crowd

    def targets(self, boxes, crowd):
        s, oh, ow = self.stride, self.oh, self.ow
        ys, xs = np.mgrid[0:oh, 0:ow].astype(np.float32)
        heat = np.zeros((1, oh, ow), np.float32)
        box = np.zeros((4, oh, ow), np.float32)
        box_w = np.zeros((1, oh, ow), np.float32)
        ignore = np.zeros((1, oh, ow), np.float32)
        for x0, y0, x1, y1 in crowd:
            ignore[0, int(y0 // s):int(math.ceil(y1 / s)), int(x0 // s):int(math.ceil(x1 / s))] = 1
        for x0, y0, x1, y1 in sorted(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1])):
            bcx, bcy, bw, bh = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
            gx, gy = (bcx - (s - 1) / 2) / s, (bcy - (s - 1) / 2) / s
            rx, ry = min(max(round(gx), 0), ow - 1), min(max(round(gy), 0), oh - 1)
            sig = max(0.5, 0.15 * math.sqrt(bw * bh) / s)
            heat[0] = np.maximum(heat[0], np.exp(-((xs - rx) ** 2 + (ys - ry) ** 2) / (2 * sig ** 2)))
            box[:, ry, rx] = (bcy - (ry * s + (s - 1) / 2), bcx - (rx * s + (s - 1) / 2),
                              math.log(bh), math.log(bw))     # larger boxes drawn last win the cell
            box_w[0, ry, rx] = 1
        ignore[heat >= 0.99] = 0
        return tuple(torch.from_numpy(a) for a in (heat, box, box_w, ignore))


def color_jitter(img):
    img = img.astype(np.float32)
    img = img * np.random.uniform(0.6, 1.4) + np.random.uniform(-30, 30)
    gray = img.mean(axis=2, keepdims=True)
    img = gray + (img - gray) * np.random.uniform(0.6, 1.4)
    img = img * np.random.uniform(0.85, 1.15, 3)
    if random.random() < 0.3:
        img = cv2.GaussianBlur(img, (3, 3), np.random.uniform(0.3, 1.2))
    return np.clip(img, 0, 255).astype(np.uint8)


def collate(batch):
    *t, meta = zip(*batch)
    return (*[torch.stack(a) for a in t], list(meta))


def det_loss(heat_logit, box_pred, heat_t, box_t, box_w, ignore):
    p = heat_logit.sigmoid().clamp(1e-4, 1 - 1e-4)
    pos = heat_t.ge(0.99).float()
    keep = 1 - ignore
    l_pos = -(pos * (1 - p) ** 2 * torch.log(p)).sum()
    l_neg = -(keep * (1 - pos) * (1 - heat_t) ** 4 * p ** 2 * torch.log(1 - p)).sum()
    n = pos.sum().clamp(min=1)
    l_heat = (l_pos + l_neg) / n
    w = box_w.expand_as(box_pred)
    l1 = F.smooth_l1_loss(box_pred, box_t, reduction='none', beta=1.0)
    l_off = (l1[:, :2] * w[:, :2]).sum() / n
    l_size = (l1[:, 2:] * w[:, 2:]).sum() / n
    return l_heat + 0.1 * l_off + 1.0 * l_size, l_heat.item(), l_off.item(), l_size.item()


def decode_boxes(heat_logit, box_pred, stride, k=20, thresh=0.02):
    """Peaks (3x3 max) -> list per image of (x0, y0, x1, y1, score) in input px."""
    p = heat_logit.sigmoid()
    peak = (p == F.max_pool2d(p, 3, 1, 1)).float() * p
    n, _, oh, ow = p.shape
    score, idx = peak.reshape(n, -1).topk(min(k, oh * ow))
    out = []
    for b in range(n):
        dets = []
        for sc, i in zip(score[b].tolist(), idx[b].tolist()):
            if sc < thresh:
                break
            r, c = divmod(i, ow)
            dy, dx, lh, lw = box_pred[b, :, r, c].tolist()
            cy, cx = r * stride + (stride - 1) / 2 + dy, c * stride + (stride - 1) / 2 + dx
            bh, bw = math.exp(min(lh, 8)), math.exp(min(lw, 8))
            dets.append((cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2, sc))
        out.append(dets)
    return out


def iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    return inter / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter + 1e-9)


@torch.no_grad()
def evaluate(model, loader, gt, single_gt, device, out_json):
    """COCO person bbox AP on all val images + top-1 hit rate on single-upright-person images."""
    model.eval()
    results = []
    for x, *_, meta in loader:
        heat, box = model(x.to(device))
        for dets, m in zip(decode_boxes(heat.float(), box.float(), model.stride), meta):
            inv = cv2.invertAffineTransform(m['m'])
            for x0, y0, x1, y1, sc in dets:
                (ax, ay), (bx, by) = np.array([[x0, y0, 1], [x1, y1, 1]]) @ inv.T
                results.append(dict(image_id=m['image_id'], category_id=1, score=sc,
                                    bbox=[float(ax), float(ay), float(bx - ax), float(by - ay)]))
    model.train()
    json.dump(results, open(out_json, 'w'))
    stats = np.zeros(12)
    if results:                        # an untrained net may emit nothing above threshold
        ev = COCOeval(gt, gt.loadRes(str(out_json)), 'bbox')
        ev.params.catIds = [1]
        ev.evaluate(); ev.accumulate(); ev.summarize()
        stats = ev.stats
    top = {}
    for r in results:
        if r['image_id'] not in top or r['score'] > top[r['image_id']]['score']:
            top[r['image_id']] = r
    hits, ious = 0, []
    for a in single_gt.dataset['annotations']:
        r = top.get(a['image_id'])
        v = 0.0
        if r:
            bx, gx = r['bbox'], a['bbox']
            v = iou((bx[0], bx[1], bx[0] + bx[2], bx[1] + bx[3]), (gx[0], gx[1], gx[0] + gx[2], gx[1] + gx[3]))
        ious.append(v)
        hits += v >= 0.5
    n = max(1, len(ious))
    return dict(AP=float(stats[0]), AP50=float(stats[1]), AP_large=float(stats[5]),
                single_top1_hit=hits / n, single_mean_iou=float(np.mean(ious)) if ious else 0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cfg', default='s16', choices=list(DET_CFGS) + list(DET_NPU_CFGS))
    ap.add_argument('--epochs', type=int, default=60)
    ap.add_argument('--batch', type=int, default=128)
    ap.add_argument('--lr', type=float, default=2e-3)
    ap.add_argument('--workers', type=int, default=10)
    ap.add_argument('--cpu-threads', type=int, default=2)
    ap.add_argument('--board-aug', action='store_true')
    ap.add_argument('--coco-frac', type=float, default=1.0)
    ap.add_argument('--extra', action='append', default=[], help='annotation|image_dir|repeat')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--train-split', default='train2017')
    ap.add_argument('--eval-every', type=int, default=5)
    ap.add_argument('--resume', default='')
    ap.add_argument('--continue', dest='cont', action='store_true',
                    help='continue the run in runs/<name> from its last.pt (after a crash)')
    ap.add_argument('--eval-only', action='store_true')
    ap.add_argument('--name', default='')
    args = ap.parse_args()
    if args.cpu_threads < 1:
        ap.error('--cpu-threads must be positive')
    if not 0 < args.coco_frac <= 1:
        ap.error('--coco-frac must be in (0, 1]')
    # Keep the negative-image subset and loader length stable after --continue.
    random.seed(0)
    np.random.seed(0)
    torch.manual_seed(0)
    torch.set_num_threads(args.cpu_threads)
    torch.set_num_interop_threads(1)

    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    run = Path('runs') / (args.name or f'det_{args.cfg}_{time.strftime("%m%d_%H%M")}')
    run.mkdir(parents=True, exist_ok=True)
    model = PersonDet(args.cfg)
    print(f'det {args.cfg}: stride {model.stride}, {sum(p.numel() for p in model.parameters()) / 1e6:.3f}M params, '
          f'{macs(model, DET_H, DET_W) / 1e6:.1f}M MAC, RF {receptive_field(model)}')
    model = model.to(device)
    if args.resume:
        model.load_state_dict(torch.load(args.resume, map_location=device)['model'])

    val_ann = COCO_DIR / 'annotations/person_keypoints_val2017.json'
    gt = COCO(str(val_ann))
    single_gt = COCO(str(write_subset(val_ann, 'single', run)))
    val_set = CocoPersons(val_ann, COCO_DIR / 'val2017', train=False, stride=model.stride)
    val_loader = ThreadLoader(val_set, 128, collate, workers=args.workers)
    if args.eval_only:
        print(evaluate(model, val_loader, gt, single_gt, device, run / 'val_det.json'))
        return

    tr_ann = COCO_DIR / f'annotations/person_keypoints_{args.train_split}.json'
    train_set = CocoPersons(tr_ann, COCO_DIR / args.train_split, train=True, stride=model.stride,
                            board_aug=args.board_aug)
    if args.coco_frac < 1:
        rng = np.random.default_rng(0)
        train_set.ids = [train_set.ids[i] for i in sorted(rng.choice(
            len(train_set), max(1, int(len(train_set) * args.coco_frac)), replace=False))]
    if args.limit:
        train_set = Subset(train_set, list(range(min(args.limit, len(train_set)))))
    parts = [train_set]
    for spec in args.extra:
        ann, img_dir, rep = spec.split('|')
        if int(rep) < 1:
            ap.error('extra repeat must be positive')
        ex = CocoPersons(ann, img_dir, train=True, stride=model.stride, board_aug=args.board_aug)
        parts += [ex] * int(rep)
        print(f'extra {ann}: {len(ex)} images x {rep}', flush=True)
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
    print(f'train images {len(train_set)}, val images {len(val_set)}, steps {steps}, run {run}', flush=True)
    for epoch in range(start, args.epochs):
        t0, tot = time.time(), np.zeros(4)
        for i, (x, heat_t, box_t, box_w, ignore, _) in enumerate(loader):
            x, heat_t, box_t, box_w, ignore = (t.to(device, non_blocking=True)
                                               for t in (x, heat_t, box_t, box_w, ignore))
            with torch.autocast(device, dtype=torch.float16, enabled=device == 'cuda'):
                heat, box = model(x)
            loss, lh, lo, ls = det_loss(heat.float(), box.float(), heat_t, box_t, box_w, ignore)
            opt.zero_grad(set_to_none=True)
            scaler.scale(loss).backward()
            scaler.step(opt); scaler.update(); sched.step()
            tot += (loss.item(), lh, lo, ls)
            if i % 50 == 0:
                print(f'epoch {epoch + 1} step {i + 1}/{len(loader)} loss {loss.item():.4f}', flush=True)
        tot /= i + 1
        msg = (f'epoch {epoch + 1}/{args.epochs} loss {tot[0]:.4f} heat {tot[1]:.4f} off {tot[2]:.3f} '
               f'size {tot[3]:.3f} lr {sched.get_last_lr()[0]:.2e} {time.time() - t0:.0f}s')
        if (epoch + 1) % args.eval_every == 0 or epoch + 1 == args.epochs:
            res = evaluate(model, val_loader, gt, single_gt, device, run / 'val_det.json')
            msg += '  ' + ' '.join(f'{k} {v:.4f}' for k, v in res.items())
            if res['single_top1_hit'] > best:     # deployment: one person in front of the camera
                best = res['single_top1_hit']
                torch.save(dict(model=model.state_dict(), args=vars(args), res=res), run / 'best.pt')
        torch.save(dict(model=model.state_dict(), args=vars(args), epoch=epoch, opt=opt.state_dict(),
                        sched=sched.state_dict(), scaler=scaler.state_dict(), best=best), run / 'last.pt')
        print(msg, flush=True)
        log.write(msg + '\n'); log.flush()


if __name__ == '__main__':
    main()
