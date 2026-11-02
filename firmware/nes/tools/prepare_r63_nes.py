"""Prepare hardware candidate R63 = R62 (CPU 162 MHz) + NES-whitelisting boot ROM.

R63 is a copy of fusion hardware/production_r62_o2_cpu162_cam15_view in which
exactly one design input changes: the resident loader image `FN_PROGRAM_HEX.
The new image (tools/build_boot_rom.py) is the recorded 162 MHz loader with
the NES game ID added to its ABI-3 whitelist; it is frozen into the R63
directory so the candidate does not depend on this workspace's build/ tree.

All clocks, PLLs, constraints, floorplan and the CPU RTL are R62's, byte for
byte (except the ROM path inside fn_design.v / fn_design_sim.v and the R62
directory name in source_base.tcl).  The script refuses to run if R62's files
differ from its ASSEMBLY record or if R63 already exists.

It only adds a new directory under the fusion project's hardware/ (the native
flow accepts hardware there only); nothing existing is modified.

usage: python -I tools/prepare_r63_nes.py [--base <hardware dir name>] [--out <new dir name>]
  --base defaults to R62; when the platform timing line moves (e.g. R64), pass
  it here so the NES variant always tracks the current timing candidate.
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
BASE = FUSION / "hardware/production_r62_o2_cpu162_cam15_view"
OUT = FUSION / "hardware/production_r63_nes_cpu162"
ROM_NAME = "boot_nes_program.hex"
BOOT_RESULT = nc.ROOT / "build/boot/RESULT.json"
TEXT_FILES = ("fn_design.v", "fn_design_sim.v", "source_base.tcl")


def replace_once(text: str, old: str, new: str, where: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"{where}: anchor not unique: {old[:80]}")
    return text.replace(old, new)


def main() -> int:
    global BASE, OUT
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default=BASE.name)
    parser.add_argument("--out", default=OUT.name)
    args = parser.parse_args()
    BASE, OUT = FUSION / "hardware" / args.base, FUSION / "hardware" / args.out
    if BASE.resolve().parent != OUT.resolve().parent or not BASE.is_dir():
        raise RuntimeError("base and out must be directories under fusion hardware/")
    if OUT.exists():
        raise RuntimeError("R63 exists; frozen candidates are never overwritten")
    meta = json.loads((BASE / "ASSEMBLY.json").read_text())
    for name, digest in meta["files"].items():
        if nc.sha256(BASE / name) != digest:
            raise RuntimeError(f"R62 file differs from its ASSEMBLY record: {name}")
    if nc.sha256(Path(meta["ROM"])) != meta["ROM_sha256"]:
        raise RuntimeError("R62 ROM differs from its ASSEMBLY record")
    boot = json.loads(BOOT_RESULT.read_text())
    if boot["status"] != "BOOT_ROM_NES_PASS" or not boot["replay_identical"] or \
            boot["source_program_hex_sha256"] != meta["ROM_sha256"]:
        raise RuntimeError("NES boot ROM was not built from R62's ROM with a verified replay")
    rom = nc.ROOT / "build/boot/nes/program.hex"
    if nc.sha256(rom) != boot["program_hex_sha256"]:
        raise RuntimeError("NES boot ROM changed since build_boot_rom.py")

    old_rom, new_rom = Path(meta["ROM"]).as_posix(), (OUT / ROM_NAME).as_posix()
    edited = {}
    for name in TEXT_FILES:
        data = (BASE / name).read_bytes().decode()
        if name != "source_base.tcl":
            data = replace_once(data, f'`define FN_PROGRAM_HEX "{old_rom}"',
                                f'`define FN_PROGRAM_HEX "{new_rom}"', name)
            data = replace_once(data, f"`define FN_PROGRAM_HEX_BITS {len(old_rom) * 8}",
                                f"`define FN_PROGRAM_HEX_BITS {len(new_rom) * 8}", name)
        data = data.replace(BASE.as_posix(), OUT.as_posix())
        if BASE.name in data or Path(old_rom).parent.name in data:
            raise RuntimeError(f"{name}: residual R62 path or R62 ROM")
        if name != "source_base.tcl" and data.count(new_rom) != 1:
            raise RuntimeError(f"{name}: NES ROM path not bound exactly once")
        edited[name] = data.encode()

    shutil.copytree(BASE, OUT)
    for name, data in edited.items():
        (OUT / name).write_bytes(data)
    shutil.copyfile(rom, OUT / ROM_NAME)

    changed = sorted(n for n in meta["files"] if nc.sha256(OUT / n) != meta["files"][n])
    meta["status"] = f"NES_BOOT_ROM_ON_{BASE.name.upper()}_PREPARED_NATIVE_VALIDATION_NOT_RUN"
    meta["parent_hardware"] = str(BASE)
    meta["ROM"] = str(OUT / ROM_NAME)
    meta["ROM_sha256"] = nc.sha256(OUT / ROM_NAME)
    meta["files"] = {n: nc.sha256(OUT / n) for n in meta["files"]}
    meta["files"][ROM_NAME] = meta["ROM_sha256"]
    meta["prepare_script"] = str(Path(__file__))
    meta["prepare_script_sha256"] = nc.sha256(Path(__file__))
    meta["r63_nes"] = {
        "change": "resident loader whitelists game ID 0x4e455331 (NES, loader ABI 3, touch)",
        "boot_rom_build": str(BOOT_RESULT), "boot_rom_patches": boot["patches"],
        "loader_bytes": boot["loader_bytes"], "loader_bytes_r62": boot["loader_bytes_original"],
        "r62_files_changed": changed,
        "clocks_unchanged": {"CPU_MHz": meta["CPU_MHz"], "GPU_MHz": meta["GPU_MHz"],
                             "AI_MHz": meta["AI_MHz"], "HDMI_pixel_MHz": meta.get("HDMI_pixel_MHz"),
                             "HDMI_serial_MHz": meta.get("HDMI_serial_MHz")},
    }
    (OUT / "ASSEMBLY.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(json.dumps({"out": str(OUT), "changed": changed, "ROM_sha256": meta["ROM_sha256"]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
