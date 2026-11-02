"""Independent numpy re-implementation of the exported integer net; checks the golden files.

  python verify_export.py runs/poseB_plain_s16_body12/export_pow2
"""
import json
import sys
from pathlib import Path

import numpy as np


def conv(a, w, b, stride, groups):
    """a: (C,H,W) int64, w: (O, C/g, k, k); zero pad k//2 on all sides, windows start at -pad."""
    k = w.shape[-1]
    p = k // 2
    a = np.pad(a, ((0, 0), (p, p), (p, p)))
    win = np.lib.stride_tricks.sliding_window_view(a, (k, k), axis=(1, 2))[:, ::stride, ::stride]
    oh = (a.shape[1] - k) // stride + 1
    ow = (a.shape[2] - k) // stride + 1
    win = win[:, :oh, :ow]
    o, cg = w.shape[:2]
    out = np.empty((o, oh, ow), np.int64)
    for g in range(groups):
        oo = slice(g * o // groups, (g + 1) * o // groups)
        out[oo] = np.einsum('chwij,ocij->ohw', win[g * cg:(g + 1) * cg], w[oo].astype(np.int64))
    return out + b.reshape(-1, 1, 1)


def run(meta, P, rgb):
    mode = meta['mode']
    if mode == 'pow2':
        q = rgb.transpose(2, 0, 1).astype(np.int64) - 128
    elif mode == 'pow2u':
        q = rgb.transpose(2, 0, 1).astype(np.int64)
    else:
        v = rgb.transpose(2, 0, 1) / 127.5 - 1
        q = np.clip(np.copysign(np.floor(np.abs(v * 127) + 0.5), v), -128, 127).astype(np.int64)
    outs = []
    for L in meta['layers']:
        i = L['index']
        a = q if L['src'] == -1 else outs[L['src']]
        if mode == 'npu' and L['src'] >= 0:
            a = a - meta['layers'][L['src']]['output_zero']
        acc = conv(a, P[f'w{i}'], P[f'b{i}'].astype(np.int64), L['stride'], L['groups'])
        if mode.startswith('pow2'):
            s = L['shift']
            y = (acc >> s) + ((acc >> (s - 1)) & 1)            # n111116 output_layer.sv
            y = np.clip(y, 0, 255) if L['act'] else np.clip(y, -128, 127)
        else:
            prod = acc * P[f'm{i}'].astype(np.int64).reshape(-1, 1, 1)
            y = np.clip(((prod + np.where(prod < 0, (1 << 30) - 1, 1 << 30)) >> 31) + L['output_zero'], -128, 127)
        outs.append(y)
    return outs


if __name__ == '__main__':
    d = Path(sys.argv[1])
    meta = json.loads((d / 'layers.json').read_text())
    P = dict(np.load(d / 'params.npz'))
    ok = True
    for c in range(4):
        rgb = np.load(d / 'golden' / f'case{c}_rgb.npy')
        gold = np.load(d / 'golden' / f'case{c}_layers.npz')
        outs = run(meta, P, rgb)
        diff = [int(np.abs(o - gold[f'layer{i}']).max()) for i, o in enumerate(outs)]
        print(f'case{c}: max |diff| per layer {diff}')
        ok &= max(diff) == 0
    print('BIT-EXACT' if ok else 'MISMATCH')
