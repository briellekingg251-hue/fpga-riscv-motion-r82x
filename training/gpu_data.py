"""GPU training pipeline: raw pre-cropped canvases (shared memmap) -> GPU augmentation + targets.

Reproduces data.CocoTopDown(train=True, board_aug=True) distribution-wise (not bit-exact):
scale/shift/rotation/flip -> colour jitter (+30% Gaussian blur) -> 50% board quality
(RGB565 bit drop, 30% motion blur, JPEG 40-90 simulated on GPU: YCbCr 4:2:0 + 8x8 DCT quantisation)
-> x/127.5-1 -> CenterNet heat/offset targets.
Host side only gathers raw canvases from the memmap into pinned memory (background threads).
"""
import math
import queue
import threading

import numpy as np
import torch
import torch.nn.functional as F

from data import COCO_FLIP, KP_SETS, OFFSET_RADIUS, SIGMA
from model import IN_H, IN_W

JPEG_Q_RANGE = (40, 90)
# ITU T.81 Annex K base tables
_QY = [16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56,
       14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
       49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]
_QC = [17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99,
       47, 66, 99, 99, 99, 99, 99, 99] + [99] * 32


class Source:
    """One pre-cropped dataset (precrop.py output stem) and how often it repeats per epoch."""

    def __init__(self, stem, repeat=1.0, frac=1.0, seed=0):
        d = torch.load(f'{stem}.pt', weights_only=False)
        self.pixels = np.load(f'{stem}.npy', mmap_mode='r')          # (N,H,W,3) uint8, shared page cache
        n = len(self.pixels)
        keep = torch.arange(n)
        if frac < 1:
            g = torch.Generator().manual_seed(seed)
            keep = torch.randperm(n, generator=g)[:int(n * frac)].sort().values
        self.rows = keep.numpy()
        self.kp, self.vis = d['kp'][keep], d['vis'][keep]
        self.canvas, self.extent = tuple(d['canvas']), tuple(d['extent'])
        self.repeat, self.path = repeat, str(stem)


