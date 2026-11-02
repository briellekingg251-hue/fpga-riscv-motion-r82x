"""Compare an RTL-captured frame (rrggbb per line) with a model frame (.npy)."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load_hex_frame(path: Path) -> np.ndarray:
    vals = np.array([int(l, 16) for l in path.read_text().split()], dtype=np.uint32)
    if vals.size != 1024 * 600:
        raise SystemExit(f"{path}: {vals.size} pixels, expected {1024 * 600}")
    rgb = np.stack([(vals >> 16) & 255, (vals >> 8) & 255, vals & 255], -1).astype(np.uint8)
    return rgb.reshape(600, 1024, 3)


def main() -> int:
    got_path, png_out = Path(sys.argv[1]), Path(sys.argv[2])
    got = load_hex_frame(got_path)
    Image.fromarray(got, "RGB").save(png_out)
    if len(sys.argv) > 3:
        exp = np.load(sys.argv[3])
        diff = np.any(got != exp, axis=-1)
        n = int(diff.sum())
        if n:
            ys, xs = np.nonzero(diff)
            print(f"MISMATCH {got_path.name}: {n} pixels differ, first at x={xs[0]} y={ys[0]} "
                  f"got={got[ys[0], xs[0]]} exp={exp[ys[0], xs[0]]}")
            Image.fromarray((diff * 255).astype(np.uint8), "L").save(png_out.with_suffix(".diff.png"))
            return 1
        print(f"MATCH {got_path.name}: all {diff.size} pixels identical")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
