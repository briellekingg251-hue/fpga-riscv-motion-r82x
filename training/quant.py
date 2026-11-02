"""Post-training quantization simulation for the two hardware routes.

  npu  (route A, existing NPU, original_quantize_pose.py scheme): BN folded,
       per-output-channel symmetric INT8 weights, INT32 bias, per-tensor
       activations with arbitrary scale (Q31 multiplier in hardware); ReLU6
       layers use the full [0, 6] range, heads min/max calibrated.
  pow2 (route B, n111116-style streaming engine): BN folded, per-layer INT8
       weights and activations whose scales are powers of two (requantize =
       arithmetic shift); ReLU ranges calibrated (99.99th percentile).

Fake quantization in float32 (round + clamp at every tensor the hardware stores),
so the result tracks the integer pipeline closely; the bit-exact integer
reference is generated later from the same folded parameters.

  python quant.py --pose runs/poseB_plain_s16_body12/best.pt --mode pow2
"""
import argparse
import copy
import json
import math
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from data import CocoTopDown, collate
from eval_e2e import load_pose
from threadloader import ThreadLoader
from train import COCO_DIR, evaluate, load_gts


def fold(model):
    """Conv-BN-act Sequentials -> list of (conv with bias, act name), then the 2 heads."""
    layers = []
    for blk in model.backbone:
        conv, bn, act = blk
        w = conv.weight.detach()
        std = torch.sqrt(bn.running_var + bn.eps)
        g = bn.weight.detach() / std
        fc = copy.deepcopy(conv)
        fc.weight = nn.Parameter(w * g.reshape(-1, 1, 1, 1))
        fc.bias = nn.Parameter(bn.bias.detach() - bn.running_mean * g)
        layers.append((fc, 'relu6' if isinstance(act, nn.ReLU6) else 'relu'))
    second = model.offset if hasattr(model, 'offset') else model.box     # pose: offset, detector: box
    return layers, [model.heat, second]


def pow2_scale(maxval, levels):
    return 2.0 ** math.ceil(math.log2(max(maxval, 1e-8) / levels))


def qround(x):
    return torch.where(x >= 0, torch.floor(x + 0.5), -torch.floor(-x + 0.5))   # away from zero


class QuantPose(nn.Module):
    """Fake-quantized folded pose net (same forward interface as PoseHeads)."""

    def __init__(self, model, mode, bits=8):
        super().__init__()
        self.stride, self.num_kp, self.mode, self.bits = model.stride, model.num_kp, mode, bits
        self.layers, self.heads = fold(model)
        self.convs = nn.ModuleList([c for c, _ in self.layers] + self.heads)
        self.act_scale = None

    @torch.no_grad()
    def calibrate(self, loader, device, batches=8):
        acts = [[] for _ in range(len(self.layers))]
        head_rng = [[np.inf, -np.inf] for _ in self.heads]
        for b, (x, *_) in enumerate(loader):
            if b == batches:
                break
            y = x.to(device)
            for i, (c, act) in enumerate(self.layers):
                y = F.relu6(c(y)) if act == 'relu6' else F.relu(c(y))
                v = y.flatten()
                acts[i].append(torch.quantile(v[torch.randperm(v.numel(), device=device)[:1 << 20]], 0.9999).item())
            for j, h in enumerate(self.heads):
                o = h(y)
                head_rng[j] = [min(head_rng[j][0], o.min().item()), max(head_rng[j][1], o.max().item())]
        top = 2 ** self.bits - 1                   # unsigned post-ReLU codes
        self.act_scale = []
        for i, (c, act) in enumerate(self.layers):
            hi = 6.0 if (act == 'relu6' and self.mode == 'npu') else float(np.max(acts[i]))
            self.act_scale.append(pow2_scale(hi, top) if self.mode == 'pow2' else hi / top)
        half = 2 ** (self.bits - 1) - 1
        self.head_q = []
        for lo, hi in head_rng:
            if self.mode == 'pow2':                # symmetric, power-of-two
                self.head_q.append((pow2_scale(max(abs(lo), abs(hi)), half), 0.0))
            else:                                  # asymmetric min/max like the NPU heads
                s = (hi - lo) / (2 ** self.bits - 1)
                self.head_q.append((s, round(-2 ** (self.bits - 1) - lo / s)))
        return self

    def qweight(self, conv):
        w = conv.weight
        half = 2 ** (self.bits - 1) - 1
        if self.mode == 'npu':                     # per output channel
            s = w.abs().amax(dim=(1, 2, 3), keepdim=True).clamp(min=1e-8) / half
        else:                                      # one power-of-two scale per layer
            s = torch.tensor(pow2_scale(w.abs().max().item(), half), device=w.device)
        return qround(w / s).clamp(-half, half) * s, s

    def conv(self, conv, x, x_scale):
        wq, ws = self.qweight(conv)
        bs = x_scale * ws.reshape(-1) if ws.dim() else x_scale * ws
        bq = qround(conv.bias / bs) * bs           # INT32 bias at the accumulator scale
        return F.conv2d(x, wq, bq, conv.stride, conv.padding, conv.dilation, conv.groups)

    def forward(self, x):
        half = 2 ** (self.bits - 1) - 1
        xs = 1 / 127 if self.mode == 'npu' else pow2_scale(1.0, half)
        y = qround(x / xs).clamp(-half - 1, half) * xs
        top = 2 ** self.bits - 1
        for (c, act), s in zip(self.layers, self.act_scale):
            z = self.conv(c, y, xs)
            z = F.relu6(z) if act == 'relu6' else F.relu(z)
            y, xs = qround(z / s).clamp(0, top) * s, s
        outs = []
        for h, (s, zp) in zip(self.heads, self.head_q):
            o = self.conv(h, y, xs)
            lo, hi = -2 ** (self.bits - 1), 2 ** (self.bits - 1) - 1
            outs.append((qround(o / s + zp).clamp(lo, hi) - zp) * s)
        return outs[0], outs[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pose', required=True)
    ap.add_argument('--mode', default='pow2', choices=['npu', 'pow2'])
    ap.add_argument('--bits', type=int, default=8)
    ap.add_argument('--workers', type=int, default=12)
    args = ap.parse_args()
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    model, kp_set = load_pose(args.pose, device)
    run = Path(args.pose).parent
    tr_ann = COCO_DIR / 'annotations/person_keypoints_train2017.json'
    calib = CocoTopDown(tr_ann, COCO_DIR / 'train2017', train=False, kp_set=kp_set, stride=model.stride)
    calib.items = calib.items[::150]               # ~1000 persons, deterministic
    qm = QuantPose(model, args.mode, args.bits).to(device).eval()
    qm.calibrate(ThreadLoader(calib, 128, collate, workers=args.workers), device)
    val_ann = COCO_DIR / 'annotations/person_keypoints_val2017.json'
    val_set = CocoTopDown(val_ann, COCO_DIR / 'val2017', train=False, kp_set=kp_set, stride=model.stride)
    loader = ThreadLoader(val_set, 256, collate, workers=args.workers)
    gts = load_gts(val_ann, run, kp_set)
    res = {}
    for name, m in (('float', model), (f'{args.mode}{args.bits}', qm)):
        r = evaluate(m, loader, gts, device, run, kp_set)
        res[name] = {k: round(v[0], 4) for k, v in r.items()}
    print(json.dumps(res, indent=2))
    with open(run / 'quant.jsonl', 'a') as f:
        f.write(json.dumps(dict(pose=args.pose, mode=args.mode, bits=args.bits, ap=res,
                                act_scale=qm.act_scale)) + '\n')


if __name__ == '__main__':
    main()
