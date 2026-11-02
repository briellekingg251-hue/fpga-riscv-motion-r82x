"""COCO keypoints, top-down crops for the pose nets.

Each sample is one annotated person: the box is expanded to the 2:3 (W:H)
input aspect, padded by 25%, randomly scaled/rotated/flipped (train only) and
warped to 192x128.  Targets on the (192/stride)x(128/stride) grid:
  heat   : Gaussian (sigma in cells) per visible keypoint
  offset : (y, x) from each cell's input-pixel position to the keypoint,
           supervised only within OFFSET_RADIUS cells of the keypoint
"""
import json
import math
import random

import cv2
import numpy as np
import torch
from torch.utils.data import Dataset

from model import IN_H, IN_W
from anncache import slim_coco
from subsets import is_upright

cv2.setNumThreads(0)     # DataLoader workers already parallelise

COCO_FLIP = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]   # left <-> right
KP_SETS = {'coco17': list(range(17)),
           'body12': list(range(5, 17))}          # no nose/eyes/ears
SIGMA = 1.0              # heatmap Gaussian sigma, in output cells
OFFSET_RADIUS = 2.0      # cells around a keypoint where offsets are trained
PAD = 1.25               # box padding before the crop


def box_to_center_scale(box, pad=PAD):
    """Return crop centre and (w, h) with the input aspect ratio."""
    x, y, w, h = box
    cx, cy = x + w / 2, y + h / 2
    aspect = IN_W / IN_H
    if w > aspect * h:
        h = w / aspect
    else:
        w = h * aspect
    return np.array([cx, cy], np.float32), np.array([w * pad, h * pad], np.float32)


def crop_matrix(center, size, rot_deg=0.0, flip=False):
    """2x3 affine: original image -> input crop."""
    sx, sy = IN_W / size[0], IN_H / size[1]
    a = math.radians(rot_deg)
    ca, sa = math.cos(a), math.sin(a)
    m = np.array([[ca * sx, sa * sx, 0], [-sa * sy, ca * sy, 0]], np.float32)
    m[:, 2] = np.array([IN_W / 2, IN_H / 2]) - m[:, :2] @ center
    if flip:
        m = np.array([[-1, 0, IN_W - 1], [0, 1, 0]], np.float32) @ np.vstack([m, [0, 0, 1]])
    return m


