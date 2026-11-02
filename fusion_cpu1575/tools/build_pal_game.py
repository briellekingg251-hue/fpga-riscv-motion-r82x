"""Build the complete PAL-Navy game for the board CPU and package GAMES/PAL.

The whole SDLPAL engine (DOS 1995 data, classic battle) is compiled for
rv32i_zmmul_zicsr/ilp32 and linked with newlib, the board platform layer in
fw/pal/port (DDR3 image, SD resources, GPU presenter, touch input, A/B saves).
The resident loader with loader ABI 3 is built into build/pal_game/program.hex.

Outputs:
  build/pal_game/pal.elf / pal.bin / pal.map, status.json
  build/pal_game/program.hex       resident loader (block RAM image)
  sdcard/GAMES/PAL/                MANIFEST.BIN GAME.BIN, 21 DOS resources,
                                   SAVE1A.DAT .. SAVE5B.DAT (created once,
                                   never overwritten: they hold player saves)
"""
from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_fw as cc  # noqa: E402

OUT = ROOT / "build" / "pal_game"
ENGINE = ROOT / "third_party" / "pal-navy"
NAVY = ROOT / "third_party" / "navy-apps"
PORT = ROOT / "fw" / "pal" / "port"
DATA = ROOT / "game_data" / "PAL_DOS"
PACKAGE = ROOT / "sdcard" / "GAMES" / "PAL"
LOAD_ADDRESS = 0x80100000
GAME_ID = 0x50414C31
SAVE_SLOTS = 5
SAVE_FILE_BYTES = 512 + 256 * 1024
OBJDUMP = cc.TOOLBIN / "riscv-none-elf-objdump.exe"

ARCH = ["-march=rv32i_zmmul_zicsr", "-mabi=ilp32", "-mno-relax", "-msmall-data-limit=0", "-mstrict-align"]
COMMON = [*ARCH, "-O2", "-g", "-ffunction-sections", "-fdata-sections", "-fno-strict-aliasing",
          "-fno-common", "-D__NAVY__", "-DPAL_CLASSIC=1", "-DPAL_FPGA_RV32=1",
          "-I" + str(NAVY / "libs/libminiSDL/include"), "-I" + str(NAVY / "libs/libfixedptc/include")]
ENGINE_FLAGS = [*COMMON, "-std=gnu99", "-D_GNU_SOURCE", "-w", "-I" + str(ENGINE / "include")]
PORT_FLAGS = [*COMMON, "-std=gnu99", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter"]
FW_FLAGS = [*COMMON, "-std=gnu99", "-Wall", "-Wextra", "-ffreestanding"]
DATA_FILES = ["ABC.MKF", "BALL.MKF", "DATA.MKF", "F.MKF", "FANTI.FON", "FBP.MKF", "FIRE.MKF", "GOP.MKF",
              "M.MSG", "MAP.MKF", "MGO.MKF", "MIDI.MKF", "MUS.MKF", "PAT.MKF", "RGM.MKF", "RNG.MKF",
              "SSS.MKF", "VOC.MKF", "WOR16.ASC", "WOR16.FON", "WORD.DAT"]


def sources():
    units = []
    for src in sorted((ENGINE / "src").rglob("*.c")):
        if "sound" in src.parts:
            continue
        units.append((src, ENGINE_FLAGS, "pal_" + "_".join(src.relative_to(ENGINE / "src").with_suffix("").parts)))
    units.append((NAVY / "libs/libfixedptc/fixedptc.c", ENGINE_FLAGS, "navy_fixedptc"))
    for src in sorted(PORT.glob("*.[cS]")):
        units.append((src, PORT_FLAGS, "port_" + src.stem))
    for name in ["pal_sdl_event.c", "pal_sdl_timer.c", "pal_touch.c", "pal_sd.c"]:
        units.append((ROOT / "fw/pal" / name, PORT_FLAGS, "backend_" + Path(name).stem))
    for name in ["fat32.c", "sd_spi.c", "uart.c", "gpu.c"]:
        units.append((ROOT / "fw" / name, FW_FLAGS, "fw_" + Path(name).stem))
    return units


def compile_unit(unit):
    src, flags, name = unit
    obj = OUT / "obj" / (name + ".o")
    res = subprocess.run([str(cc.GCC), *flags, "-c", str(src), "-o", str(obj)], capture_output=True, text=True)
    return name, obj, res.returncode, res.stdout + res.stderr


def build_engine():
    (OUT / "obj").mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(compile_unit, sources()))
    failed = [r for r in results if r[2]]
    for name, _, _, log in results:
        if log.strip():
            (OUT / "obj" / (name + ".log")).write_text(log, encoding="utf-8")
    if failed:
        for name, _, _, log in failed:
            sys.stderr.write(f"--- {name}\n{log}\n")
        raise SystemExit(f"{len(failed)} PAL compile units failed")
    elf = OUT / "pal.elf"
    link = subprocess.run([str(cc.GCC), *ARCH, "-nostartfiles", "-T", str(PORT / "pal_link.ld"),
                           "-Wl,--gc-sections", "-Wl,--no-warn-rwx-segments", f"-Wl,-Map={OUT / 'pal.map'}",
                           "-o", str(elf), *[str(r[1]) for r in results], "-lc", "-lm", "-lgcc"],
                          capture_output=True, text=True)
    (OUT / "link.log").write_text(link.stdout + link.stderr, encoding="utf-8")
    if link.returncode:
        sys.stderr.write(link.stdout + link.stderr)
        raise SystemExit("PAL link failed")
    binary = OUT / "pal.bin"
    cc.run([cc.OBJCOPY, "-O", "binary", elf, binary])
    sizes = cc.run([cc.SIZE, elf]).splitlines()[-1].split()
    # The s80 core implements Zmmul only: no division instruction may remain.
    disasm = cc.run([OBJDUMP, "-d", "--no-show-raw-insn", elf])
    forbidden = [line for line in disasm.splitlines()
                 if "\t" in line and line.split("\t")[1].split(" ")[0] in ("div", "divu", "rem", "remu")]
    if forbidden:
        raise SystemExit(f"division instructions present: {forbidden[:3]}")
    symbols = {}
    for line in cc.run([cc.TOOLBIN / "riscv-none-elf-nm.exe", elf]).splitlines():
        parts = line.split()
        if len(parts) == 3:
            symbols[parts[2]] = int(parts[0], 16)
    if symbols["_start"] != LOAD_ADDRESS:
        raise SystemExit("_start must be the first byte of the image")
    return binary.read_bytes(), {"text": int(sizes[0]), "data": int(sizes[1]), "bss": int(sizes[2]),
                                 "image_bytes": binary.stat().st_size,
                                 "heap_start": hex(symbols["__heap_start"]), "heap_end": hex(symbols["__heap_end"])}