class GpuTrainLoader:
    def __init__(self, sources, batch, device, kp_set='body12', stride=16, max_rot=30.0, board_aug=True,
                 drop_last=True, augment=True, prefetch=4, threads=4):
        assert len({s.canvas for s in sources}) == 1, 'all sources must share one canvas size'
        self.sources = sources
        self.src_of = np.concatenate([np.full(len(s.rows), i) for i, s in enumerate(sources)])
        self.row_of = np.concatenate([s.rows for s in sources])
        self.kp = torch.cat([s.kp for s in sources]).to(device)
        self.vis = torch.cat([s.vis for s in sources]).to(device)
        self.canvas_h, self.canvas_w = sources[0].canvas
        self.extent = sources[0].extent
        offs, self.parts = 0, []
        for s in sources:                       # (start, count, repeat) per source
            self.parts.append((offs, len(s.rows), s.repeat))
            offs += len(s.rows)
        idx = KP_SETS[kp_set]
        self.flip_perm = torch.tensor([idx.index(COCO_FLIP[k]) for k in idx], device=device)
        self.batch, self.device, self.stride = batch, device, stride
        self.max_rot, self.board_aug, self.drop_last = max_rot, board_aug, drop_last
        self.augment, self.prefetch, self.threads = augment, prefetch, threads
        self.out_h, self.out_w = IN_H // stride, IN_W // stride
        ys, xs = torch.meshgrid(torch.arange(IN_H, device=device, dtype=torch.float32),
                                torch.arange(IN_W, device=device, dtype=torch.float32), indexing='ij')
        self.out_grid = torch.stack([xs, ys, torch.ones_like(xs)], -1).reshape(-1, 3)   # (HW,3)

    def epoch_indices(self):
        idx = []
        for start, count, rep in self.parts:
            whole, frac = int(rep), rep - int(rep)
            for _ in range(whole):
                idx.append(torch.arange(start, start + count))
            if frac > 0:
                idx.append(start + torch.randperm(count)[:int(round(count * frac))])
        idx = torch.cat(idx)
        return idx[torch.randperm(len(idx))]

    def __len__(self):
        n = sum(c * int(r) + int(round(c * (r - int(r)))) for _, c, r in self.parts)
        return n // self.batch if self.drop_last else -(-n // self.batch)

    def fetch(self, ids, out=None):
        """Gather raw canvases for global ids into a pinned host tensor (N,H,W,3) uint8.
        Row-by-row copies (memcpy, GIL released) -- numpy fancy indexing on the memmap was ~3x slower."""
        ids = np.asarray(ids)
        if out is None:
            out = torch.empty((len(ids), self.canvas_h, self.canvas_w, 3), dtype=torch.uint8).pin_memory()
        o = out.numpy()
        for j in np.argsort(self.row_of[ids]):        # ascending memmap reads
            g = ids[j]
            o[j] = self.sources[self.src_of[g]].pixels[self.row_of[g]]
        return out[:len(ids)]

    def __iter__(self):
        order = self.epoch_indices().numpy()
        stop = len(order) - self.batch + 1 if self.drop_last else len(order)
        chunks = [order[b:b + self.batch] for b in range(0, stop, self.batch)]
        # ring of reusable pinned buffers (pinned allocation costs ~80 ms per batch)
        free = queue.Queue()
        for _ in range(self.prefetch + self.threads + 1):
            free.put((torch.empty((self.batch, self.canvas_h, self.canvas_w, 3), dtype=torch.uint8).pin_memory(),
                      None))
        ready, lock, done = queue.Queue(), threading.Lock(), threading.Event()
        nxt = iter(range(len(chunks)))
        errors = []

        def worker():
            try:
                while not done.is_set():
                    with lock:
                        i = next(nxt, None)
                    if i is None:
                        return
                    buf, ev = free.get()
                    if ev is not None:
                        ev.synchronize()          # GPU copy out of this buffer has finished
                    ready.put((i, buf, self.fetch(chunks[i], buf)))
            except Exception as e:          # surface in the consumer instead of hanging
                errors.append(e)
                ready.put((None, None, None))
        threads = [threading.Thread(target=worker, daemon=True) for _ in range(self.threads)]
        for t in threads:
            t.start()
        pending = {}
        try:
            for want in range(len(chunks)):
                while want not in pending:
                    i, buf, host = ready.get()
                    if i is None:
                        raise RuntimeError('loader thread failed') from errors[0]
                    pending[i] = (buf, host)
                buf, host = pending.pop(want)
                batch = self.make_batch(torch.from_numpy(chunks[want]), host)
                ev = torch.cuda.Event()
                ev.record()
                free.put((buf, ev))
                yield batch
        finally:
            done.set()

    # ---------------------------------------------------------------- batch
    @torch.no_grad()
    def make_batch(self, ids, host=None):
        dev, n = self.device, len(ids)
        if host is None:
            host = self.fetch(ids.numpy())
        imgs = host.to(dev, non_blocking=True).permute(0, 3, 1, 2).float()
        gid = ids.to(dev)
        kp, vis = self.kp[gid], self.vis[gid].clone()
        A = self.sample_affine(n)                              # canvas -> input crop, (n,2,3)
        crop = self.warp(imgs, A)
        pts = torch.einsum('nij,nkj->nki', A, torch.cat([kp, torch.ones_like(kp[..., :1])], -1))
        flip = (torch.rand(n, device=dev) < 0.5) & self.augment
        if flip.any():
            crop[flip] = crop[flip].flip(-1)
            fp = pts[flip][:, self.flip_perm]
            fp[..., 0] = IN_W - 1 - fp[..., 0]
            pts[flip], vis[flip] = fp, vis[flip][:, self.flip_perm]
        vis &= (pts[..., 0] >= 0) & (pts[..., 0] < IN_W) & (pts[..., 1] >= 0) & (pts[..., 1] < IN_H)
        if self.augment:
            crop = self.color_jitter(crop)
            if self.board_aug:
                crop = self.board_quality(crop)
        x = crop / 127.5 - 1
        heat, off, off_w = self.targets(pts, vis)
        return x, heat, off, off_w, vis.float()

    def sample_affine(self, n):
        dev = self.device
        s = (torch.randn(n, device=dev) * 0.25 + 1).clamp(0.75, 1.35)
        shift = torch.empty(n, 2, device=dev).uniform_(-0.08, 0.08)
        rot = (torch.randn(n, device=dev) * self.max_rot / 2).clamp(-self.max_rot, self.max_rot)
        rot = torch.where(torch.rand(n, device=dev) < 0.6, rot, torch.zeros_like(rot))
        if not self.augment:
            s, shift, rot = torch.ones_like(s), torch.zeros_like(shift), torch.zeros_like(rot)
        # crop window in canvas px: (w, h) = s * canvas / extent; centre shifted by shift * window
        win_w = s * self.canvas_w / self.extent[0]
        win_h = s * self.canvas_h / self.extent[1]
        cx = self.canvas_w / 2 + shift[:, 0] * win_w
        cy = self.canvas_h / 2 + shift[:, 1] * win_h
        sx, sy = IN_W / win_w, IN_H / win_h
        a = torch.deg2rad(rot)
        ca, sa = a.cos(), a.sin()
        A = torch.zeros(n, 2, 3, device=dev)
        A[:, 0, 0], A[:, 0, 1] = ca * sx, sa * sx
        A[:, 1, 0], A[:, 1, 1] = -sa * sy, ca * sy
        A[:, 0, 2] = IN_W / 2 - (A[:, 0, 0] * cx + A[:, 0, 1] * cy)
        A[:, 1, 2] = IN_H / 2 - (A[:, 1, 0] * cx + A[:, 1, 1] * cy)
        return A

    def warp(self, imgs, A):
        """Bilinear, zero border; pixel-index coordinates like cv2.warpAffine."""
        n = A.shape[0]
        full = torch.cat([A, torch.tensor([0, 0, 1.0], device=A.device).expand(n, 1, 3)], 1)
        inv = torch.linalg.inv(full)[:, :2]                                   # crop -> canvas
        src = torch.einsum('nij,pj->npi', inv, self.out_grid)                 # (n,HW,2) canvas px
        gx = src[..., 0] * (2 / (self.canvas_w - 1)) - 1
        gy = src[..., 1] * (2 / (self.canvas_h - 1)) - 1
        grid = torch.stack([gx, gy], -1).reshape(n, IN_H, IN_W, 2)
        return F.grid_sample(imgs, grid, mode='bilinear', padding_mode='zeros', align_corners=True)

    def color_jitter(self, img):
        n, dev = img.shape[0], img.device
        u = lambda lo, hi, *shape: torch.empty(n, *shape, device=dev).uniform_(lo, hi)
        img = img * u(0.6, 1.4, 1, 1, 1) + u(-30, 30, 1, 1, 1)
        gray = img.mean(1, keepdim=True)
        img = gray + (img - gray) * u(0.6, 1.4, 1, 1, 1)
        img = img * u(0.85, 1.15, 3, 1, 1)
        blur = torch.rand(n, device=dev) < 0.3
        if blur.any():
            sig = u(0.3, 1.2)[blur]
            k1 = torch.exp(-torch.tensor([-1.0, 0, 1], device=dev)[None] ** 2 / (2 * sig[:, None] ** 2))
            k1 = k1 / k1.sum(1, keepdim=True)
            img[blur] = self._sep_conv(img[blur], k1)
        return img.clamp(0, 255).floor()          # astype(uint8) truncation

    @staticmethod
    def _sep_conv(img, k1):
        """Per-sample separable 3-tap filter, reflect-101 border (cv2 default)."""
        m, c, h, w = img.shape
        r = k1.shape[1] // 2
        x = F.pad(img.reshape(1, m * c, h, w), (r, r, r, r), mode='reflect')
        kk = k1.repeat_interleave(c, 0)
        x = F.conv2d(x, kk[:, None, None, :], groups=m * c)
        x = F.conv2d(x, kk[:, None, :, None], groups=m * c)
        return x.reshape(m, c, h, w)

    def board_quality(self, img):
        n, dev = img.shape[0], img.device
        sel = torch.rand(n, device=dev) < 0.5
        if not sel.any():
            return img
        sub = img[sel]
        div = torch.tensor([8.0, 4.0, 8.0], device=dev)[None, :, None, None]
        sub = torch.floor(sub / div) * div                                   # RGB565 bit drop
        mb = torch.rand(len(sub), device=dev) < 0.3
        if mb.any():
            sub[mb] = self._motion_blur(sub[mb])
        quality = torch.randint(JPEG_Q_RANGE[0], JPEG_Q_RANGE[1] + 1, (len(sub),), device=dev).float()
        img[sel] = jpeg_sim(sub.clamp(0, 255), quality)
        return img

    @staticmethod
    def _motion_blur(img):
        m, c, h, w = img.shape
        dev, K = img.device, 9
        length = torch.tensor([3, 5, 7, 9], device=dev)[torch.randint(4, (m,), device=dev)].float()
        ang = torch.rand(m, device=dev) * math.pi
        t = torch.linspace(-0.5, 0.5, 4 * K, device=dev)[None]
        cen = (K - 1) / 2
        half = (length - 1) / 2
        px = (cen + t * 2 * half[:, None] * ang.cos()[:, None]).round().long()
        py = (cen + t * 2 * half[:, None] * ang.sin()[:, None]).round().long()
        ker = torch.zeros(m, K * K, device=dev)
        ker.scatter_(1, py * K + px, 1.0)
        ker = (ker / ker.sum(1, keepdim=True)).reshape(m, 1, K, K)
        x = F.pad(img.reshape(1, m * c, h, w), (4, 4, 4, 4), mode='reflect')
        x = F.conv2d(x, ker.repeat_interleave(c, 0), groups=m * c)
        return x.reshape(m, c, h, w)

    def targets(self, pts, vis):
        s, oh, ow = self.stride, self.out_h, self.out_w
        dev = pts.device
        ys, xs = torch.meshgrid(torch.arange(oh, device=dev, dtype=torch.float32),
                                torch.arange(ow, device=dev, dtype=torch.float32), indexing='ij')
        cy, cx = ys * s + (s - 1) / 2, xs * s + (s - 1) / 2
        gx = (pts[..., 0] - (s - 1) / 2) / s                      # (n,K)
        gy = (pts[..., 1] - (s - 1) / 2) / s
        rx = gx.round().clamp(0, ow - 1)[..., None, None]
        ry = gy.round().clamp(0, oh - 1)[..., None, None]
        v = vis.float()[..., None, None]
        heat = torch.exp(-((xs - rx) ** 2 + (ys - ry) ** 2) / (2 * SIGMA ** 2)) * v
        d2 = (xs - gx[..., None, None]) ** 2 + (ys - gy[..., None, None]) ** 2
        off_w = (d2 <= OFFSET_RADIUS ** 2).float() * v
        off_y = (pts[..., 1, None, None] - cy) * v
        off_x = (pts[..., 0, None, None] - cx) * v
        return heat, torch.cat([off_y, off_x], 1), off_w


