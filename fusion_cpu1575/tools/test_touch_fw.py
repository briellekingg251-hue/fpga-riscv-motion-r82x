"""Run actual C firmware input/state tests for all eight panel orientations.

Usage: python tools/test_touch_fw.py [--cc path/to/host/c/compiler]
Uses CC, a native gcc/clang on PATH, or the small local TinyCC installation.
The cross compiler for RV32 is intentionally not used for these host tests.
"""
from __future__ import annotations

import argparse
import itertools
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", help="native C compiler executable")
    args = parser.parse_args()
    compiler = args.cc or os.environ.get("CC") or shutil.which("gcc") or shutil.which("clang")
    if not compiler:
        tcc = Path("F:/Codex_workplace/tools/tcc-0.9.27-win64/tcc/tcc.exe")
        if tcc.is_file():
            compiler = str(tcc)
    if not compiler:
        parser.error("No native C compiler found; supply --cc (gcc, clang or tcc).")
    BUILD.mkdir(exist_ok=True)
    log = []
    cases = 0
    try:
        for swap, mx, my in itertools.product((0, 1), repeat=3):
            exe = BUILD / f"test_touch_fw_{swap}{mx}{my}{'.exe' if os.name == 'nt' else ''}"
            commands = [
                [compiler, "-std=c99", "-Wall", "-Wextra", "-DFN_SD_ENABLED=0",
                 f"-DFN_TOUCH_SWAP_XY={swap}", f"-DFN_TOUCH_MIRROR_X={mx}",
                 f"-DFN_TOUCH_MIRROR_Y={my}", "-o", str(exe),
                 str(ROOT / "sim/test_touch_fw.c"), str(ROOT / "fw/gpu.c")],
                [str(exe)],
            ]
            for command in commands:
                result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
                output = result.stdout + result.stderr
                if output:
                    print(output, end="")
                    log.append(output)
                if result.returncode:
                    raise SystemExit(f"FAILED ({result.returncode}): {command}")
                if len(command) == 1:
                    match = re.search(r", (\d+) cases", output)
                    if not match:
                        raise SystemExit("FAILED: test executable did not report its case count")
                    cases += int(match.group(1))
        summary = f"PASS: {cases} firmware behavior/orientation cases\n"
        print(summary, end="")
        log.append(summary)
    finally:
        (ROOT / "sim/touch_fw_test.log").write_text("".join(log), encoding="utf-8")


if __name__ == "__main__":
    main()
