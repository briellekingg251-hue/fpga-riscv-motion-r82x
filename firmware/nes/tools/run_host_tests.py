"""Host verification: pure-module unit tests, then real InfoNES on every ROM.

Each ROM runs headless for --frames frames with a scripted joypad (START, then
movement and A/B), and every presented frame is checked texel-for-texel by the
harness.  PPM frames are converted to PNG for review.

usage: python -I tools/run_host_tests.py [--roms roms] [--frames 1200]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc

OUT = nc.ROOT / "build/host"
# START at ~2 s and ~4 s (title screens, game select), then play.
SCRIPT = """120 126 08
240 246 08
300 900 80
360 362 01
480 482 01
600 602 02
700 760 40
800 802 01
"""
CFLAGS = ["-std=gnu99", "-O2", "-g", "-fno-strict-aliasing", "-fsanitize=undefined",
          "-fsanitize-trap"]


def build(stage: Path) -> tuple[Path, Path]:
    env = nc.host_env()
    port = nc.PORT
    pure = OUT / "test_pure.exe"
    nc.run([nc.HOST_GCC, *CFLAGS, "-Wall", "-Wextra", "-Werror", f"-I{port}",
            nc.ROOT / "tests/test_pure.c", port / "nes_rom.c", port / "nes_pad.c",
            port / "nes_menu.c", port / "nes_frame.c", "-o", pure], OUT / "test_pure.log", env)
    harness = OUT / "nes_host.exe"
    # Upstream InfoNES is built with warnings off; the port units are -Werror.
    core = [stage / f"{u}.cpp" for u in nc.CORE_UNITS]
    # Gate: the patched core must be free of sequence-point undefined behaviour.
    for src in core:
        nc.run([nc.HOST_GCC, *nc.CXX_FLAGS, "-fsyntax-only", "-w", "-Wsequence-point",
                "-Werror=sequence-point", f"-I{stage}", src], None, env)
    objs = []
    for src in core:
        obj = OUT / (src.stem + ".o")
        nc.run([nc.HOST_GCC, *nc.CXX_FLAGS, *[f for f in CFLAGS if f != "-std=gnu99"], "-w",
                f"-I{stage}", "-c", src, "-o", obj], None, env)
        objs.append(obj)
    port_src = [port / n for n in ("nes_system.c", "nes_rom.c", "nes_frame.c", "nes_mapper.c")]
    nc.run([nc.HOST_GCC, *CFLAGS, "-Wall", "-Wextra", "-Werror", "-Wno-old-style-declaration",
            f"-I{stage}", f"-I{port}", nc.ROOT / "tests/nes_host.c", *port_src, *objs, "-o", harness],
           OUT / "nes_host.log", env)
    return pure, harness


def ppm_to_png(directory: Path) -> int:
    try:
        from PIL import Image
    except ImportError:
        return 0
    count = 0
    for ppm in sorted(directory.glob("*.ppm")):
        Image.open(ppm).save(ppm.with_suffix(".png"))
        ppm.unlink()
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--roms", type=Path, default=nc.ROOT / "roms")
    parser.add_argument("--frames", type=int, default=1200)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    stage = OUT / "stage"
    hashes = nc.stage_infones(stage)
    pure, harness = build(stage)
    report = {"pure": nc.run([pure]).strip(), "roms": {}, "infones_sha256": hashes}
    script = OUT / "script.txt"
    script.write_text(SCRIPT, encoding="ascii")
    failed = 0
    for rom in sorted(args.roms.glob("*.NES")):
        frames_dir = OUT / "frames" / rom.stem
        frames_dir.mkdir(parents=True, exist_ok=True)
        for old in frames_dir.glob("*"):
            old.unlink()
        start = time.perf_counter()
        try:
            text = nc.run([harness, rom, frames_dir, args.frames, script], env=nc.host_env())
            line = re.search(r"^HOST_RESULT (.*)$", text, re.M)
            result = dict(kv.split("=") for kv in line.group(1).split()) if line else {"error": "no result"}
        except RuntimeError as exc:
            result, failed = {"error": str(exc)[-400:]}, failed + 1
        result["seconds"] = round(time.perf_counter() - start, 2)
        result["png"] = ppm_to_png(frames_dir)
        report["roms"][rom.name] = result
        print(rom.name, result)
    (OUT / "RESULT.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(report["pure"])
    print("HOST_TESTS", "FAIL" if failed else "PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
