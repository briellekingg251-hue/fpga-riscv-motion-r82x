"""Bit-exact Python reference model of the Fruit Ninja display engine (GPU).

The model defines the command semantics that rtl/video/*.v implements.  It is
used to (1) preview scenes without hardware and (2) check RTL simulation
frames pixel-for-pixel.

Command FIFO entry = (idx, data32).  See docs in README / fw/gpu.h.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import fnlib as F  # noqa: E402

# register / command indices (word offset of the MMIO write)
R_NOP, R_COLOR, R_DST, R_SIZE, R_U0, R_V0, R_DUDX, R_DVDX, R_DUDY, R_DVDY, R_FLAGS = range(11)
C_CLEAR, C_BG, C_RECT, C_SPRITE, C_GLYPH, C_TEXT, C_CIRCLE, C_PSET, C_PALETTE, C_SWAP = range(16, 26)

FLAG_SOLID = 1
TEXT_INV = {1: 0x10000, 2: 0x8000, 3: 0x5556, 4: 0x4000}
M32 = 0xFFFFFFFF


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def s32(v: int) -> int:
    v &= M32
    return v - 0x100000000 if v & 0x80000000 else v


class GpuModel:
    def __init__(self) -> None:
        b = ROOT / "build"
        self.pal = np.array([[(c >> 16) & 255, (c >> 8) & 255, c & 255]
                             for c in F.read_hex(b / "palette.hex")], dtype=np.uint8)
        self.rom = np.array(F.read_hex(b / "sprites.hex"), dtype=np.uint8)
        self.font = np.array(F.read_hex(b / "font.hex"), dtype=np.uint32)
        self.fb = [np.zeros((F.FB_H, F.FB_W), dtype=np.uint8) for _ in range(2)]
        self.draw_buf = 1
        self.disp_buf = 0
        self.swaps = 0
        self.r = dict(color=0, x0=0, y0=0, w=0, h=0, u0=0, v0=0,
                      dudx=0x10000, dvdx=0, dudy=0, dvdy=0x10000, flags=0)
        self.pixels_touched = 0

    # ------------------------------------------------------------ raster core
    def _raster(self, mode, x0, y0, w, h, color, u0=0, v0=0, dudx=0, dvdx=0,
                dudy=0, dvdy=0, img=0, ch=0, flags=0, r=0, variant=0):
        fb = self.fb[self.draw_buf]
        urow, vrow = u0 & M32, v0 & M32
        for j in range(h):
            dy = y0 + j
            if 0 <= dy < F.FB_H:
                u, v = urow, vrow
                for i in range(w):
                    dx = x0 + i
                    self.pixels_touched += 1
                    if 0 <= dx < F.FB_W:
                        c = self._pixel(mode, dx, dy, i, j, u, v, color, img, ch, flags, r, variant)
                        if c is not None:
                            fb[dy, dx] = c
                    u = (u + dudx) & M32
                    v = (v + dvdx) & M32
            urow = (urow + dudy) & M32
            vrow = (vrow + dvdy) & M32

    def _pixel(self, mode, dx, dy, i, j, u, v, color, img, ch, flags, r, variant):
        if mode == "fill":
            return color
        if mode == "bg":
            return F.bg_index(dx, dy, variant)
        if mode == "sprite":
            if (u >> 22) or (v >> 22):
                return None
            t = int(self.rom[(img << 12) | (((v >> 16) & 63) << 6) | ((u >> 16) & 63)])
            if t == 0:
                return None
            return color if flags & FLAG_SOLID else t
        if mode == "glyph":
            if (u >> 20) or (v >> 20):
                return None
            row = int(self.font[(ch << 4) | ((v >> 16) & 15)])
            return color if (row >> (15 - ((u >> 16) & 15))) & 1 else None
        if mode == "circle":
            a, b = i - r, j - r
            return color if a * a + b * b <= r * r + r else None
        raise ValueError(mode)

    # ------------------------------------------------------------ commands
    def write(self, idx: int, d: int) -> None:
        d &= M32
        r = self.r
        if idx == R_COLOR:
            r["color"] = d & 255
        elif idx == R_DST:
            r["x0"], r["y0"] = s16(d), s16(d >> 16)
        elif idx == R_SIZE:
            r["w"], r["h"] = d & 1023, (d >> 16) & 1023
        elif idx in (R_U0, R_V0, R_DUDX, R_DVDX, R_DUDY, R_DVDY):
            key = {R_U0: "u0", R_V0: "v0", R_DUDX: "dudx", R_DVDX: "dvdx",
                   R_DUDY: "dudy", R_DVDY: "dvdy"}[idx]
            r[key] = d
        elif idx == R_FLAGS:
            r["flags"] = d & 1
        elif idx == C_CLEAR:
            self._raster("fill", 0, 0, F.FB_W, F.FB_H, d & 255)
        elif idx == C_BG:
            self._raster("bg", 0, 0, F.FB_W, F.FB_H, 0, variant=d & 15)
        elif idx == C_RECT:
            self._raster("fill", r["x0"], r["y0"], r["w"], r["h"], r["color"])
        elif idx in (C_SPRITE, C_GLYPH):
            self._raster("sprite" if idx == C_SPRITE else "glyph", r["x0"], r["y0"], r["w"], r["h"],
                         r["color"], r["u0"], r["v0"], r["dudx"], r["dvdx"], r["dudy"], r["dvdy"],
                         img=d & 31, ch=d & 127, flags=r["flags"])
        elif idx == C_TEXT:
            x, y, ch, sc = d & 511, (d >> 9) & 511, (d >> 18) & 127, ((d >> 25) & 3) + 1
            inv = TEXT_INV[sc]
            self._raster("glyph", x, y, 16 * sc, 16 * sc, r["color"], 0, 0, inv, 0, 0, inv, ch=ch)
        elif idx == C_CIRCLE:
            cx, cy, rad, col = d & 511, (d >> 9) & 511, (d >> 18) & 63, (d >> 24) & 255
            self._raster("circle", cx - rad, cy - rad, 2 * rad + 1, 2 * rad + 1, col, r=rad)
        elif idx == C_PSET:
            x, y, col = d & 511, (d >> 9) & 511, (d >> 24) & 255
            self._raster("fill", x, y, 1, 1, col)
        elif idx == C_PALETTE:
            i = (d >> 24) & 255
            self.pal[i] = [(d >> 16) & 255, (d >> 8) & 255, d & 255]
        elif idx == C_SWAP:
            self.disp_buf = self.draw_buf
            self.draw_buf ^= 1
            self.swaps += 1
        # R_NOP and unknown indices: ignored

    def frame(self) -> np.ndarray:
        """1024x600 RGB image currently on the LCD."""
        idx = self.fb[self.disp_buf].repeat(2, 0).repeat(2, 1)
        return self.pal[idx]


# ---------------------------------------------------------------- helpers
SIN_Q14 = [int(round(16384 * math.sin(2 * math.pi * i / 256))) for i in range(256)]


def sprite_cmds(img, cx, cy, scale_q8=256, angle=0, flip=False, solid=False, color=0):
    """Affine sprite blit centred on (cx, cy); mirrors fw/gpu.c gpu_sprite()."""
    c = SIN_Q14[(angle + 64) & 255]
    s = SIN_Q14[angle & 255]
    inv = (1 << 24) // scale_q8
    dudx = (c * inv) >> 14
    dvdx = (-s * inv) >> 14
    dudy = (s * inv) >> 14
    dvdy = (c * inv) >> 14
    hb = (((abs(c) + abs(s)) * scale_q8) >> 17) + 1          # ceil-ish of 32*scale*(|c|+|s|)
    x0, y0, w = cx - hb, cy - hb, 2 * hb
    u0 = (32 << 16) + (((dudx + dudy) * (1 - 2 * hb)) >> 1)
    v0 = (32 << 16) + (((dvdx + dvdy) * (1 - 2 * hb)) >> 1)
    if flip:
        dudx, dudy, u0 = -dudx, -dudy, (64 << 16) - u0
    out = [(R_DST, ((y0 & 0xFFFF) << 16) | (x0 & 0xFFFF)), (R_SIZE, (w << 16) | w),
           (R_U0, u0), (R_V0, v0), (R_DUDX, dudx), (R_DVDX, dvdx), (R_DUDY, dudy),
           (R_DVDY, dvdy), (R_FLAGS, FLAG_SOLID if solid else 0)]
    if solid:
        out.insert(0, (R_COLOR, color))
    out.append((C_SPRITE, img))
    return [(i, v & M32) for i, v in out]


def text_cmds(x, y, s, color, scale=1, widths=None):
    out = [(R_COLOR, color)]
    for ch in s:
        code = ord(ch) & 127
        out.append((C_TEXT, (x & 511) | ((y & 511) << 9) | (code << 18) | ((scale - 1) << 25)))
        adv = (widths[code] if widths else 10) + 1
        x += adv * scale
    return out


def circle_cmd(cx, cy, r, color):
    return (C_CIRCLE, (cx & 511) | ((cy & 511) << 9) | ((r & 63) << 18) | ((color & 255) << 24))


def glyph_widths():
    txt = (ROOT / "fw" / "assets.h").read_text()
    body = txt.split("fn_glyph_width[128] = {")[1].split("};")[0]
    return [int(v) for v in body.replace("\n", " ").split(",") if v.strip()]


def save_png(rgb: np.ndarray, path) -> None:
    from PIL import Image
    Image.fromarray(rgb, "RGB").save(path)
