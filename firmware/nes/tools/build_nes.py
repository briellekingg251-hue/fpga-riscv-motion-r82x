"""Build the RV32 NES package for the fusion SD loader (ABI 3, GAMES/NES).

Outputs (build/rv32/): nes.elf, nes.bin, nes.map, disassembly, RESULT.json, and
the SD package in build/sdcard/GAMES/NES (GAME.BIN, MANIFEST.BIN, plus the
.NES files from --roms when given; those are local test copies only).

usage: python -I tools/build_nes.py [--roms roms] [--opt O2]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc

OUT = nc.ROOT / "build/rv32"
PACKAGE = nc.ROOT / "build/sdcard/GAMES/NES"
CPU_HZ = 162000000
LOAD_ADDR = 0x80100000
GAME_ID = 0x4E455331          # "NES1"
MANIFEST_MAGIC = 0x53444731   # "SDG1"
LOADER_ABI = 3
ARCH = ["-march=rv32i_zmmul_zicsr", "-mabi=ilp32", "-mno-relax", "-msmall-data-limit=0",
        "-mstrict-align"]
SUPPORTED = set("lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw "
                "addi slti sltiu xori ori andi slli srli srai add sub sll slt sltu xor srl sra or and "
                "mul mulh mulhsu mulhu fence fence.i ecall ebreak csrrw csrrs csrrc csrrwi csrrsi "
                "csrrci mret unimp".split())
PORT_UNITS = ["nes_main.c", "nes_system.c", "nes_board.c", "nes_video.c", "nes_frame.c",
              "nes_pad.c", "nes_rom.c", "nes_menu.c", "nes_mapper.c", "nes_trap.c", "nes_crt0.S"]
BOARD_UNITS = ["fat32.c", "sd_spi.c", "gpu.c", "uart.c", "jump.S"]


def compile_unit(unit: tuple[Path, list[str], str]) -> Path:
    src, flags, name = unit
    obj = OUT / "obj" / (name + ".o")
    nc.run([nc.GCC, *flags, "-c", src, "-o", obj], OUT / "obj" / (name + ".log"))
    return obj


def check_isa(elf: Path) -> list[str]:
    """Decode without aliases so DIV, FPU, atomic or compressed opcodes cannot hide."""
    disasm = nc.run([nc.OBJDUMP, "-d", "-M", "no-aliases", "--no-show-raw-insn", elf])
    (OUT / "disassembly.txt").write_text(disasm, encoding="utf-8")
    # jump.S emits FENCE.I as a raw word (the frozen loader toolchain contract).
    disasm = re.sub(r"(^\s*[0-9a-f]+:\s+)\.word\s+0x0000100f\s*$", r"\1fence.i", disasm, flags=re.M)
    opcodes = set(re.findall(r"^\s*[0-9a-f]+:\s+(\S+)", disasm, re.M))
    forbidden = sorted(opcodes - SUPPORTED)
    if forbidden:
        raise RuntimeError(f"unsupported instructions: {forbidden}")
    return sorted(opcodes)


def symbols(elf: Path) -> dict[str, int]:
    table = {}
    for line in nc.run([nc.NM, elf]).splitlines():
        parts = line.split()
        if len(parts) == 3 and re.fullmatch(r"[0-9a-f]+", parts[0]):
            table[parts[2]] = int(parts[0], 16)
    return table


def package(binary: bytes, roms: Path | None) -> dict[str, str]:
    if PACKAGE.exists():
        shutil.rmtree(PACKAGE)
    PACKAGE.mkdir(parents=True)
    header = struct.pack("<7I", MANIFEST_MAGIC, LOADER_ABI, len(binary), zlib.crc32(binary),
                         LOAD_ADDR, LOAD_ADDR, GAME_ID)
    (PACKAGE / "GAME.BIN").write_bytes(binary)
    (PACKAGE / "MANIFEST.BIN").write_bytes(header + struct.pack("<I", zlib.crc32(header)))
    if roms:
        for rom in sorted(roms.glob("*.NES")):
            if len(rom.stem) > 8 or not re.fullmatch(r"[A-Z0-9_]+", rom.stem):
                raise RuntimeError(f"{rom.name}: not an upper-case 8.3 name")
            shutil.copyfile(rom, PACKAGE / rom.name)
    return {p.name: nc.sha256(p) for p in sorted(PACKAGE.iterdir())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--roms", type=Path, default=None)
    parser.add_argument("--opt", default="O2", choices=["O2", "O3", "Os"])
    args = parser.parse_args()
    for directory in (OUT, OUT / "obj"):
        directory.mkdir(parents=True, exist_ok=True)
    status_path = OUT / "RESULT.json"
    status_path.write_text(json.dumps({"status": "BUILDING"}), encoding="utf-8")
    try:
        stage = OUT / "stage"
        core_hashes = nc.stage_infones(stage)
        common = [*ARCH, f"-{args.opt}", "-g", "-ffunction-sections", "-fdata-sections",
                  "-fno-strict-aliasing", "-fno-common", f"-DCPU_CLOCK_HZ={CPU_HZ}u"]
        includes = [f"-I{stage}", f"-I{nc.PORT}", f"-I{nc.BOARD}"]
        core_flags = [*common, *nc.CXX_FLAGS, "-w", f"-I{stage}"]
        port_flags = [*common, "-std=gnu99", "-Wall", "-Wextra", "-Werror", *includes]
        board_flags = [*common, "-Wall", "-Wextra", f"-I{nc.BOARD}"]
        units = [(stage / f"{u}.cpp", core_flags, "core_" + u) for u in nc.CORE_UNITS]
        units += [(nc.PORT / u, port_flags, "port_" + Path(u).stem) for u in PORT_UNITS]
        units += [(nc.BOARD / u, board_flags, "board_" + Path(u).stem) for u in BOARD_UNITS]
        # Gate: no sequence-point undefined behaviour left in the patched core.
        for u in nc.CORE_UNITS:
            nc.run([nc.GCC, *core_flags, "-fsyntax-only", "-Wsequence-point",
                    "-Werror=sequence-point", stage / f"{u}.cpp"])
        with ThreadPoolExecutor(max_workers=8) as pool:
            objects = list(pool.map(compile_unit, units))
        elf = OUT / "nes.elf"
        nc.run([nc.GCC, *ARCH, "-nostartfiles", "-T", nc.PORT / "nes_link.ld", "-Wl,--gc-sections",
                "-Wl,--no-warn-rwx-segments", f"-Wl,-Map={OUT / 'nes.map'}", "-o", elf,
                *objects, "-lc", "-lgcc"], OUT / "link.log")
        binary_path = OUT / "nes.bin"
        nc.run([nc.OBJCOPY, "-O", "binary", elf, binary_path])
        opcodes = check_isa(elf)
        sym = symbols(elf)
        if sym["_start"] != LOAD_ADDR:
            raise RuntimeError("entry is not the load address")
        if sym["__stack_top"] != 0x83F00000:
            raise RuntimeError("stack top moved into the GPU framebuffer area")
        for name in ("ChrBuf", "WorkFrame", "rom_image"):
            if sym[name] % 4:
                raise RuntimeError(f"{name} is not word aligned (DWORD casts in the core)")
        binary = binary_path.read_bytes()
        sizes = nc.run([nc.SIZE, elf]).splitlines()[-1].split()
        pkg = package(binary, args.roms)
        result = {
            "status": "NES_RV32_BUILD_PASS", "cpu_hz": CPU_HZ, "isa": "rv32i_zmmul_zicsr",
            "loader_abi": LOADER_ABI, "game_id": hex(GAME_ID), "entry": hex(LOAD_ADDR),
            "opt": args.opt, "text": int(sizes[0]), "data": int(sizes[1]), "bss": int(sizes[2]),
            "binary_bytes": len(binary), "bss_end": hex(sym["__bss_end"]),
            "opcodes": opcodes, "forbidden_opcodes": [],
            "patches": [{"file": f, "reason": r} for f, _o, _n, r in nc.PATCHES],
            "compiler": {"path": str(nc.GCC), "sha256": nc.sha256(nc.GCC),
                         "version": nc.run([nc.GCC, "--version"]).splitlines()[0]},
            "flags": {"core": core_flags, "port": port_flags, "board": board_flags, "link": ARCH},
            "source_sha256": {**core_hashes,
                              **{str(p.relative_to(nc.ROOT)): nc.sha256(p) for p in
                                 sorted(nc.PORT.iterdir()) if p.is_file()},
                              **{f"board_fw/{u}": nc.sha256(nc.BOARD / u) for u in BOARD_UNITS},
                              str(Path(__file__).relative_to(nc.ROOT)): nc.sha256(Path(__file__))},
            "output_sha256": {p.name: nc.sha256(p) for p in (elf, binary_path)},
            "package_sha256": pkg, "board": "NOT_RUN",
        }
        status_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps({k: result[k] for k in ("status", "text", "data", "bss", "binary_bytes",
                                                  "bss_end")}, indent=1))
        return 0
    except Exception as exc:
        status_path.write_text(json.dumps({"status": "FAIL", "error": str(exc)}, indent=2), encoding="utf-8")
        raise


if __name__ == "__main__":
    sys.exit(main())
