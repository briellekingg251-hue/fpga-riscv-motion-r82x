"""Build resident loader, RAM-linked game, and copyable FAT32 game directory.

Does not access or format any disk. SAVE.DAT is created once, never overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import re
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_fw as compiler


def build(name, sources, linker):
    (ROOT / "build").mkdir(exist_ok=True)
    elf = ROOT / "build" / (name + ".elf")
    game_flags=["-DFN_GPU_POSE_YIELD=1","-DFN_DUAL_POSE_PIP=1"] if name in ("fruit","subway") else []
    if name in ("fruit","subway") and __import__("os").environ.get("FN_POSE_DEBUG")=="1": game_flags.append("-DFN_POSE_DEBUG=1")
    compiler.run([compiler.GCC, *compiler.CFLAGS, "-Werror", "-DFN_POSE_PRODUCTION=1", "-DFN_SUBWAY_TILE_ROWS=8", *game_flags, "-nostdlib", "-nostartfiles",
                  "-T", ROOT / "fw" / linker, "-Wl,--gc-sections", "-Wl,--no-warn-rwx-segments",
                  f"-Wl,-Map={elf.with_suffix('.map')}", "-o", elf,
                  *[ROOT / "fw" / s for s in sources], "-lgcc"])
    binary = elf.with_suffix(".bin")
    compiler.run([compiler.OBJCOPY, "-O", "binary", elf, binary])
    print(compiler.run([compiler.SIZE, elf]).strip())
    return binary.read_bytes()


def package(name, game, sprites, palette, game_id, resource_abi):
    if not 0 < len(game) <= 0x17c00 - 8192:
        raise SystemExit(f"{name} RAM image exceeds ABI limits")
    expected_sprites = {1: 73728, 2: 262144}[resource_abi]
    if len(sprites) != expected_sprites or len(palette) != 768:
        raise SystemExit(f"{name} resources do not match ABI {resource_abi}")
    directory = ROOT / "sdcard" / "GAMES" / name
    directory.mkdir(parents=True, exist_ok=True)
    header = struct.pack("<7I", 0x53444731, resource_abi, len(game), zlib.crc32(game),
                         zlib.crc32(sprites), zlib.crc32(palette), game_id)
    for filename, contents in {"GAME.BIN": game, "SPRITES.BIN": sprites, "PALETTE.BIN": palette,
                               "MANIFEST.BIN": header + struct.pack("<I", zlib.crc32(header))}.items():
        (directory / filename).write_bytes(contents)
    save = directory / "SAVE.DAT"
    if not save.exists():
        save.write_bytes(bytes(1024))
    elif save.stat().st_size != 1024:
        raise SystemExit("Existing SAVE.DAT has wrong size; retained unchanged")
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(directory.iterdir())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games-only", action="store_true",
                        help="build SD games without changing the resident image or packed RTL")
    args = parser.parse_args()
    if not args.games_only:
        boot = build("boot", ["start.S", "jump.S", "boot.c", "cardlink.c", "uartlink.c", "gpu.c", "uart.c", "fat32.c", "sd_spi.c"], "boot_link.ld")
        if len(boot) > 24576:
            raise SystemExit("Resident RAM image exceeds ABI limits")
        image = bytearray(128 * 1024)
        image[0x18000:0x18000+len(boot)] = boot
        (ROOT / "build" / "program.hex").write_text(
            "".join(f"{int.from_bytes(image[i:i+4], 'little'):08x}\n" for i in range(0, len(image), 4)), encoding="ascii")
    common = ["pose_ui.c", "game_pose_service.c", "pose_service.c", "pose_mmio_source.c", "p2_algo.c", "pose_input.c", "game_runtime.c", "start.S", "jump.S", "gpu.c", "uart.c", "game_record.c", "fat32.c", "sd_spi.c"]
    fruit = build("fruit", ["main.c", "pose_blade_visual.c", *common], "game_link.ld")
    subway = build("subway", ["subway_main.c", "subway.c", "subway_draw.c", *common], "game_link.ld")
    # Snapshot ships the combined 32-slot ROM, including slot zero.
    combined = ROOT / "build" / "sprites.hex"
    if combined.exists():
        sprites = bytes(int(v,16) for v in combined.read_text().split())[4096:19*4096]
    else:
        sprites = bytes(int(v,16) for i in range(1,19)
                        for v in (ROOT / "build" / "spr" / f"spr_{i:02d}.hex").read_text().split())
    palette = b"".join(int(v, 16).to_bytes(3, "big") for v in (ROOT / "build" / "palette.hex").read_text().split())
    hashes = package("FRUIT", fruit, sprites, palette, 0x46525549, 1)
    subway_sprites = bytes(int(v, 16) for v in (ROOT / "assets" / "subway" / "sprites.hex").read_text().split())
    table = (ROOT / "fw" / "subway_assets.h").read_text().split("static const uint32_t sw_palette[240] = {", 1)[1].split("};", 1)[0]
    colors = [int(v, 16) for v in re.findall(r"0x[0-9A-Fa-f]{6}", table)]
    if len(colors) != 240:
        raise SystemExit("Subway palette table must have exactly 240 entries")
    subway_palette = palette[:48] + b"".join(v.to_bytes(3, "big") for v in colors)
    hashes.update(package("SUBWAY", subway, subway_sprites, subway_palette, 0x53554257, 2))
    modecaps = {"contract_version": 1, "inference_integrated": True, "continuity_gate_integrated": True,
                "pose_actions_connected": True, "firmware_pose_runnable": True,
                "system_pose_runnable": False, "validation": "production action chain with observable single-player continuity; CPU budget/30fps/board acceptance pending",
                "games": {name: {"modes": ["TOUCH", "POSE"], "shared_game_bin": True,
                                  "pose_adapter": True, "resource_abi": abi}
                          for name, abi in (("FRUIT", 1), ("SUBWAY", 2))}}
    modecaps["games"]["PAL"]={"modes":["TOUCH"],"shared_game_bin":True,"pose_adapter":False,"resource_abi":3}
    (ROOT / "build" / "modecap.json").write_text(json.dumps(modecaps, indent=2), encoding="utf-8")
    sidecar = ROOT / "sdcard" / "MODECAP.JSON"
    sidecar.write_text(json.dumps(modecaps, indent=2), encoding="utf-8")
    hashes[str(sidecar.relative_to(ROOT))] = hashlib.sha256(sidecar.read_bytes()).hexdigest()
    (ROOT / "build" / "package_manifest.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    print("FRUIT ABI 1 and SUBWAY GPU v2 ABI 2 packaged. Existing SAVE.DAT retained.")


if __name__ == "__main__":
    main()
