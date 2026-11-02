"""Build and package the complete RV32 Doom engine; all outputs stay in this workspace."""
from __future__ import annotations

import hashlib
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_fw as cc

OUT = ROOT / "build/doom"
PORT = ROOT / "fw/doom"
ENGINE = ROOT / "third_party/doomgeneric/doomgeneric"
PACKAGE = ROOT / "sdcard/GAMES/DOOM"
ARCH = ["-march=rv32i_zmmul_zicsr", "-mabi=ilp32", "-mno-relax", "-msmall-data-limit=0", "-mstrict-align"]
COMMON = [*ARCH, "-O2", "-g", "-ffunction-sections", "-fdata-sections", "-fno-strict-aliasing",
          "-fno-common", "-DCMAP256", "-DDOOMGENERIC_RESX=320", "-DDOOMGENERIC_RESY=200", "-DFPGA_DOOM",
          "-D_DEFAULT_SOURCE", "-I" + str(ENGINE)]
SUPPORTED = set("lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw "
                "addi slti sltiu xori ori andi slli srli srai add sub sll slt sltu xor srl sra or and "
                "mul mulh mulhsu mulhu fence fence.i ecall ebreak csrrw csrrs csrrc csrrwi csrrsi "
                "csrrci mret unimp".split())


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args: list, log: Path | None = None) -> str:
    env = os.environ.copy()
    env["TMP"] = env["TEMP"] = str(OUT / "tmp")
    res = subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env)
    if log:
        log.write_text(res.stdout + res.stderr, encoding="utf-8")
    if res.returncode:
        raise RuntimeError(f"{args[0]} failed ({res.returncode}):\n{res.stdout}{res.stderr}")
    return res.stdout


def compile_unit(unit: tuple[Path, list[str], str]) -> Path:
    src, flags, name = unit
    obj = OUT / "obj" / (name + ".o")
    run([cc.GCC, *flags, "-c", src, "-o", obj], OUT / "obj" / (name + ".log"))
    return obj


def check_isa(elf: Path) -> list[str]:
    """Decode without aliases so compressed, FPU, DIV and atomic opcodes cannot hide."""
    disasm = run([cc.TOOLBIN / "riscv-none-elf-objdump.exe", "-d", "-M", "no-aliases",
                  "--no-show-raw-insn", elf])
    (OUT / (elf.stem + "_disassembly.txt")).write_text(disasm, encoding="utf-8")
    # jump.S emits the architectural FENCE.I word directly because the frozen
    # compile contract predates GCC's separate Zifencei extension spelling.
    disasm = re.sub(r"(^\s*[0-9a-f]+:\s+)\.word\s+0x0000100f\s*$", r"\1fence.i", disasm, flags=re.M)
    opcodes = set(re.findall(r"^\s*[0-9a-f]+:\s+(\S+)", disasm, re.M))
    forbidden = sorted(opcodes - SUPPORTED)
    if forbidden:
        raise RuntimeError(f"Unsupported ISA instructions in {elf.name}: {forbidden}")
    return sorted(opcodes)