def build_loader():
    elf = OUT / "boot.elf"
    cc.run([cc.GCC, *cc.CFLAGS, "-Werror", "-nostdlib", "-nostartfiles", "-T", ROOT / "fw/boot_link.ld",
            "-Wl,--gc-sections", "-Wl,--no-warn-rwx-segments", f"-Wl,-Map={OUT / 'boot.map'}", "-o", elf,
            *[ROOT / "fw" / s for s in ["start.S", "jump.S", "boot.c", "cardlink.c", "uartlink.c", "gpu.c", "uart.c", "fat32.c", "sd_spi.c"]],
            "-lgcc"])
    binary = OUT / "boot.bin"
    cc.run([cc.OBJCOPY, "-O", "binary", elf, binary])
    boot = binary.read_bytes()
    if len(boot) > 24576:
        raise SystemExit("resident loader exceeds its 24 KiB block RAM window")
    image = bytearray(128 * 1024)
    image[0x18000:0x18000 + len(boot)] = boot
    (OUT / "program.hex").write_text("".join(f"{int.from_bytes(image[i:i + 4], 'little'):08x}\n"
                                             for i in range(0, len(image), 4)), encoding="ascii")
    return len(boot)


def package(game: bytes):
    PACKAGE.mkdir(parents=True, exist_ok=True)
    header = struct.pack("<7I", 0x53444731, 3, len(game), zlib.crc32(game), LOAD_ADDRESS, LOAD_ADDRESS, GAME_ID)
    (PACKAGE / "GAME.BIN").write_bytes(game)
    (PACKAGE / "MANIFEST.BIN").write_bytes(header + struct.pack("<I", zlib.crc32(header)))
    for name in DATA_FILES:
        src = DATA / name
        dst = PACKAGE / name
        if not dst.exists() or dst.stat().st_size != src.stat().st_size or dst.read_bytes() != src.read_bytes():
            shutil.copyfile(src, dst)
    for slot in range(1, SAVE_SLOTS + 1):
        for side in "AB":
            save = PACKAGE / f"SAVE{slot}{side}.DAT"
            if not save.exists():
                save.write_bytes(bytes(SAVE_FILE_BYTES))
            elif save.stat().st_size != SAVE_FILE_BYTES:
                raise SystemExit(f"{save.name} has an unexpected size; left unchanged")
    stale = {p.name for p in PACKAGE.iterdir()} - set(DATA_FILES) - {"GAME.BIN", "MANIFEST.BIN"} - \
        {f"SAVE{s}{side}.DAT" for s in range(1, SAVE_SLOTS + 1) for side in "AB"}
    if stale:
        raise SystemExit(f"unexpected files in {PACKAGE}: {sorted(stale)}")
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(PACKAGE.iterdir())
            if not p.name.startswith("SAVE")}


def main():
    global OUT
    import argparse
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--test-battle", type=int, metavar="TEAM",
                        help="simulation-only build in build/pal_game_test: AUTO starts a battle; not packaged")
    args = parser.parse_args()
    if args.test_battle is not None:
        OUT = ROOT / "build" / "pal_game_test"
        ENGINE_FLAGS.append(f"-DPAL_FPGA_TEST_BATTLE={args.test_battle}")
        OUT.mkdir(parents=True, exist_ok=True)
        _, sizes = build_engine()
        print("test build", sizes, "-> pal.bin (not packaged)")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    game, sizes = build_engine()
    loader = build_loader()
    hashes = package(game)
    status = {"status": "PAL_GAME_BUILD_PASS", "isa": "rv32i_zmmul_zicsr", "abi": "ilp32",
              "loader_abi": 3, "load_address": hex(LOAD_ADDRESS), "game_id": hex(GAME_ID),
              "elf": sizes, "resident_loader_bytes": loader, "save_slots": SAVE_SLOTS,
              "save_file_bytes": SAVE_FILE_BYTES, "package": hashes}
    (OUT / "status.json").write_text(json.dumps(status, indent=2), encoding="utf-8")
    print(json.dumps({k: status[k] for k in ("status", "elf", "resident_loader_bytes")}, indent=2))


if __name__ == "__main__":
    main()
