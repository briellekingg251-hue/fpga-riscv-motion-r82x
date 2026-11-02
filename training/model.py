"""Top-down single-person pose networks restricted to FPGA-friendly operators.

Two hardware targets:
  npu   NpuPose  : the existing layer-sequential NPU (pose_network.sv): first 3x3
                   conv s2, 3x3 depthwise s1/s2, 1x1 pointwise, ReLU6, single chain,
                   two 1x1 heads.
  plain PlainPose: a streaming dataflow engine like n111116/CNN_FPGA (one hardware
                   block per layer, line buffers only): plain 3x3 conv (s1/s2) + ReLU,
                   single chain, two 1x1 heads.  No depthwise conv (awkward for a
                   systolic full-conv PE array).
BatchNorm is used for training only and is folded before quantization.

Input 192x128 (H x W) RGB crop.  Heads at the output stride:
  heat   : K channels (logits, sigmoid -> keypoint probability)
  offset : 2K channels (K y then K x, in input pixels, PoseNet layout)
"""
import torch
import torch.nn as nn

import os
# crop input size (H x W, 2:3); POSE_IN=240x160 trades APM (MAC) for detail without adding weights
IN_H, IN_W = (int(v) for v in os.environ.get('POSE_IN', '192x128').split('x'))


def conv_bn(cin, cout, k, stride, groups=1, act=nn.ReLU6):
    return nn.Sequential(nn.Conv2d(cin, cout, k, stride, k // 2, groups=groups, bias=False),
                         nn.BatchNorm2d(cout), act(inplace=True))


class PoseHeads(nn.Module):
    def __init__(self, backbone, cin, num_kp, stride):
        super().__init__()
        self.backbone, self.stride, self.num_kp = backbone, stride, num_kp
        self.heat = nn.Conv2d(cin, num_kp, 1)
        self.offset = nn.Conv2d(cin, 2 * num_kp, 1)
        nn.init.constant_(self.heat.bias, -4.0)       # sparse targets: start near p=0.02

    def forward(self, x):
        f = self.backbone(x)
        return self.heat(f), self.offset(f)


def NpuPose(width=128, deep_blocks=8, num_kp=17):
    """Depthwise-separable chain for the existing NPU, output stride 8."""
    layers = [conv_bn(3, 16, 3, 2)]
    plan = [(32, 1), (64, 2), (64, 1), (width, 2)] + [(width, 1)] * deep_blocks
    cin = 16
    for cout, s in plan:
        layers += [conv_bn(cin, cin, 3, s, groups=cin), conv_bn(cin, cout, 1, 1)]
        cin = cout
    return PoseHeads(nn.Sequential(*layers), cin, num_kp, 8)


PLAIN_CFGS = {
    's16_p1': [(16, 2), (24, 2), (24, 1), (48, 2), (48, 1), (64, 2)] + [(64, 1)] * 4,
    # (out_channels, stride) per 3x3 conv
    's8': [(16, 2), (32, 2), (32, 1), (64, 2)] + [(64, 1)] * 7,
    's16': [(16, 2), (32, 2), (32, 1), (64, 2), (64, 1), (96, 2)] + [(96, 1)] * 4,
    # P2 candidates (n111116 rules: widths in HW_WIDTHS, neighbours 1:1/1:2/2:3, early MAC share capped)
    's16_deep': [(16, 2), (32, 2), (32, 1), (64, 2), (64, 1), (64, 1), (96, 2)] + [(96, 1)] * 4,
    's16_d5': [(16, 2), (32, 2), (32, 1), (64, 2), (64, 1), (96, 2)] + [(96, 1)] * 5,
    # APM-for-accuracy candidates: extra compute at high resolution, few extra weights
    's16_deep_hx': [(16, 2), (32, 2), (32, 1), (32, 1), (64, 2), (64, 1), (64, 1), (96, 2)] + [(96, 1)] * 4,
    # 288x192 needs RF >= 230: one more layer (at 24x16 or at the 96-ch tail)
    's16_hx_r64': [(16, 2), (32, 2), (32, 1), (32, 1), (64, 2), (64, 1), (64, 1), (64, 1), (96, 2)] + [(96, 1)] * 4,
    's16_hx_r96': [(16, 2), (32, 2), (32, 1), (32, 1), (64, 2), (64, 1), (64, 1), (96, 2)] + [(96, 1)] * 5,
    's16_deep_we': [(32, 2), (32, 2), (64, 1), (64, 2), (64, 1), (64, 1), (96, 2)] + [(96, 1)] * 4,
}

HW_WIDTHS = {8, 16, 32, 48, 64, 96, 128}
HW_RATIOS = {(1, 1), (1, 2), (2, 1), (2, 3), (3, 2)}
EARLY_LAYERS, EARLY_MAC_SHARE = 3, 0.30
DRM_BITS = 36 * 1024


def hw_check(cfg, num_kp=12, max_params=0.6e6):
    """n111116 streaming-engine design rules for a PLAIN_CFGS entry -> (ok, report dict)."""
    from math import gcd
    plan = PLAIN_CFGS[cfg]
    errors, cin, h, w, rf, jump, layer_macs = [], 3, IN_H, IN_W, 1, 1, []
    for i, (cout, s) in enumerate(plan):
        if cout not in HW_WIDTHS:
            errors.append(f'layer {i}: width {cout} not in {sorted(HW_WIDTHS)}')
        if i and (cin // gcd(cin, cout), cout // gcd(cin, cout)) not in HW_RATIOS:
            errors.append(f'layer {i}: {cin}->{cout} ratio not 1:1/1:2/2:3')
        h, w = h // s, w // s
        layer_macs.append(h * w * cout * cin * 9)
        rf += 2 * jump
        jump *= s
        cin = cout
    heads = h * w * cin * 3 * num_kp
    total = sum(layer_macs) + heads
    early = sum(layer_macs[:EARLY_LAYERS]) / total
    params = sum(9 * a * b for a, b in zip([3] + [c for c, _ in plan[:-1]], [c for c, _ in plan])) + cin * 3 * num_kp
    if early > EARLY_MAC_SHARE:
        errors.append(f'early {EARLY_LAYERS} layers carry {early:.0%} of MAC (> {EARLY_MAC_SHARE:.0%})')
    if rf < 0.8 * IN_H:
        errors.append(f'receptive field {rf} < 80% of input height')
    if params > max_params:
        errors.append(f'{params} weights > budget {max_params:.0f}')
    rep = dict(cfg=cfg, stride=jump, weights=params, drm_weights=-(-params * 8 // DRM_BITS),
               mac=total, early_mac_share=round(early, 3), rf=rf, errors=errors)
    return not errors, rep


def PlainPose(cfg='s8', num_kp=17, width_mult=1.0):
    """Plain 3x3 conv + ReLU chain for a streaming dataflow engine."""
    layers, cin, stride = [], 3, 1
    for cout, s in PLAIN_CFGS[cfg]:
        cout = max(8, int(round(cout * width_mult / 8)) * 8)
        layers.append(conv_bn(cin, cout, 3, s, act=nn.ReLU))
        cin, stride = cout, stride * s
    return PoseHeads(nn.Sequential(*layers), cin, num_kp, stride)


def build(arch, num_kp, width=128, blocks=8, cfg='s8', width_mult=1.0):
    if arch == 'npu':
        return NpuPose(width, blocks, num_kp)
    if arch == 'plain':
        return PlainPose(cfg, num_kp, width_mult)
    raise ValueError(arch)


def macs(model, h=IN_H, w=IN_W):
    """Multiply-accumulates of all convolutions (what the accelerator executes)."""
    total, x = 0, torch.zeros(1, 3, h, w)
    hooks = []

    def hook(m, inp, out):
        nonlocal total
        k = m.kernel_size[0] * m.kernel_size[1]
        total += out.numel() * k * (m.in_channels // m.groups)
    for m in model.modules():
        if isinstance(m, nn.Conv2d):
            hooks.append(m.register_forward_hook(hook))
    was_training = model.training
    with torch.no_grad():
        model.eval()(x)
    model.train(was_training)
    for hk in hooks:
        hk.remove()
    return total


def receptive_field(model):
    """Receptive field (input px) of one output cell, from the conv chain."""
    rf, jump = 1, 1
    for m in model.modules():
        if isinstance(m, nn.Conv2d):
            rf += (m.kernel_size[0] - 1) * jump
            jump *= m.stride[0]
    return rf


if __name__ == '__main__':
    for name, m in [('npu w128', NpuPose(128)), ('npu w192', NpuPose(192)),
                    ('plain s8', PlainPose('s8', 12)), ('plain s16', PlainPose('s16', 12))]:
        h, o = m(torch.zeros(2, 3, IN_H, IN_W))
        print(f'{name}: params {sum(p.numel() for p in m.parameters()) / 1e6:.3f}M  '
              f'MAC {macs(m) / 1e6:.1f}M  RF {receptive_field(m)}  heat {tuple(h.shape)} offset {tuple(o.shape)}')
