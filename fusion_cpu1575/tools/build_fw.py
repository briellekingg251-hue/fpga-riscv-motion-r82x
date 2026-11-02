"""Build the demo firmware into build/<name>.elf and build/<name>.hex.

The .hex has 32768 lines (one little-endian 32-bit word each) = the 128 KiB RAM
image loaded by p2_burst_sram's $readmemh at configuration time.

usage: python tools/build_fw.py [name] [-DMACRO=value ...]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FW = ROOT / "fw"
BUILD = ROOT / "build"
TOOLBIN = Path("F:/Codex_workplace/tools/xpack-riscv-none-elf-gcc-15.2.0-1/"
               "xpack-riscv-none-elf-gcc-15.2.0-1/bin")
GCC = TOOLBIN / "riscv-none-elf-gcc.exe"
OBJCOPY = TOOLBIN / "riscv-none-elf-objcopy.exe"
SIZE = TOOLBIN / "riscv-none-elf-size.exe"
RAM_BYTES = 128 * 1024
STACK_RESERVE = 8 * 1024

CFLAGS = [
    "-march=rv32i_zmmul_zicsr", "-mabi=ilp32", "-mno-relax", "-msmall-data-limit=0",
    "-O2", "-ffreestanding", "-fno-builtin", "-fno-stack-protector",
    "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-g",
]
SOURCES = ["start.S", "main.c", "gpu.c", "uart.c"]


def run(cmd: list[str]) -> str:
    res = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write(res.stdout + res.stderr)
        raise SystemExit(f"command failed: {cmd[0]}")
    if res.stderr.strip():
        sys.stderr.write(res.stderr)
    return res.stdout


def main() -> None:
    args = sys.argv[1:]
    name = args.pop(0) if args and not args[0].startswith("-") else "program"
    defines = [a for a in args if a.startswith("-D")]
    BUILD.mkdir(exist_ok=True)
    elf = BUILD / f"{name}.elf"
    run([GCC, *CFLAGS, *defines, "-nostdlib", "-nostartfiles", "-T", FW / "link.ld",
         "-Wl,--gc-sections", "-Wl,--no-warn-rwx-segments", f"-Wl,-Map={BUILD / (name + '.map')}", "-o", elf,
         *[FW / s for s in SOURCES], "-lgcc"])
    binf = BUILD / f"{name}.bin"
    run([OBJCOPY, "-O", "binary", elf, binf])
    data = binf.read_bytes()
    if len(data) > RAM_BYTES - STACK_RESERVE:
        raise SystemExit(f"image {len(data)} bytes leaves < {STACK_RESERVE} bytes of stack")
    data = data + bytes(RAM_BYTES - len(data))
    with open(BUILD / f"{name}.hex", "w", newline="\n") as f:
        for i in range(0, RAM_BYTES, 4):
            f.write(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n")
    print(run([SIZE, elf]).strip())
    print(f"wrote {BUILD / (name + '.hex')}")


if __name__ == "__main__":
    main()