class CocoTopDown(Dataset):
    def __init__(self, ann_file, img_dir, train=True, min_kp=1, subset='all', max_rot=30.0,
                 kp_set='coco17', stride=8, board_aug=False):
        d = slim_coco(ann_file)
        self.kp_idx = KP_SETS[kp_set]
        self.flip = [self.kp_idx.index(COCO_FLIP[k]) for k in self.kp_idx]
        self.stride, self.out_h, self.out_w = stride, IN_H // stride, IN_W // stride
        self.img_dir = img_dir
        self.train = train
        self.board_aug = board_aug
        self.max_rot = max_rot
        self.files = {i: name for i, name, _, _ in d['images']}
        self.items = [a for a in d['persons'] if not a['iscrowd']
                      and a['num_keypoints'] >= min_kp and a['bbox'][2] > 1 and a['bbox'][3] > 1
                      and (subset == 'all' or is_upright(a))]
        del d

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        a = self.items[i]
        img = cv2.imread(f'{self.img_dir}/{self.files[a["image_id"]]}', cv2.IMREAD_COLOR)[:, :, ::-1]
        kp = np.array(a['keypoints'], np.float32).reshape(17, 3)[self.kp_idx]
        center, size = box_to_center_scale(a['bbox'])
        rot, flip = 0.0, False
        if self.train:
            size = size * np.clip(np.random.randn() * 0.25 + 1, 0.75, 1.35)
            center = center + size * np.random.uniform(-0.08, 0.08, 2)
            rot = float(np.clip(np.random.randn() * self.max_rot / 2, -self.max_rot, self.max_rot)) \
                if random.random() < 0.6 else 0.0
            flip = random.random() < 0.5
        m = crop_matrix(center, size, rot, flip)
        crop = cv2.warpAffine(np.ascontiguousarray(img), m, (IN_W, IN_H), flags=cv2.INTER_LINEAR,
                              borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0))
        pts = np.c_[kp[:, :2], np.ones(len(kp))] @ m.T
        vis = kp[:, 2] > 0
        if flip:
            pts, vis = pts[self.flip], vis[self.flip]
        vis &= (pts[:, 0] >= 0) & (pts[:, 0] < IN_W) & (pts[:, 1] >= 0) & (pts[:, 1] < IN_H)
        if self.train:
            crop = self.color_jitter(crop)
            if self.board_aug:
                crop = self.board_quality(crop)
        x = torch.from_numpy(np.ascontiguousarray(crop.transpose(2, 0, 1))).float() / 127.5 - 1
        heat, off, off_w = self.targets(pts, vis)
        meta = dict(center=center, size=size, image_id=a['image_id'], ann_id=a['id'], area=a['area'])
        return x, heat, off, off_w, torch.from_numpy(vis.astype(np.float32)), meta

    @staticmethod
    def board_quality(img):
        if random.random() < 0.5:
            img = img.copy()
            img[:, :, 0] = (img[:, :, 0] >> 3) << 3
            img[:, :, 1] = (img[:, :, 1] >> 2) << 2
            img[:, :, 2] = (img[:, :, 2] >> 3) << 3
            if random.random() < 0.3:
                length = random.choice([3, 5, 7, 9])
                kernel = np.zeros((length, length), np.float32)
                angle = random.uniform(0, math.pi)
                center = (length-1)/2
                dx, dy = center*math.cos(angle), center*math.sin(angle)
                cv2.line(kernel, (round(center-dx), round(center-dy)),
                         (round(center+dx), round(center+dy)), 1.0, 1)
                kernel /= kernel.sum()
                img = cv2.filter2D(img, -1, kernel)
            ok, encoded = cv2.imencode('.jpg', cv2.cvtColor(img, cv2.COLOR_RGB2BGR),
                                      [cv2.IMWRITE_JPEG_QUALITY, random.randint(40, 90)])
            if ok:
                img = cv2.cvtColor(cv2.imdecode(encoded, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
        return img

    @staticmethod
    def color_jitter(img):
        img = img.astype(np.float32)
        img = img * np.random.uniform(0.6, 1.4) + np.random.uniform(-30, 30)
        gray = img.mean(axis=2, keepdims=True)
        img = gray + (img - gray) * np.random.uniform(0.6, 1.4)
        img = img * np.random.uniform(0.85, 1.15, 3)       # white balance, like a cheap sensor
        if random.random() < 0.3:
            img = cv2.GaussianBlur(img, (3, 3), np.random.uniform(0.3, 1.2))
        return np.clip(img, 0, 255).astype(np.uint8)

    def targets(self, pts, vis):
        s, oh, ow, nk = self.stride, self.out_h, self.out_w, len(pts)
        ys, xs = np.mgrid[0:oh, 0:ow].astype(np.float32)
        cy, cx = ys * s + (s - 1) / 2, xs * s + (s - 1) / 2   # cell centres, input px
        heat = np.zeros((nk, oh, ow), np.float32)
        off = np.zeros((2 * nk, oh, ow), np.float32)
        off_w = np.zeros((nk, oh, ow), np.float32)
        for k in range(nk):
            if not vis[k]:
                continue
            gx, gy = (pts[k, 0] - (s - 1) / 2) / s, (pts[k, 1] - (s - 1) / 2) / s
            d2 = (xs - gx) ** 2 + (ys - gy) ** 2
            # peak exactly 1 on the nearest cell (CenterNet); sub-cell precision comes from offsets
            rx, ry = min(max(round(gx), 0), ow - 1), min(max(round(gy), 0), oh - 1)
            heat[k] = np.exp(-((xs - rx) ** 2 + (ys - ry) ** 2) / (2 * SIGMA ** 2))
            near = d2 <= OFFSET_RADIUS ** 2
            off[k] = pts[k, 1] - cy
            off[k + nk] = pts[k, 0] - cx
            off_w[k] = near
        return torch.from_numpy(heat), torch.from_numpy(off), torch.from_numpy(off_w)


def collate(batch):
    x, h, o, w, v, meta = zip(*batch)
    return torch.stack(x), torch.stack(h), torch.stack(o), torch.stack(w), torch.stack(v), list(meta)


def decode(heat, offset, stride=8):
    """Firmware-equivalent decode: argmax cell + offset -> input-pixel (x, y), score (logit)."""
    n, k, h, w = heat.shape
    flat = heat.reshape(n, k, -1)
    score, idx = flat.max(-1)
    row, col = idx // w, idx % w
    oy = offset[:, :k].reshape(n, k, -1).gather(-1, idx[..., None])[..., 0]
    ox = offset[:, k:].reshape(n, k, -1).gather(-1, idx[..., None])[..., 0]
    x = col.float() * stride + (stride - 1) / 2 + ox
    y = row.float() * stride + (stride - 1) / 2 + oy
    return torch.stack([x, y], -1), score


def to_coco17(pts, score, kp_set):
    """(K,2),(K,) in a keypoint subset -> COCO 17 order; missing joints get score 0 at the
    subset centroid (they are only evaluated against body-only GT, where they are unlabelled)."""
    idx = KP_SETS[kp_set]
    if len(idx) == 17:
        return pts, score
    full, fs = np.tile(pts.mean(0), (17, 1)), np.zeros(17, np.float32)
    full[idx], fs[idx] = pts, score
    return full, fs


def to_image(pts_in, center, size):
    """Input-crop pixels -> original image (no rotation/flip at eval)."""
    m = crop_matrix(center, size)
    inv = cv2.invertAffineTransform(m)
    return np.c_[pts_in, np.ones(len(pts_in))] @ inv.T