def _dct_mat(dev):
    k = torch.arange(8, device=dev, dtype=torch.float32)
    c = torch.cos((2 * k[None] + 1) * k[:, None] * math.pi / 16) * 0.5
    c[0] /= math.sqrt(2)
    return c                                                     # orthonormal 8x8 DCT-II


def _qtable(base, quality):
    """libjpeg quality scaling, per sample -> (n,8,8)."""
    scale = torch.where(quality < 50, 5000 / quality, 200 - 2 * quality)
    t = torch.floor((torch.tensor(base, device=quality.device, dtype=torch.float32)[None] * scale[:, None] + 50) / 100)
    return t.clamp(1, 255).reshape(-1, 8, 8)


def _blockwise(ch, q, D):
    """(n,H,W) level-shifted channel -> DCT quantise/dequantise per 8x8 block (H, W multiples of 8)."""
    n, h, w = ch.shape
    b = ch.reshape(n, h // 8, 8, w // 8, 8).permute(0, 1, 3, 2, 4)
    coef = D @ b @ D.T
    qq = q[:, None, None]
    b = D.T @ (torch.round(coef / qq) * qq) @ D
    return b.permute(0, 1, 3, 2, 4).reshape(n, h, w)


def jpeg_sim(rgb, quality):
    """Lossy JPEG round trip on GPU (baseline, 4:2:0, libjpeg tables); entropy coding is lossless so skipped.
    rgb (n,3,H,W) float 0..255 with H, W multiples of 8 -> float 0..255 (rounded)."""
    D = _dct_mat(rgb.device)
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = -0.168736 * r - 0.331264 * g + 0.5 * b + 128
    cr = 0.5 * r - 0.418688 * g - 0.081312 * b + 128
    y = _blockwise(y - 128, _qtable(_QY, quality), D) + 128
    sub = F.avg_pool2d(torch.stack([cb, cr], 1), 2)                       # 4:2:0
    h2, w2 = sub.shape[-2:]
    sub = F.pad(sub, (0, (-w2) % 8, 0, (-h2) % 8), mode='replicate')
    qc = _qtable(_QC, quality)
    chroma = torch.stack([_blockwise(sub[:, i] - 128, qc, D) + 128 for i in (0, 1)], 1)[:, :, :h2, :w2]
    chroma = F.interpolate(chroma, scale_factor=2, mode='bilinear', align_corners=False) - 128
    cb, cr = chroma[:, 0], chroma[:, 1]
    out = torch.stack([y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb], 1)
    return out.round().clamp(0, 255)
