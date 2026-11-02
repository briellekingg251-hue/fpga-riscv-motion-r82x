"""Build the GPU unit-test command stream and the expected frames.

Writes:
  sim/gpu_cmds.hex        one 40-bit entry per line: {2'b0, idx[5:0], data[31:0]}
  build/expected_f1.npy/png, build/expected_f2.npy/png
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import gpu_model as G  # noqa: E402


def scene_frame1(widths):
    c = [(G.C_BG, 0)]
    c += G.sprite_cmds(1, 90, 80)                               # watermelon, 1:1
    c += G.sprite_cmds(3, 200, 70, angle=32)                    # orange rotated 45 deg
    c += G.sprite_cmds(5, 310, 90, scale_q8=384, angle=16)      # apple 1.5x rotated
    c += G.sprite_cmds(7, 420, 80, flip=True)                   # lemon mirrored
    c += G.sprite_cmds(2, 80, 200, angle=200)                   # watermelon half
    c += G.sprite_cmds(2, 130, 210, angle=72, flip=True)        # other half
    c += G.sprite_cmds(11, 250, 210, scale_q8=192)              # bomb 0.75x
    c += G.sprite_cmds(9, 350, 220, solid=True, color=1)        # kiwi white silhouette
    c += G.sprite_cmds(12, 460, 230, scale_q8=512)              # splash 2x, right edge clip
    c += G.sprite_cmds(10, 10, 10, angle=100)                   # clip top-left
    c += G.sprite_cmds(4, 500, 295, angle=10)                   # clip bottom-right
    c += [(G.R_COLOR, 4), (G.R_DST, (130 << 16) | 170), (G.R_SIZE, (20 << 16) | 60), (G.C_RECT, 0)]
    for k in range(24):                                         # blade trail
        c.append(G.circle_cmd(40 + 18 * k, 150 + (k * k) // 6 - 2 * k, 1 + k // 4, 48 + (k % 8)))
    c += G.text_cmds(12, 6, "Score 1234", 12, 2, widths)
    c += G.text_cmds(10, 4, "Score 1234", 4, 2, widths)
    c += G.text_cmds(300, 262, "FPGA Fruit!", 1, 1, widths)
    c += G.text_cmds(170, 120, "Ninja", 3, 3, widths)
    c += [(G.C_PALETTE, (15 << 24) | 0x20E0A0)]                 # recolour BLUE -> mint
    c += G.text_cmds(8, 270, "pal", 15, 1, widths)
    for k in range(40):
        c.append((G.C_PSET, (200 + k) | ((290 - k // 2) << 9) | (1 << 24)))
    c.append((G.C_SWAP, 0))
    return c


def scene_frame2(widths):
    c = [(G.C_CLEAR, 2)]
    c += G.sprite_cmds(1, 256, 150, scale_q8=768, angle=20)     # big 3x watermelon
    c += G.sprite_cmds(16, 60, 60)
    c += G.sprite_cmds(17, 130, 60)
    c += G.text_cmds(140, 250, "Frame 2 OK", 1, 2, widths)
    c += [(G.R_DST, (0xFFF0 << 16) | 0xFFF0), (G.R_SIZE, (40 << 16) | 40),
          (G.R_U0, 0), (G.R_V0, 0), (G.R_DUDX, 1 << 16), (G.R_DVDX, 0), (G.R_DUDY, 0),
          (G.R_DVDY, 1 << 16), (G.R_COLOR, 3), (G.C_GLYPH, ord("A"))]  # glyph via affine
    c.append(G.circle_cmd(480, 40, 30, 7))
    c.append((G.C_SWAP, 0))
    return c


def scene_frame3(widths):
    """FIFO back-pressure test: pushed right after SWAP 2 while the GPU is parked
    waiting for the frame boundary, so the 1024-entry FIFO must fill up and the
    CPU-side store must stall without dropping anything."""
    c = [(G.C_CLEAR, 11)]
    for k in range(1100):
        x = (k * 37) % 512
        y = (k * 53 + k // 7) % 300
        c.append((G.C_PSET, x | (y << 9) | ((64 + k % 192) << 24)))
    c += G.text_cmds(150, 140, "FIFO full OK", 4, 2, widths)
    c.append((G.C_SWAP, 0))
    return c


def main() -> None:
    widths = G.glyph_widths()
    cmds = scene_frame1(widths) + scene_frame2(widths) + scene_frame3(widths)
    model = G.GpuModel()
    frames = []
    for idx, data in cmds:
        model.write(idx, data)
        if idx == G.C_SWAP:
            frames.append(model.frame().copy())
    (ROOT / "sim").mkdir(exist_ok=True)
    with open(ROOT / "sim" / "gpu_cmds.hex", "w", newline="\n") as f:
        for idx, data in cmds:
            f.write(f"{(idx << 32) | (data & 0xFFFFFFFF):010x}\n")
    for k, fr in enumerate(frames, 1):
        np.save(ROOT / "build" / f"expected_f{k}.npy", fr)
        G.save_png(fr, ROOT / "build" / f"expected_f{k}.png")
    print(f"{len(cmds)} commands, {len(frames)} frames, raster pixels {model.pixels_touched}")


if __name__ == "__main__":
    main()
