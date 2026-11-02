"""Integer export of a trained pose net for the hardware, with a bit-exact reference.

  python export.py --pose runs/poseB_plain_s16_body12/best.pt --mode pow2   # route B (streaming)
  python export.py --pose runs/poseA_npu_w128_coco17/best.pt --mode npu     # route A (existing NPU)
  python export.py --det runs/det_s16_wide/best.pt --mode pow2               # person detector

Writes <run>/export_<mode>/:
  layers.json     layer table + quantization parameters (see README.md there)
  params.npz      w{i} int8 [cout][cin/groups][kh][kw], b{i} int32, (npu) m{i} int32 Q31 multipliers
  mem/            w{i}.mem (one int8 per line, 2-digit two's-complement hex, same order),
                  b{i}.mem (int32, 8 hex digits per line)
  mat/            (pow2) layer{i}.mat with weight/bias/shift_k/input/output for
                  n111116's CnnHardwareGenerator_pds.py
  golden/         4 fixed crops: RGB input, every layer's integer output, decoded keypoints
  README.md       integer formulas, padding, data order and decode rules

Integer rules
  pow2 (n111116 output_layer.sv): input q = pixel - 128 (int8, exponent -7);
        acc = conv(q_in, w) + b;  y = floor(acc / 2^shift + 1/2)  (= (acc>>>s) + bit s-1);
        ReLU layers: clamp(y, 0, 255) (unsigned 8 bit, next layer reads it as 9-bit signed);
        heads: clamp(y, -128, 127).  real value = q * 2^exp.
  npu  (original_quantize_pose.integer_run): input q = round(127 * (pixel/127.5 - 1));
        a = q_in - z_in; acc = conv(a, w) + b; p = acc * m;
        y = ((p + (p < 0 ? 2^30 - 1 : 2^30)) >> 31) + z_out; clamp(y, -128, 127).
Padding: every 3x3 layer pads one zero row/col on top/left/bottom/right *in the
integer domain after zero-point removal* and stride-2 windows start at -1
(PyTorch).  NOTE: for even input sizes this differs from TF 'SAME' (pad bottom/right
only), which the original integer_run uses; with the old odd 193 input the two agree.
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

from data import KP_SETS, CocoTopDown, collate, decode
from eval_e2e import load_det, load_pose
from quant import fold
from threadloader import ThreadLoader
from train import COCO_DIR, evaluate, load_gts

COCO_NAMES = ['nose', 'l_eye', 'r_eye', 'l_ear', 'r_ear', 'l_shoulder', 'r_shoulder', 'l_elbow', 'r_elbow',
              'l_wrist', 'r_wrist', 'l_hip', 'r_hip', 'l_knee', 'r_knee', 'l_ankle', 'r_ankle']


def layer_list(model, mode, head_names=('heat', 'offset')):
    """Folded float layers as dicts; 'src' = index of the input layer (-1 = image)."""
    body, heads = fold(model)
    out = []
    for i, (c, act) in enumerate(body):
        w, b = c.weight.detach().double().cpu(), c.bias.detach().double().cpu()
        if i == 0 and mode == 'pow2':
            # hardware input q = pixel - 128 with exponent -7; trained input x = (q + 0.5) / 127.5
            b = b + w.sum(dim=(1, 2, 3)) * 0.5 / 127.5
            w = w * 128 / 127.5
        elif i == 0 and mode == 'pow2u':
            # n111116 PEs take unsigned data: q = pixel (0..255), exponent -7; x = q / 127.5 - 1
            b = b - w.sum(dim=(1, 2, 3))
            w = w * 128 / 127.5
        out.append(dict(w=w, b=b, stride=c.stride[0], groups=c.groups, act=act, src=i - 1))
    last = len(out) - 1
    for name, h in zip(head_names, heads):
        out.append(dict(w=h.weight.detach().double().cpu(), b=h.bias.detach().double().cpu(),
                        stride=1, groups=1, act=None, src=last, name=name))
    return out


@torch.no_grad()
def calibrate(model, layers, loader, device, batches=8):
    """99.99th percentile of each ReLU output, min/max of each head (float folded net)."""
    hi = np.zeros(len(layers))
    lo = np.zeros(len(layers))
    for k, (x, *_) in enumerate(loader):
        if k == batches:
            break
        feats = []
        x = x.to(device).double()
        for i, L in enumerate(layers):
            inp = x if L['src'] == -1 else feats[L['src']]
            z = F.conv2d(inp, L['w_float'].to(device), L['b_float'].to(device), L['stride'],
                         L['w'].shape[-1] // 2, 1, L['groups'])
            if L['act'] == 'relu6':
                z = z.clamp(0, 6)
            elif L['act'] == 'relu':
                z = z.clamp(min=0)
            feats.append(z)
            if L['act']:
                v = z.flatten()
                v = v[torch.randperm(v.numel(), device=device)[:1 << 20]].float()
                hi[i] = max(hi[i], torch.quantile(v, 0.9999).item())
            else:
                lo[i], hi[i] = min(lo[i], z.min().item()), max(hi[i], z.max().item())
    return lo, hi


def quantize(layers, lo, hi, mode):
    if mode.startswith('pow2'):
        e_out = {-1: -7}
        for i, L in enumerate(layers):
            e_in = e_out[L['src']]
            ew = math.ceil(math.log2(max(L['w'].abs().max().item(), 1e-12) / 127))
            qw = torch.round(L['w'] / 2 ** ew).clamp(-127, 127)
            qb = torch.round(L['b'] / 2 ** (e_in + ew))
            if L['act']:
                eo = math.ceil(math.log2(max(hi[i], 1e-12) / 255))
            else:
                eo = math.ceil(math.log2(max(abs(lo[i]), abs(hi[i]), 1e-12) / 127))
            shift = eo - (e_in + ew)
            assert shift >= 1, f'layer {i}: shift {shift} < 1 (needs a left shift)'
            L.update(qw=qw, qb=qb, in_exp=e_in, w_exp=ew, out_exp=eo, shift=shift)
            e_out[i] = eo
        return
    zp = {-1: (1 / 127, 0)}
    for i, L in enumerate(layers):
        si, zi = zp[L['src']]
        w = L['w']
        ws = w.abs().amax(dim=(1, 2, 3)) / 127
        ws = torch.maximum(torch.maximum(ws, L['b'].abs() / (si * 2 ** 29)), torch.full_like(ws, 1e-8))
        qw = torch.round(w / ws.reshape(-1, 1, 1, 1)).clamp(-127, 127)
        if L['act'] == 'relu6':
            l, h = 0.0, 6.0
        elif L['act'] == 'relu':
            l, h = 0.0, float(hi[i])
        else:
            l, h = min(0.0, float(lo[i])), max(0.0, float(hi[i]))
        so = max((h - l) / 255, 1e-12)
        zo = int(np.clip(np.rint(-128 - l / so), -128, 127))
        qb = torch.round(L['b'] / (si * ws))
        mult = torch.round(si * ws / so * 2 ** 31)
        assert (mult >= 0).all() and (mult < 2 ** 31).all(), f'layer {i}: Q31 multiplier out of range'
        L.update(qw=qw, qb=qb, mult=mult, in_scale=si, in_zero=zi, out_scale=so, out_zero=zo)
        zp[i] = (so, zo)


class IntNet(torch.nn.Module):
    """Bit-exact integer pipeline (exact integer accumulation in float64, int64 requantize)."""

    def __init__(self, layers, mode, stride, num_kp):
        super().__init__()
        self.layers, self.mode, self.stride, self.num_kp = layers, mode, stride, num_kp

    def to_input(self, x):
        p = torch.round((x.double() + 1) * 127.5).clamp(0, 255)          # dataset tensor -> pixels
        if self.mode == 'pow2':
            return p - 128
        if self.mode == 'pow2u':
            return p
        v = p / 127.5 - 1
        return torch.where(v >= 0, torch.floor(v * 127 + 0.5), -torch.floor(-v * 127 + 0.5)).clamp(-128, 127)

    def run(self, q):
        outs, dev = [], q.device
        for L in self.layers:
            a = q if L['src'] == -1 else outs[L['src']]
            if self.mode == 'npu':
                a = a - (0 if L['src'] == -1 else self.layers[L['src']]['out_zero'])
            acc = F.conv2d(a, L['qw'].to(dev), L['qb'].to(dev), L['stride'], L['qw'].shape[-1] // 2, 1, L['groups'])
            acc = acc.round().long()
            if self.mode.startswith('pow2'):
                s = L['shift']
                y = torch.div(acc + (1 << (s - 1)), 1 << s, rounding_mode='floor')
                y = y.clamp(0, 255) if L['act'] else y.clamp(-128, 127)
            else:
                prod = acc * L['mult'].to(dev).long().reshape(1, -1, 1, 1)
                y = ((prod + torch.where(prod < 0, (1 << 30) - 1, 1 << 30)) >> 31) + L['out_zero']
                y = y.clamp(-128, 127)
            outs.append(y.double())
        return outs

    def dequant(self, i, q):
        L = self.layers[i]
        if self.mode.startswith('pow2'):
            return q * 2.0 ** L['out_exp']
        return (q - L['out_zero']) * L['out_scale']

    def forward(self, x):
        outs = self.run(self.to_input(x))
        return self.dequant(-2, outs[-2]).float(), self.dequant(-1, outs[-1]).float()


def hexline(v, bits):
    return f'{int(v) & ((1 << bits) - 1):0{bits // 4}x}'


def write_outputs(out, layers, mode, intnet, golden_x, in_hw, kind='pose', kp_set='body12'):
    out.mkdir(parents=True, exist_ok=True)
    (out / 'mem').mkdir(exist_ok=True)
    arrays, table = {}, []
    h, w = in_hw
    shapes = {-1: (3, h, w)}
    total_mac = 0
    for i, L in enumerate(layers):
        cin, ih, iw = shapes[L['src']]
        k, s = L['qw'].shape[-1], L['stride']
        oh, ow = (ih + 2 * (k // 2) - k) // s + 1, (iw + 2 * (k // 2) - k) // s + 1
        cout = L['qw'].shape[0]
        shapes[i] = (cout, oh, ow)
        mac = oh * ow * cout * k * k * (cin // L['groups'])
        total_mac += mac
        ltype = L.get('name') or ('dwconv' if L['groups'] > 1 else 'conv') + f'{k}x{k}'
        e = dict(index=i, type=ltype, src=L['src'], cin=cin, cout=cout, groups=L['groups'], kernel=k, stride=s,
                 pad=k // 2, in_hw=[ih, iw], out_hw=[oh, ow], act=L['act'], mac=mac)
        qw, qb = L['qw'].numpy().astype(np.int8), L['qb'].numpy().astype(np.int64)
        assert np.abs(qb).max() < 2 ** 31
        arrays[f'w{i}'], arrays[f'b{i}'] = qw, qb.astype(np.int32)
        if mode.startswith('pow2'):
            e.update(in_exp=L['in_exp'], w_exp=L['w_exp'], out_exp=L['out_exp'], shift=L['shift'],
                     out_bits=8, out_signed=L['act'] is None)
        else:
            arrays[f'm{i}'] = L['mult'].numpy().astype(np.int32)
            e.update(input_scale=L['in_scale'], input_zero=L['in_zero'], output_scale=L['out_scale'],
                     output_zero=L['out_zero'])
        table.append(e)
        (out / 'mem' / f'w{i}.mem').write_text('\n'.join(hexline(v, 8) for v in qw.reshape(-1)) + '\n')
        (out / 'mem' / f'b{i}.mem').write_text('\n'.join(hexline(v, 32) for v in qb.reshape(-1)) + '\n')
    np.savez_compressed(out / 'params.npz', **arrays)
    meta = dict(kind=kind, mode=mode, input=dict(h=h, w=w, order='RGB, row-major, pixel uint8',
                quant={'pow2': 'q = pixel - 128 (int8)', 'pow2u': 'q = pixel (uint8)',
                       'npu': 'q = round(127*(pixel/127.5-1))'}[mode]),
                stride=intnet.stride, params=int(sum(a.size for k, a in arrays.items() if k[0] == 'w')),
                total_mac=int(total_mac), layers=table)
    if kind == 'pose':
        idx = KP_SETS[kp_set]
        meta.update(keypoints=[COCO_NAMES[k] for k in idx],
                    heads=dict(heat=f'layer {len(layers) - 2}: {len(idx)} ch logits',
                               offset=f'layer {len(layers) - 1}: {len(idx)} ch dy then {len(idx)} ch dx, input px'))
    else:
        meta.update(heads=dict(heat=f'layer {len(layers) - 2}: 1 ch person-centre logit',
                               box=f'layer {len(layers) - 1}: 4 ch dy, dx (input px from cell centre), '
                                   'log(h), log(w) (input px)'))
    (out / 'layers.json').write_text(json.dumps(meta, indent=1))

    gold = out / 'golden'
    gold.mkdir(exist_ok=True)
    q = intnet.to_input(golden_x)
    outs = [o.cpu() for o in intnet.run(q)]
    q, golden_x = q.cpu(), golden_x.cpu()
    for c in range(golden_x.shape[0]):
        pix = torch.round((golden_x[c].double() + 1) * 127.5).clamp(0, 255).byte().permute(1, 2, 0).numpy()
        np.save(gold / f'case{c}_rgb.npy', pix)
        (gold / f'case{c}_rgb.hex').write_text('\n'.join(f'{r:02x}{g:02x}{b:02x}' for r, g, b in pix.reshape(-1, 3)) + '\n')
        np.savez_compressed(gold / f'case{c}_layers.npz', **{f'layer{i}': o[c].long().numpy() for i, o in enumerate(outs)})
        for name, li in (('heat', len(layers) - 2), ('offset' if kind == 'pose' else 'box', len(layers) - 1)):
            (gold / f'case{c}_{name}.hex').write_text(
                '\n'.join(hexline(v, 8) for v in outs[li][c].long().reshape(-1).tolist()) + '\n')
        heat, off = intnet.dequant(-2, outs[-2][c:c + 1]), intnet.dequant(-1, outs[-1][c:c + 1])
        if kind == 'pose':
            pts, score = decode(heat.float(), off.float(), intnet.stride)
            kp = {meta['keypoints'][j]: [round(float(pts[0, j, 0]), 2), round(float(pts[0, j, 1]), 2),
                                         round(float(score[0, j]), 3)] for j in range(len(idx))}
            (gold / f'case{c}_keypoints.json').write_text(json.dumps(kp, indent=1))
        else:
            import det as D
            boxes = D.decode_boxes(heat.float(), off.float(), intnet.stride, k=3, thresh=0.0)[0]
            (gold / f'case{c}_boxes.json').write_text(json.dumps(
                [dict(x0=round(b[0], 2), y0=round(b[1], 2), x1=round(b[2], 2), y1=round(b[3], 2),
                      score=round(b[4], 4)) for b in boxes], indent=1))
    if mode.startswith('pow2'):
        from scipy.io import savemat
        (out / 'mat').mkdir(exist_ok=True)
        for i, L in enumerate(layers):
            src = q if L['src'] == -1 else outs[L['src']]
            savemat(out / 'mat' / f'layer{i}.mat', dict(
                weight=L['qw'].numpy().astype(np.int32), bias=L['qb'].numpy().astype(np.int64),
                shift_k=np.array([[L['shift']]]), input=src[:1].long().numpy(), output=outs[i][:1].long().numpy()))
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pose', default='')
    ap.add_argument('--det', default='')
    ap.add_argument('--mode', default='pow2', choices=['pow2', 'pow2u', 'npu'],
                    help='pow2: shift requant, int8 input; pow2u: same, unsigned pixel input (n111116 PE); '
                         'npu: existing NPU Q31 scheme')
    ap.add_argument('--workers', type=int, default=12)
    ap.add_argument('--no-eval', action='store_true')
    args = ap.parse_args()
    assert bool(args.pose) != bool(args.det), 'give exactly one of --pose / --det'
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    tr_ann = COCO_DIR / 'annotations/person_keypoints_train2017.json'
    val_ann = COCO_DIR / 'annotations/person_keypoints_val2017.json'
    if args.pose:
        model, kp_set = load_pose(args.pose, device)
        kind, ckpt, heads = 'pose', args.pose, ('heat', 'offset')
        calib = CocoTopDown(tr_ann, COCO_DIR / 'train2017', train=False, kp_set=kp_set, stride=model.stride)
        calib.items = calib.items[::150]
        val_set = CocoTopDown(val_ann, COCO_DIR / 'val2017', train=False, kp_set=kp_set, stride=model.stride)
        col = collate
    else:
        import det as D
        model, kp_set = load_det(args.det, device), None
        kind, ckpt, heads = 'det', args.det, ('heat', 'box')
        calib = D.CocoPersons(tr_ann, COCO_DIR / 'train2017', train=False, stride=model.stride)
        calib.ids = calib.ids[::100]
        val_set = D.CocoPersons(val_ann, COCO_DIR / 'val2017', train=False, stride=model.stride)
        col = D.collate
    layers = layer_list(model, args.mode, heads)
    for L in layers:      # calibration runs the folded float net on the hardware input mapping
        L['w_float'], L['b_float'] = L['w'], L['b']
    if args.mode.startswith('pow2'):
        # undo the input folding for float calibration on dataset tensors x = p/127.5 - 1
        L0 = layers[0]
        L0['w_float'] = L0['w'] * 127.5 / 128
        if args.mode == 'pow2':
            L0['b_float'] = L0['b'] - L0['w_float'].sum(dim=(1, 2, 3)) * 0.5 / 127.5
        else:
            L0['b_float'] = L0['b'] + L0['w_float'].sum(dim=(1, 2, 3))
    lo, hi = calibrate(model, layers, ThreadLoader(calib, 128, col, workers=args.workers), device)
    quantize(layers, lo, hi, args.mode)
    intnet = IntNet(layers, args.mode, model.stride, getattr(model, 'num_kp', 1))
    out = Path(ckpt).parent / f'export_{args.mode}'
    golden_x = torch.stack([val_set[i][0] for i in (0, 100, 1000, 3000)]).to(device)
    meta = write_outputs(out, layers, args.mode, intnet, golden_x, tuple(golden_x.shape[2:]), kind, kp_set)
    print(f'exported {len(layers)} layers, {meta["params"]} weights, {meta["total_mac"] / 1e6:.1f}M MAC -> {out}')
    if args.no_eval:
        return
    loader = ThreadLoader(val_set, 128, col, workers=args.workers)
    res = {}
    if kind == 'pose':
        gts = load_gts(val_ann, out, kp_set)
        for name, m in (('float', model), ('integer', intnet)):
            r = evaluate(m, loader, gts, device, out, kp_set)
            res[name] = {k: round(v[0], 4) for k, v in r.items()}
    else:
        from pycocotools.coco import COCO
        from subsets import write_subset
        gt, single = COCO(str(val_ann)), COCO(str(write_subset(val_ann, 'single', out)))
        for name, m in (('float', model), ('integer', intnet)):
            r = D.evaluate(m, loader, gt, single, device, out / 'val_det.json')
            res[name] = {k: round(v, 4) for k, v in r.items()}
    print(json.dumps(res, indent=2))
    (out / 'ap.json').write_text(json.dumps(res, indent=2))


if __name__ == '__main__':
    main()