def main() -> None:
    global OUT, PACKAGE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpu-hz", type=int, choices=[157500000], default=157500000)
    args = parser.parse_args()
    OUT = ROOT / "build/doom1575"
    clock_flag = f"-DCPU_CLOCK_HZ={args.cpu_hz}u"
    for directory in (OUT, OUT / "obj", OUT / "tmp", PACKAGE):
        directory.mkdir(parents=True, exist_ok=True)
    status_path = OUT / "status.json"
    status_path.write_text(json.dumps({"status": "BUILDING"}), encoding="utf-8")
    try:
        names = re.search(r"^SRC_DOOM = (.+)$", (ENGINE / "Makefile").read_text(), re.M)
        if names is None:
            raise RuntimeError("Upstream source list missing")
        flags = [*COMMON, clock_flag, "-std=gnu99", "-w"]
        units = [(ENGINE / (name[:-2] + ".c"), flags, "engine_" + name[:-2])
                 for name in names[1].split() if name != "doomgeneric_xlib.o"]
        port_flags = [*COMMON, clock_flag, "-std=gnu99", "-Wall", "-Wextra", "-Werror"]
        units.extend((p, port_flags, "port_" + p.stem) for p in sorted(PORT.glob("*.[cS]")))
        units.extend((ROOT / "fw" / p, [*COMMON, clock_flag, "-Wall", "-Wextra"], "fw_" + Path(p).stem)
                     for p in ["fat32.c", "sd_spi.c", "gpu.c", "uart.c", "pal/port/pal_fs.c"])
        with ThreadPoolExecutor(max_workers=8) as pool:
            objects = list(pool.map(compile_unit, units))
        elf = OUT / "doom.elf"
        run([cc.GCC, *ARCH, "-nostartfiles", "-T", PORT / "doom_link.ld", "-Wl,--gc-sections",
             "-Wl,--no-warn-rwx-segments", f"-Wl,-Map={OUT / 'doom.map'}", "-o", elf,
             *objects, "-lc", "-lm", "-lgcc"], OUT / "link.log")
        binary = OUT / "doom.bin"
        run([cc.OBJCOPY, "-O", "binary", elf, binary])
        engine_opcodes = check_isa(elf)
        symbols = {line.split()[2]: int(line.split()[0], 16)
                   for line in run([cc.TOOLBIN / "riscv-none-elf-nm.exe", elf]).splitlines()
                   if len(line.split()) == 3 and re.fullmatch(r"[0-9a-f]+", line.split()[0])}
        if symbols["_start"] != 0x80100000:
            raise RuntimeError("Wrong DDR entry")
        if symbols["__stack_top"] != 0x83f00000 or symbols["__heap_end"] != 0x83e00000:
            raise RuntimeError("Doom memory exceeds fusion CPU DDR window")
        boot = OUT / "boot.elf"
        run([cc.GCC, *cc.CFLAGS, clock_flag, "-Werror", "-nostdlib", "-nostartfiles", "-T", ROOT / "fw/boot_link.ld",
             "-Wl,--gc-sections", "-Wl,--no-warn-rwx-segments", f"-Wl,-Map={OUT / 'boot.map'}", "-o", boot,
             *[ROOT / "fw" / p for p in ["start.S", "jump.S", "boot.c", "cardlink.c", "uartlink.c",
                                         "gpu.c", "uart.c", "fat32.c", "sd_spi.c", "game_runtime.c"]], "-lgcc"], OUT / "boot.log")
        run([cc.OBJCOPY, "-O", "binary", boot, OUT / "boot.bin"])
        boot_opcodes = check_isa(boot)
        boot_bytes = (OUT / "boot.bin").read_bytes()
        if len(boot_bytes) > 24576:
            raise RuntimeError("Resident loader exceeds BRAM window")
        image = bytearray(128 * 1024)
        image[0x18000:0x18000 + len(boot_bytes)] = boot_bytes
        (OUT / "program.hex").write_text("".join(f"{int.from_bytes(image[i:i+4], 'little'):08x}\n"
                                                for i in range(0, len(image), 4)), encoding="ascii")
        game = binary.read_bytes()
        header = struct.pack("<7I", 0x53444731, 3, len(game), zlib.crc32(game), 0x80100000, 0x80100000, 0x444f4f4d)
        (PACKAGE / "GAME.BIN").write_bytes(game)
        (PACKAGE / "MANIFEST.BIN").write_bytes(header + struct.pack("<I", zlib.crc32(header)))
        wad = ROOT / "third_party/PureDOOM/doom1.wad"
        shutil.copyfile(wad, PACKAGE / "DOOM1.WAD")
        magic, lumps, directory = struct.unpack_from("<4sII", wad.read_bytes())
        if magic != b"IWAD" or directory + lumps * 16 > wad.stat().st_size:
            raise RuntimeError("Invalid shareware IWAD")
        from sd_volume import check_package
        check_package(PACKAGE)
        sizes = run([cc.SIZE, elf]).splitlines()[-1].split()
        status = {"status": "DOOM_RV32_BUILD_PASS", "engine": "DoomGeneric", "isa": "rv32i_zmmul_zicsr",
                  "abi": "ilp32", "clock_hz": args.cpu_hz, "loader_abi": 3, "entry": "0x80100000",
                  "text": int(sizes[0]), "data": int(sizes[1]), "bss": int(sizes[2]),
                  "heap_bytes": symbols["__heap_end"] - symbols["__heap_start"],
                  "stack_top": hex(symbols["__stack_top"]), "heap_end": hex(symbols["__heap_end"]),
                  "cpu_ddr_end_exclusive": "0x83f00000", "gpu_reserved": "0x83f00000..0x83ffffff",
                  "binary_bytes": len(game), "loader_bytes": len(boot_bytes), "forbidden_opcodes": [],
                  "opcodes": {"doom": engine_opcodes, "boot": boot_opcodes},
                  "compiler": {"path": str(cc.GCC), "sha256": digest(cc.GCC),
                               "version": run([cc.GCC, "--version"]).splitlines()[0]},
                  "compile_flags": {str(p.relative_to(ROOT)): f for p, f, _ in units},
                  "loader_flags": [*cc.CFLAGS, clock_flag], "link_arch": ARCH,
                  "source_sha256": {str(p.relative_to(ROOT)): digest(p)
                                    for p in sorted(set([p for p, _, _ in units] +
                                        [p for p in (ROOT / 'fw').rglob('*') if p.is_file() and p.suffix in
                                         ('.h', '.c', '.S', '.ld')] + list(ENGINE.glob('*.h')) +
                                        [ENGINE / 'Makefile', Path(__file__)]))},
                  "output_sha256": {p.name: digest(p) for p in
                                    [elf, binary, boot, OUT / 'boot.bin', OUT / 'program.hex']},
                  "package_sha256": {p.name: digest(p) for p in PACKAGE.iterdir()},
                  "board": "NOT_RUN", "native_cpu_rtl": "NOT_RUN"}
        status_path.write_text(json.dumps(status, indent=2), encoding="utf-8")
        print(json.dumps({k: v for k, v in status.items() if not k.endswith("sha256")}, indent=2))
    except Exception as exc:
        status_path.write_text(json.dumps({"status": "FAIL", "error": str(exc)}, indent=2), encoding="utf-8")
        raise


if __name__ == "__main__":
    main()
