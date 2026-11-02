"""End-to-end check: replay the GPU commands the CPU issued in the full-system
simulation through the reference model and compare every captured frame.

usage: python tools/replay_cmds.py [sim/out]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import gpu_model as G  # noqa: E402
from compare_frame import load_hex_frame  # noqa: E402


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "sim" / "out"
    lines = (out / "sys_cmds.hex").read_text().split()
    model = G.GpuModel()
    frames = []
    counts = []
    n = 0
    for ln in lines:
        v = int(ln, 16)
        idx, data = (v >> 32) & 63, v & 0xFFFFFFFF
        model.write(idx, data)
        n += 1
        if idx == G.C_SWAP:
            frames.append(model.frame().copy())
            counts.append(n)
    print(f"{len(lines)} commands, {len(frames)} swaps (commands per frame: "
          f"{[b - a for a, b in zip([0] + counts, counts)]})")
    bad = 0
    for k in range(1, len(frames) + 1):
        f = out / f"sys_frame_{k}.hex"
        if not f.exists():
            continue
        got = load_hex_frame(f)
        exp = frames[k - 1]
        Image.fromarray(got, "RGB").save(ROOT / "build" / f"sys_frame_{k}.png")
        diff = int(np.any(got != exp, axis=-1).sum())
        print(f"frame {k}: {'MATCH' if diff == 0 else f'MISMATCH {diff} px'}")
        bad += diff != 0
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
