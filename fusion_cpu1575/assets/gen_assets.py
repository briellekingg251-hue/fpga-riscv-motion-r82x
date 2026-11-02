"""Generate sprite ROM, font ROM, palette and headers for the display engine.

Outputs (paths relative to the project root):
  build/sprites.hex   131072 x 8-bit  (32 images x 64 x 64, index 0 = transparent)
  build/font.hex      2048 x 16-bit   (128 glyphs x 16 rows, MSB = leftmost pixel)
  build/palette.hex   256 x 24-bit RGB
  rtl/video/fn_bg_lut.vh  background LUT functions for fn_bg_gen.v
  fw/assets.h         sprite ids, palette indices, glyph advance widths
  build/preview_*.png visual previews
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import fnlib as F  # noqa: E402

N = F.SPR_SIZE
SS = 4                      # supersampling factor
M = N * SS
BUILD = ROOT / "build"
FW = ROOT / "fw"

LIGHT = np.array([-0.45, -0.62, 0.64])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF_VEC = LIGHT + np.array([0.0, 0.0, 1.0])
HALF_VEC = HALF_VEC / np.linalg.norm(HALF_VEC)


# ---------------------------------------------------------------- canvas
class Canvas:
    """Supersampled RGBA canvas in sprite units (0..64)."""

    def __init__(self) -> None:
        c = (np.arange(M) + 0.5) / SS
        self.X, self.Y = np.meshgrid(c, c)
        self.rgb = np.zeros((M, M, 3))
        self.mask = np.zeros((M, M), dtype=bool)

    def paint(self, mask: np.ndarray, rgb) -> None:
        rgb = np.broadcast_to(np.asarray(rgb, dtype=float), (M, M, 3))
        self.rgb[mask] = rgb[mask]
        self.mask |= mask

    def erase(self, mask: np.ndarray) -> None:
        self.mask &= ~mask

    def downsample(self) -> tuple[np.ndarray, np.ndarray]:
        m = self.mask.reshape(N, SS, N, SS).astype(float)
        cov = m.mean(axis=(1, 3))
        w = m[..., None]
        col = (self.rgb.reshape(N, SS, N, SS, 3) * w).sum(axis=(1, 3))
        cnt = m.sum(axis=(1, 3))[..., None]
        col = np.where(cnt > 0, col / np.maximum(cnt, 1), 0)
        return np.clip(col, 0, 255), cov >= 0.5


def local(cv: Canvas, cx, cy, rx, ry, ang_deg=0.0):
    a = math.radians(ang_deg)
    ca, sa = math.cos(a), math.sin(a)
    dx, dy = cv.X - cx, cv.Y - cy
    lx = (dx * ca + dy * sa) / rx
    ly = (-dx * sa + dy * ca) / ry
    return lx, ly, ca, sa


def sphere_normal(lx, ly, ca, sa):
    r2 = lx * lx + ly * ly
    nz = np.sqrt(np.clip(1.0 - r2, 0.0, 1.0))
    nx = lx * ca - ly * sa
    ny = lx * sa + ly * ca
    return nx, ny, nz


def shade(base, nx, ny, nz, amb=0.42, kd=0.74, ks=0.55, shin=24, rim=0.22):
    base = np.asarray(base, dtype=float)
    diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
    spec = np.clip(nx * HALF_VEC[0] + ny * HALF_VEC[1] + nz * HALF_VEC[2], 0, 1) ** shin
    limb = (1 - rim) + rim * nz
    col = base * (amb + kd * diff)[..., None] * limb[..., None]
    col = col + (255 * ks * spec)[..., None]
    return np.clip(col, 0, 255)


def noise2(x, y, seed, scale):
    """Cheap smooth-ish value noise from sines (deterministic)."""
    rng = np.random.default_rng(seed)
    acc = np.zeros_like(x)
    for _ in range(5):
        fx, fy = rng.uniform(0.5, 1.5, 2) * scale
        ph = rng.uniform(0, 2 * math.pi, 2)
        acc += np.sin(x * fx + ph[0]) * np.sin(y * fy + ph[1])
    return acc / 5


def speckle(seed, count, cx, cy, r, cv: Canvas, rad=(0.5, 1.1)):
    rng = np.random.default_rng(seed)
    m = np.zeros((M, M), dtype=bool)
    for _ in range(count):
        ang = rng.uniform(0, 2 * math.pi)
        d = r * math.sqrt(rng.uniform(0, 1))
        px, py = cx + d * math.cos(ang), cy + d * math.sin(ang)
        rr = rng.uniform(*rad)
        m |= (cv.X - px) ** 2 + (cv.Y - py) ** 2 <= rr * rr
    return m


# ---------------------------------------------------------------- fruit bodies
def body_watermelon(cv, cx, cy, ang):
    rx, ry = 29.0, 22.0
    lx, ly, ca, sa = local(cv, cx, cy, rx, ry, ang)
    inside = lx * lx + ly * ly <= 1
    nx, ny, nz = sphere_normal(lx, ly, ca, sa)
    theta = np.arctan2(ly, np.maximum(nz, 1e-3))
    wob = 0.35 * np.sin(lx * 7.0) + 0.18 * np.sin(lx * 17.0 + 1.3)
    stripe = np.sin(theta * 9.0 + wob) > 0.05
    base = np.where(stripe[..., None], np.array([34, 112, 38.0]), np.array([128, 198, 70.0]))
    cv.paint(inside, shade(base, nx, ny, nz, ks=0.45))


def body_orange(cv, cx, cy):
    r = 24.0
    lx, ly, ca, sa = local(cv, cx, cy, r, r)
    inside = lx * lx + ly * ly <= 1
    nx, ny, nz = sphere_normal(lx, ly, ca, sa)
    n = noise2(cv.X, cv.Y, 7, 2.2)
    base = np.array([255, 146, 18.0])[None, None, :] * (0.93 + 0.07 * n)[..., None]
    cv.paint(inside, shade(base, nx, ny, nz, ks=0.5, shin=30))
    dots = speckle(11, 90, cx, cy, r * 0.95, cv, (0.35, 0.6)) & inside
    cv.paint(dots, shade(np.array([214, 110, 10.0]), nx, ny, nz, ks=0.2))
    stem = (cv.X - (cx + 1)) ** 2 + (cv.Y - (cy - r + 3)) ** 2 <= 3.2 ** 2
    cv.paint(stem, np.array([70, 110, 30.0]))
    stem2 = (cv.X - (cx + 1)) ** 2 + (cv.Y - (cy - r + 3)) ** 2 <= 1.4 ** 2
    cv.paint(stem2, np.array([40, 70, 20.0]))


def apple_mask(cv, cx, cy, r):
    dx, dy = cv.X - cx, cv.Y - cy
    th = np.arctan2(dx, -dy)                     # 0 at top
    rr = r * (1 - 0.13 * np.exp(-(th / 0.42) ** 2)) * (1 - 0.05 * np.exp(-((np.abs(th) - math.pi) / 0.5) ** 2))
    return np.sqrt(dx * dx + dy * dy) <= rr


def body_apple(cv, cx, cy):
    r = 24.0
    lx, ly, ca, sa = local(cv, cx, cy, r, r)
    inside = apple_mask(cv, cx, cy, r)
    nx, ny, nz = sphere_normal(lx, ly, ca, sa)
    streak = 0.5 + 0.5 * np.sin((cv.X - cx) * 1.3 + 2 * np.sin(cv.Y * 0.4))
    blush = np.clip((cv.Y - cy) / r * 0.9 + 0.15 * streak, 0, 1)
    base = np.array([206, 22, 32.0]) * (1 - 0.35 * blush)[..., None] + \
        np.array([240, 150, 40.0]) * (0.35 * blush)[..., None]
    cv.paint(inside, shade(base, nx, ny, nz, ks=0.65, shin=36))
    # stem and leaf
    t = np.linspace(0, 1, 60)
    stem = np.zeros((M, M), dtype=bool)
    for tt in t:
        sx = cx + 1 + 2.5 * tt
        sy = cy - r + 4 - 11 * tt
        stem |= (cv.X - sx) ** 2 + (cv.Y - sy) ** 2 <= 1.3 ** 2
    cv.paint(stem, np.array([96, 58, 24.0]))
    llx, lly, _, _ = local(cv, cx + 9, cy - r - 1, 8.5, 3.6, -28)
    leaf = llx * llx + lly * lly <= 1
    leafc = np.where((np.abs(lly) < 0.12)[..., None], np.array([60, 140, 30.0]), np.array([88, 186, 50.0]))
    cv.paint(leaf, leafc * (0.85 + 0.15 * (1 - llx))[..., None].clip(0.7, 1.1))


def lemon_mask(lx, ly):
    body = lx * lx + ly * ly <= 1
    tip = (np.abs(lx) >= 0.8) & (np.abs(lx) <= 1.16) & (np.abs(ly) <= (1.16 - np.abs(lx)) * 1.25)
    return body | tip


def body_lemon(cv, cx, cy, ang):
    rx, ry = 25.0, 19.0
    lx, ly, ca, sa = local(cv, cx, cy, rx, ry, ang)
    inside = lemon_mask(lx, ly)
    nx, ny, nz = sphere_normal(np.clip(lx, -0.999, 0.999), ly, ca, sa)
    n = noise2(cv.X, cv.Y, 3, 2.5)
    base = np.array([250, 222, 42.0])[None, None, :] * (0.94 + 0.06 * n)[..., None]
    cv.paint(inside, shade(base, nx, ny, nz, ks=0.55, shin=28))
    dots = speckle(5, 70, cx, cy, ry * 0.95, cv, (0.3, 0.55)) & inside
    cv.paint(dots, shade(np.array([220, 186, 20.0]), nx, ny, nz, ks=0.2))


def body_kiwi(cv, cx, cy, ang):
    rx, ry = 25.0, 20.0
    lx, ly, ca, sa = local(cv, cx, cy, rx, ry, ang)
    inside = lx * lx + ly * ly <= 1
    nx, ny, nz = sphere_normal(lx, ly, ca, sa)
    rng = np.random.default_rng(21)
    fuzz = rng.uniform(-1, 1, (M // 2, M // 2)).repeat(2, 0).repeat(2, 1)
    base = np.array([146, 104, 50.0])[None, None, :] * (0.9 + 0.12 * fuzz)[..., None]
    cv.paint(inside, shade(base, nx, ny, nz, ks=0.12, amb=0.4))


# ---------------------------------------------------------------- halves
def flesh_face(cv, fx, fy, a, b, rings, core_fn=None, seeds=None, segments=None):
    """Draw the cut face ellipse. rings: list of (outer_e, rgb) from outside in."""
    ex, ey = (cv.X - fx) / a, (cv.Y - fy) / b
    e = np.sqrt(ex * ex + ey * ey)
    face = e <= 1
    for outer, rgb in rings:
        cv.paint(face & (e <= outer), np.array(rgb, dtype=float) * (0.92 + 0.08 * (1 - e))[..., None])
    if segments is not None:
        n_seg, seg_rgb, inner, outer = segments
        ang = np.arctan2(ey, ex)
        frac = (ang / (2 * math.pi) * n_seg) % 1.0
        line = ((frac < 0.07) | (frac > 0.93)) & (e > inner) & (e < outer)
        cv.paint(face & line, np.array(seg_rgb, dtype=float))
    if core_fn is not None:
        core_fn(cv, ex, ey, e, face)
    if seeds is not None:
        ring_e, count, rgb, size = seeds
        for k in range(count):
            t = 2 * math.pi * (k + 0.5) / count
            sx, sy = fx + a * ring_e * math.cos(t), fy + b * ring_e * math.sin(t)
            m = ((cv.X - sx) / (size * 0.7)) ** 2 + ((cv.Y - sy) / size) ** 2 <= 1
            cv.paint(m & face, np.array(rgb, dtype=float))
    return face


def half_of(cv_body_fn, face_args, rx, ry, keep_left=True):
    cv = Canvas()
    a = ry * 0.46
    cx = 32 + (rx - a) / 2 if keep_left else 32 - (rx - a) / 2
    cy = 32.0
    cv_body_fn(cv, cx, cy)
    cut = cv.X > cx if keep_left else cv.X < cx
    cv.erase(cut)
    flesh_face(cv, cx, cy, a, ry * 0.98, **face_args)
    return cv


def seeds_kiwi(cv, ex, ey, e, face):
    core = face & (e <= 0.24)
    cv.paint(core, np.array([238, 240, 196.0]))


def core_apple(cv, ex, ey, e, face):
    ang = np.arctan2(ey, ex)
    star = e <= 0.30 * (0.75 + 0.25 * np.cos(5 * ang))
    cv.paint(face & star, np.array([232, 212, 150.0]))
    for sgn in (-1, 1):
        m = ((ex - 0.0) / 0.10) ** 2 + ((ey - sgn * 0.14) / 0.09) ** 2 <= 1
        cv.paint(face & m, np.array([92, 52, 22.0]))


# ---------------------------------------------------------------- other sprites
def sprite_bomb():
    cv = Canvas()
    cx, cy, r = 30.0, 37.0, 21.0
    lx, ly, ca, sa = local(cv, cx, cy, r, r)
    inside = lx * lx + ly * ly <= 1
    nx, ny, nz = sphere_normal(lx, ly, ca, sa)
    cv.paint(inside, shade(np.array([48, 46, 60.0]), nx, ny, nz, ks=0.9, shin=40, amb=0.45))
    cap = (np.abs(cv.X - (cx + 2)) <= 6.5) & (np.abs(cv.Y - (cy - r + 1)) <= 4.0)
    cv.paint(cap, np.array([140, 140, 150.0]) * (1.05 - 0.2 * (cv.Y - (cy - r - 3)) / 8)[..., None].clip(0.7, 1.1))
    fuse = np.zeros((M, M), dtype=bool)
    for tt in np.linspace(0, 1, 80):
        fx = cx + 3 + 12 * tt
        fy = cy - r - 3 - 10 * math.sin(tt * math.pi * 0.8)
        fuse |= (cv.X - fx) ** 2 + (cv.Y - fy) ** 2 <= 1.5 ** 2
    cv.paint(fuse, np.array([176, 140, 90.0]))
    sx, sy = cx + 15, cy - r - 12
    dx, dy = cv.X - sx, cv.Y - sy
    ang = np.arctan2(dy, dx)
    rad = np.sqrt(dx * dx + dy * dy)
    star = rad <= 3.0 + 3.5 * np.abs(np.cos(ang * 3)) ** 3
    cv.paint(star, np.array([255, 170, 30.0]))
    cv.paint(rad <= 2.6, np.array([255, 245, 190.0]))
    return cv


def sprite_splash(main, light, seed):
    cv = Canvas()
    rng = np.random.default_rng(seed)
    cx = cy = 32.0
    dx, dy = cv.X - cx, cv.Y - cy
    ang = np.arctan2(dy, dx)
    rad = np.sqrt(dx * dx + dy * dy)
    rr = 15.0
    for k in range(2, 7):
        rr = rr + rng.uniform(0.8, 2.2) * np.sin(k * ang + rng.uniform(0, 6.28))
    blob = rad <= rr
    cv.paint(blob, np.array(main, dtype=float))
    for _ in range(14):
        t = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(17, 29)
        s = rng.uniform(1.4, 3.6)
        px, py = cx + d * math.cos(t), cy + d * math.sin(t)
        drop = ((cv.X - px) ** 2 + (cv.Y - py) ** 2) <= s * s
        cv.paint(drop, np.array(main, dtype=float))
        # streak toward the blob
        for tt in np.linspace(0, 1, 12):
            qx, qy = px - (d - 14) * tt * math.cos(t), py - (d - 14) * tt * math.sin(t)
            w = s * (1 - tt) * 0.6
            if w > 0.3:
                cv.paint((cv.X - qx) ** 2 + (cv.Y - qy) ** 2 <= w * w, np.array(main, dtype=float))
    hl = blob & (((cv.X - cx + 5) ** 2 + (cv.Y - cy + 5) ** 2) <= 36)
    cv.paint(hl, np.array(light, dtype=float))
    return cv


def sprite_x(fill, edge):
    cv = Canvas()
    cx = cy = 32.0
    m_edge = np.zeros((M, M), dtype=bool)
    m_fill = np.zeros((M, M), dtype=bool)
    for a in (45, -45):
        lx, ly, _, _ = local(cv, cx, cy, 1, 1, a)
        m_edge |= (np.abs(lx) <= 21) & (np.abs(ly) <= 7.5)
        m_fill |= (np.abs(lx) <= 19) & (np.abs(ly) <= 5.2)
    cv.paint(m_edge, np.array(edge, dtype=float))
    cv.paint(m_fill, np.array(fill, dtype=float))
    return cv


def sprite_sparkle():
    cv = Canvas()
    dx, dy = cv.X - 32, cv.Y - 32
    ang = np.arctan2(dy, dx)
    rad = np.sqrt(dx * dx + dy * dy)
    star = rad <= 4 + 22 * np.abs(np.cos(ang * 2)) ** 12
    cv.paint(star, np.array([255, 236, 150.0]))
    cv.paint(rad <= 4 + 14 * np.abs(np.cos(ang * 2)) ** 16, np.array([255, 255, 240.0]))
    return cv


# ---------------------------------------------------------------- sprite table
def build_sprites():
    sprites: list[tuple[str, Canvas]] = [("EMPTY", Canvas())]

    def whole(name, fn):
        cv = Canvas()
        fn(cv)
        sprites.append((name, cv))

    whole("WATERMELON", lambda cv: body_watermelon(cv, 32, 32, -22))
    sprites.append(("WATERMELON_HALF", half_of(
        lambda cv, x, y: body_watermelon(cv, x, y, 0), dict(
            rings=[(1.0, (40, 120, 40)), (0.90, (220, 238, 180)), (0.80, (232, 46, 52))],
            seeds=(0.55, 9, (24, 18, 16), 1.9)), 29, 22)))
    whole("ORANGE", lambda cv: body_orange(cv, 32, 32))
    sprites.append(("ORANGE_HALF", half_of(body_orange, dict(
        rings=[(1.0, (255, 140, 16)), (0.90, (255, 236, 196)), (0.84, (255, 168, 36))],
        segments=(10, (255, 222, 150), 0.16, 0.84)), 24, 24)))
    whole("APPLE", lambda cv: body_apple(cv, 32, 33))
    sprites.append(("APPLE_HALF", half_of(body_apple, dict(
        rings=[(1.0, (196, 24, 30)), (0.92, (252, 240, 190))],
        core_fn=core_apple), 24, 24)))
    whole("LEMON", lambda cv: body_lemon(cv, 32, 32, 18))
    sprites.append(("LEMON_HALF", half_of(
        lambda cv, x, y: body_lemon(cv, x, y, 0), dict(
            rings=[(1.0, (246, 214, 30)), (0.90, (255, 250, 214)), (0.83, (255, 240, 130))],
            segments=(9, (255, 252, 222), 0.14, 0.83)), 25, 19)))
    whole("KIWI", lambda cv: body_kiwi(cv, 32, 32, -15))
    sprites.append(("KIWI_HALF", half_of(
        lambda cv, x, y: body_kiwi(cv, x, y, 0), dict(
            rings=[(1.0, (120, 84, 40)), (0.92, (132, 204, 44)), (0.55, (160, 220, 70))],
            core_fn=seeds_kiwi, seeds=(0.40, 16, (20, 20, 16), 1.3)), 25, 20)))
    sprites.append(("BOMB", sprite_bomb()))
    sprites.append(("SPLASH_RED", sprite_splash((204, 22, 34), (244, 84, 84), 1)))
    sprites.append(("SPLASH_ORANGE", sprite_splash((240, 124, 10), (255, 176, 70), 2)))
    sprites.append(("SPLASH_YELLOW", sprite_splash((232, 204, 24), (255, 242, 110), 3)))
    sprites.append(("SPLASH_GREEN", sprite_splash((104, 184, 30), (164, 224, 86), 4)))
    sprites.append(("X_RED", sprite_x((232, 36, 30), (90, 10, 8))))
    sprites.append(("X_GRAY", sprite_x((120, 110, 100), (50, 40, 32))))
    sprites.append(("SPARKLE", sprite_sparkle()))
    assert len(sprites) <= F.SPR_SLOTS
    return sprites


def quantize(images):
    """Map all opaque sprite pixels to a shared 192-colour palette."""
    pix = np.concatenate([rgb[op] for rgb, op in images if op.any()]).astype(np.uint8)
    strip = Image.fromarray(pix.reshape(1, -1, 3), "RGB")
    q = strip.quantize(colors=F.PAL_SPR_COUNT, method=Image.Quantize.MEDIANCUT,
                       kmeans=3, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[: F.PAL_SPR_COUNT * 3]).reshape(-1, 3)
    out = []
    for rgb, op in images:
        idx = np.zeros((N, N), dtype=np.int32)
        if op.any():
            p = rgb[op].astype(float)
            d = ((p[:, None, :] - pal[None, :, :]) ** 2).sum(-1)
            idx[op] = d.argmin(1) + F.PAL_SPR_BASE
        out.append(idx)
    return [tuple(int(v) for v in c) for c in pal], out


# ---------------------------------------------------------------- font
FONT_FILE = Path("C:/Windows/Fonts/segoeuib.ttf")


def build_font():
    font = ImageFont.truetype(str(FONT_FILE), 15)
    ascent, _ = font.getmetrics()
    baseline = 12
    rows = np.zeros((128, F.GLYPH_H), dtype=np.int64)
    widths = [0] * 128
    for code in range(32, 127):
        ch = chr(code)
        img = Image.new("L", (32, 24), 0)
        d = ImageDraw.Draw(img)
        d.text((2, baseline - ascent), ch, font=font, fill=255)
        a = np.array(img)[:F.GLYPH_H] >= 110
        cols = np.where(a.any(0))[0]
        if cols.size:
            a = a[:, cols[0]:cols[0] + F.GLYPH_W]
            w = min(F.GLYPH_W, cols[-1] - cols[0] + 1)
        else:
            a = np.zeros((F.GLYPH_H, F.GLYPH_W), dtype=bool)
            w = 4
        glyph = np.zeros((F.GLYPH_H, F.GLYPH_W), dtype=bool)
        glyph[:, :a.shape[1]] = a[:, :F.GLYPH_W]
        for r in range(F.GLYPH_H):
            v = 0
            for c in range(F.GLYPH_W):
                v = (v << 1) | int(glyph[r, c])
            rows[code, r] = v
        widths[code] = int(w)
    widths[32] = 5
    return rows, widths


# ---------------------------------------------------------------- outputs
def write_header(names, widths):
    lines = ["/* Generated by assets/gen_assets.py -- do not edit. */",
             "#ifndef FN_ASSETS_H", "#define FN_ASSETS_H", "",
             "/* sprite image ids (64x64, index 0 transparent) */"]
    for i, n in enumerate(names):
        lines.append(f"#define SPR_{n:<16s} {i}")
    lines += [f"#define SPR_COUNT {len(names)}", "", "/* fixed palette indices */"]
    for i, (n, _) in enumerate(F.UI_COLORS):
        lines.append(f"#define COL_{n:<14s} {i}")
    lines += [f"#define COL_BG_BASE     {F.PAL_BG_BASE}",
              f"#define COL_BLADE_RAMP  {F.PAL_FX_BASE}",
              f"#define COL_FIRE_RAMP   {F.PAL_FX_BASE + 8}",
              "", "/* glyph advance widths (pixels, before scaling) */",
              "static const unsigned char fn_glyph_width[128] = {"]
    for r in range(0, 128, 16):
        lines.append("    " + ", ".join(f"{w:2d}" for w in widths[r:r + 16]) + ",")
    lines += ["};", "", "#endif", ""]
    (FW / "assets.h").write_text("\n".join(lines), encoding="utf-8")


def write_sprite_rom(rom: np.ndarray) -> list[int]:
    """Per-image 4K x 8 ROM banks + generated Verilog wrapper.

    One bank per used image (exactly one DRM each, no DRM cascades) and a
    registered output select, 2-cycle latency like a single inferred ROM.
    """
    sdir = BUILD / "spr"
    sdir.mkdir(exist_ok=True)
    used = [i for i in range(F.SPR_SLOTS) if rom[i].any()]
    for i in used:
        F.write_hex(sdir / f"spr_{i:02d}.hex", rom[i].reshape(-1).tolist(), 2)
    v = ["`timescale 1ns / 1ps",
         "// Generated by assets/gen_assets.py -- do not edit.",
         "// Sprite ROM: 32 image slots x 64 x 64 x 8 bit, address {image[4:0], v[5:0], u[5:0]}.",
         "// One 4K x 8 bank (one DRM) per used image; empty slots read 0.  Latency 2.",
         "module fn_rom4k #(parameter INIT = \"\") (",
         "    input  wire        clk,",
         "    input  wire [11:0] addr,",
         "    output reg  [7:0]  q",
         ");",
         "    reg [7:0] rom [0:4095];",
         "    initial $readmemh(INIT, rom);",
         "    always @(posedge clk) q <= rom[addr];",
         "endmodule",
         "",
         "module fn_sprite_rom (",
         "    input  wire        clk,",
         "    input  wire [16:0] addr,",
         "    output reg  [7:0]  q",
         ");"]
    for i in used:
        v.append(f"    wire [7:0] q{i:02d};")
    for i in used:
        path = (sdir / f"spr_{i:02d}.hex").as_posix()
        v.append(f"    fn_rom4k #(.INIT(\"{path}\")) u_b{i:02d} (.clk(clk), .addr(addr[11:0]), .q(q{i:02d}));")
    v += ["    reg [4:0] sel;",
          "    always @(posedge clk) sel <= addr[16:12];",
          "    always @(posedge clk) begin",
          "        case (sel)"]
    for i in used:
        v.append(f"            5'd{i}: q <= q{i:02d};")
    v += ["            default: q <= 8'd0;", "        endcase", "    end", "endmodule", ""]
    (ROOT / "rtl" / "video" / "fn_sprite_rom.v").write_text("\n".join(v), encoding="utf-8")
    return used


def main() -> None:
    BUILD.mkdir(exist_ok=True)
    sprites = build_sprites()
    names = [n for n, _ in sprites]
    images = [cv.downsample() for _, cv in sprites]
    spr_pal, idx_imgs = quantize(images)
    pal = F.base_palette() + spr_pal
    pal += [(0, 0, 0)] * (256 - len(pal))

    rom = np.zeros((F.SPR_SLOTS, N, N), dtype=np.int32)
    for i, im in enumerate(idx_imgs):
        rom[i] = im
    F.write_hex(BUILD / "sprites.hex", rom.reshape(-1).tolist(), 2)
    write_sprite_rom(rom)
    F.write_hex(BUILD / "palette.hex", [(r << 16) | (g << 8) | b for r, g, b in pal], 6)
    rows, widths = build_font()
    F.write_hex(BUILD / "font.hex", rows.reshape(-1).tolist(), 4)
    (ROOT / "rtl" / "video" / "fn_bg_lut.vh").write_text(F.verilog_bg_lut(), encoding="utf-8")
    write_header(names, widths)

    # previews
    pal_arr = np.array(pal, dtype=np.uint8)
    sheet = Image.new("RGB", (8 * (N + 4), 4 * (N + 4)), (70, 40, 20))
    for i in range(F.SPR_SLOTS):
        im = rom[i]
        rgb = pal_arr[im]
        a = Image.fromarray(rgb, "RGB")
        m = Image.fromarray(((im != 0) * 255).astype(np.uint8), "L")
        sheet.paste(a, ((i % 8) * (N + 4) + 2, (i // 8) * (N + 4) + 2), m)
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(BUILD / "preview_sprites.png")
    fimg = np.zeros((8 * 18, 16 * 18), dtype=np.uint8)
    for code in range(128):
        gx, gy = (code % 16) * 18 + 1, (code // 16) * 18 + 1
        for r in range(16):
            for c in range(16):
                if (rows[code, r] >> (15 - c)) & 1:
                    fimg[gy + r, gx + c] = 255
    Image.fromarray(fimg, "L").resize((16 * 18 * 3, 8 * 18 * 3), Image.NEAREST).save(BUILD / "preview_font.png")
    used = sum(1 for n in names if n != "EMPTY")
    print(f"sprites: {used} images, palette sprite colours: {len(spr_pal)}")


if __name__ == "__main__":
    main()
