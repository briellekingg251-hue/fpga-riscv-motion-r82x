"""Assemble the 162 MHz SD tree for the NES hardware: current game card + GAMES/NES.

Copies fusion firmware_o2_view/games_162_r62_run01/sdcard (the 162 MHz package
used by R62..R65) and adds build/sdcard/GAMES/NES from this workspace, into a
new fusion directory firmware_o2_view/<name>/sdcard, with a RESULT.json that
records CPU_Hz (checked by the fusion release tools) and every file hash.
Never overwrites an existing directory.

usage: python -I tools/make_nes_sd_tree.py [--name games_162_r65_nes_run01] [--base games_162_r62_run01]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc

FUSION = Path("E:/Codex_workplace/cpu_pose_touch_fusion_20261008")
BASE = FUSION / "firmware_o2_view/games_162_r62_run01"
NES = nc.ROOT / "build/sdcard/GAMES/NES"
CPU_HZ = 162000000


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", default="games_162_r65_nes_run01")
    parser.add_argument("--base", default=BASE.name, help="162 MHz games build under fusion firmware_o2_view/")
    args = parser.parse_args()
    base = FUSION / "firmware_o2_view" / args.base
    out = FUSION / "firmware_o2_view" / args.name
    if out.exists():
        raise SystemExit(f"{out} exists; never overwritten")
    base_result = json.loads((base / "RESULT.json").read_text())
    if base_result["CPU_Hz"] != CPU_HZ:
        raise SystemExit("base card is not the 162 MHz build")
    build = json.loads((nc.ROOT / "build/rv32/RESULT.json").read_text())
    if build["status"] != "NES_RV32_BUILD_PASS" or build["cpu_hz"] != CPU_HZ:
        raise SystemExit("NES package is not a passing 162 MHz build")
    for name, digest in build["package_sha256"].items():
        if nc.sha256(NES / name) != digest:
            raise SystemExit(f"NES package file changed since build: {name}")
    shutil.copytree(base / "sdcard", out / "sdcard")
    if (out / "sdcard/GAMES/NES").exists():
        raise SystemExit("base card already has GAMES/NES")
    shutil.copytree(NES, out / "sdcard/GAMES/NES")
    files = {p.relative_to(out / "sdcard").as_posix(): nc.sha256(p)
             for p in sorted((out / "sdcard").rglob("*")) if p.is_file()}
    result = {"status": "NES_SD_TREE_BUILT", "CPU_Hz": CPU_HZ, "base_card": str(base / "sdcard"),
              "base_RESULT_sha256": nc.sha256(base / "RESULT.json"),
              "nes_build_RESULT_sha256": nc.sha256(nc.ROOT / "build/rv32/RESULT.json"),
              "tool": str(Path(__file__)), "tool_sha256": nc.sha256(Path(__file__)),
              "note": ".NES files are local copies of commercial dumps from the upstream repo; not for redistribution",
              "files": files, "physical_SD_written": False}
    (out / "RESULT.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    games = sorted(p.name for p in (out / "sdcard/GAMES").iterdir() if p.is_dir())
    print(json.dumps({"out": str(out), "games": games, "files": len(files)}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
