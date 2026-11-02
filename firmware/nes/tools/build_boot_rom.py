"""Rebuild the 162 MHz resident loader ROM with the NES package whitelisted.

The loader only starts packages whose game ID it knows.  This tool replays the
exact recorded build of the current 162 MHz ROM (fusion firmware_o2_view/
build_162_run01, RESULT.json 'commands') on a copy of its sources:

  1. replay unchanged  -> program.hex must be byte-identical to the original;
  2. apply the NES patch (two lines) -> new program.hex.

Only control.h (catalog capabilities: NES is a touch game) and boot.c (ABI-3
whitelist) change.  The ROM window limit (24576 bytes) is enforced.

usage: python -I tools/build_boot_rom.py [--src <build_162_run01>]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc

DEFAULT_SRC = Path("E:/Codex_workplace/cpu_pose_touch_fusion_20261008/firmware_o2_view/build_162_run01")
OUT = nc.ROOT / "build/boot"
ROM_BYTES = 131072
ROM_LOADER_OFFSET = 0x18000
ROM_LOADER_MAX = 24576
PATCHES = [
    ("fw/control.h",
     "#define CONTROL_GAME_VIEW 0x50564945u\n",
     "#define CONTROL_GAME_VIEW 0x50564945u\n#define CONTROL_GAME_NES 0x4e455331u\n"),
    ("fw/control.h",
     "    if(id==CONTROL_GAME_PAL || id==CONTROL_GAME_DOOM || id==CONTROL_GAME_SLUG)return CONTROL_CAP_TOUCH;",
     "    if(id==CONTROL_GAME_PAL || id==CONTROL_GAME_DOOM || id==CONTROL_GAME_SLUG ||\n"
     "       id==CONTROL_GAME_NES)return CONTROL_CAP_TOUCH;"),
    ("fw/boot.c",
     "id==CONTROL_GAME_SLUG || id==CONTROL_GAME_VIEW)));",
     "id==CONTROL_GAME_SLUG || id==CONTROL_GAME_VIEW ||\n"
     "                            id==CONTROL_GAME_NES)));"),
]


def copy_tree(src: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "fw").parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src / "fw", dest / "fw")


def replay(record: dict, src: Path, dest: Path) -> None:
    for step in record["commands"]:
        if not step["name"].startswith("boot"):
            continue   # the POSEVIEW package is not part of the ROM
        command = [arg.replace(str(src), str(dest)) for arg in step["command"]]
        # Never let a command touch the frozen source build: every path that
        # named it must now name the copy.
        stale = [arg for arg in command if src.name in arg and str(dest) not in arg]
        if stale:
            raise RuntimeError(f"recorded command still points at the source build: {stale[:2]}")
        nc.run(command, dest / f"{step['name']}.log", cwd=dest)


def write_rom(dest: Path) -> int:
    blob = (dest / "boot.bin").read_bytes()
    if len(blob) > ROM_LOADER_MAX:
        raise RuntimeError(f"loader exceeds the ROM window: {len(blob)} > {ROM_LOADER_MAX}")
    image = bytearray(ROM_BYTES)
    image[ROM_LOADER_OFFSET:ROM_LOADER_OFFSET + len(blob)] = blob
    (dest / "program.hex").write_text("".join(
        f"{int.from_bytes(image[i:i + 4], 'little'):08x}\n" for i in range(0, ROM_BYTES, 4)),
        encoding="ascii")
    return len(blob)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--src", type=Path, default=DEFAULT_SRC)
    args = parser.parse_args()
    src = args.src.resolve()
    record = json.loads((src / "RESULT.json").read_text())
    if record.get("CPU_Hz") != 162000000:
        raise RuntimeError("source ROM build is not the 162 MHz build")
    OUT.mkdir(parents=True, exist_ok=True)

    original = OUT / "replay"
    copy_tree(src, original)
    replay(record, src, original)
    write_rom(original)
    if nc.sha256(original / "program.hex") != nc.sha256(src / "program.hex"):
        raise RuntimeError("unpatched replay does not reproduce the recorded program.hex")

    patched = OUT / "nes"
    copy_tree(src, patched)
    for name, old, new in PATCHES:
        path = patched / name
        text = path.read_text()
        if text.count(old) != 1:
            raise RuntimeError(f"patch target not unique in {name}")
        path.write_text(text.replace(old, new))
    replay(record, src, patched)
    loader = write_rom(patched)
    if nc.sha256(patched / "program.hex") == nc.sha256(src / "program.hex"):
        raise RuntimeError("patched ROM is identical to the original")
    # The compiler folds the ID comparisons, so no literal is checked here;
    # tools/run_iss.py proves functionally that this loader starts GAMES/NES.
    if (patched / "boot.bin").read_bytes() == (original / "boot.bin").read_bytes():
        raise RuntimeError("patched loader code is identical to the original")
    result = {
        "status": "BOOT_ROM_NES_PASS", "cpu_hz": 162000000,
        "source_build": str(src), "source_program_hex_sha256": nc.sha256(src / "program.hex"),
        "replay_identical": True, "loader_bytes": loader, "loader_limit": ROM_LOADER_MAX,
        "loader_bytes_original": (original / "boot.bin").stat().st_size,
        "patches": [{"file": n, "old": o, "new": w} for n, o, w in PATCHES],
        "program_hex_sha256": nc.sha256(patched / "program.hex"),
        "tool_sha256": nc.sha256(Path(__file__)),
    }
    (OUT / "RESULT.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("status", "loader_bytes", "loader_bytes_original",
                                             "program_hex_sha256")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
