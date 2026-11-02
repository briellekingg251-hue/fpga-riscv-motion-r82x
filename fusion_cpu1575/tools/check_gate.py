"""Match gate-level frames (sim/out_gate/gate_frame_<n>.hex) against the
reference-model frames of the same firmware (commands from the RTL system
simulation in sim/out_title/sys_cmds.hex).  A frame passes if it is identical
to the model output after some swap (or the all-black power-up frame)."""
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
    model = G.GpuModel()
    refs = {"black (before first swap)": model.frame().copy()}
    swap = 0
    for ln in (ROOT / "sim" / "out_title" / "sys_cmds.hex").read_text().split():
        v = int(ln, 16)
        model.write((v >> 32) & 63, v & 0xFFFFFFFF)
        if ((v >> 32) & 63) == G.C_SWAP:
            swap += 1
            refs[f"model swap {swap}"] = model.frame().copy()
    bad = 0
    shown = 0
    for f in sorted((ROOT / "sim" / "out_gate").glob("gate_frame_*.hex"),
                    key=lambda p: int(p.stem.split("_")[-1])):
        try:
            got = load_hex_frame(f)
        except SystemExit as e:
            print(f"{f.name}: incomplete ({e})")
            continue
        hit = next((name for name, ref in refs.items() if np.array_equal(got, ref)), None)
        if hit and "swap" in hit:
            shown += 1
            Image.fromarray(got, "RGB").save(ROOT / "build" / f"gate_{f.stem}.png")
        print(f"{f.name}: {'MATCH ' + hit if hit else 'NO MATCH'}")
        bad += hit is None
    print("PASS" if bad == 0 and shown else "FAIL")
    return 0 if bad == 0 and shown else 1


if __name__ == "__main__":
    raise SystemExit(main())
