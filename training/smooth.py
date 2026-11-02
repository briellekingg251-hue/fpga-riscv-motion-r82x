"""One Euro filter for keypoints (Casiez et al. 2012): heavy smoothing when a joint is
still, little when it moves fast, so slow jitter disappears without lagging a waving wrist.

Firmware form (per joint, per axis, frame period T = 1/15.6 s):
    a(fc)  = 1 / (1 + 1 / (2*pi*fc*T))
    dx     = (x - x_prev) / T;          dx_hat = a(D_CUTOFF) * dx + (1 - a(D_CUTOFF)) * dx_hat_prev
    fc     = MIN_CUTOFF + BETA * |dx_hat|
    x_hat  = a(fc) * x + (1 - a(fc)) * x_hat_prev
Reset (x_hat = x, dx_hat = 0) on a new detection or when the joint was not confident.
"""
import math

import numpy as np

FPS = 15.6
MIN_CUTOFF = 1.0      # Hz
BETA = 0.02           # per (pixel / s)
D_CUTOFF = 1.0        # Hz


def alpha(fc, t=1 / FPS):
    return 1.0 / (1.0 + 1.0 / (2 * math.pi * fc * t))


class OneEuro:
    def __init__(self, n, min_cutoff=MIN_CUTOFF, beta=BETA, d_cutoff=D_CUTOFF):
        self.n, self.min_cutoff, self.beta, self.d_cutoff = n, min_cutoff, beta, d_cutoff
        self.reset()

    def reset(self):
        self.x = None
        self.dx = np.zeros((self.n, 2))

    def __call__(self, xy, ok):
        """xy: (n, 2) raw joints, ok: (n,) bool confident; returns smoothed copy."""
        xy = np.asarray(xy, float)
        if self.x is None:
            self.x = xy.copy()
            self.dx[:] = 0
            return xy.copy()
        out = xy.copy()
        for j in range(self.n):
            if not ok[j]:                         # unreliable joint: pass through, restart its state
                self.x[j], self.dx[j] = xy[j], 0
                continue
            d = (xy[j] - self.x[j]) * FPS
            ad = alpha(self.d_cutoff)
            self.dx[j] = ad * d + (1 - ad) * self.dx[j]
            fc = self.min_cutoff + self.beta * np.abs(self.dx[j])
            a = np.array([alpha(f) for f in fc])
            self.x[j] = a * xy[j] + (1 - a) * self.x[j]
            out[j] = self.x[j]
        return out
