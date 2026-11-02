"""Cycle-accurate NES cost on the O2 RTL (Verilator model of ooo/rtl).

Builds tests/o2_bench.c with the same staged InfoNES core, compiler and flags
as the board package, embeds a cartridge, and runs it on the O2 testbench
(4 MiB RAM fixture, cosim off) under several memory-stall settings: 0 % (fast
SRAM behind the caches) and heavier settings that stretch every burst
handshake, standing in for DDR3 latency.  Reports cycles per rendered frame
against the 162 MHz / 60 Hz budget of 2,700,000 cycles.

The simulator must be built first (see README):
  OBJ=<repo>/build/o2sim/obj bash <cpu repo>/ooo/sim/build.sh -DTB_RAM_BYTES=4194304

usage: python -I tools/run_o2_bench.py [--rom roms/MARIO.NES] [--frames 360] [--stall 0 50 80]
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc
from build_nes import ARCH

OUT = nc.ROOT / "build/o2bench"
SIM = nc.ROOT / "build/o2sim/obj/Vo2_tb.exe"
RAM_BYTES = 4 * 1024 * 1024
RAM_BASE = 0x80000000
FRAME_BUDGET = 162_000_000 // 60
LINK = """OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = %d }
SECTIONS {
 .text : ALIGN(64) { KEEP(*(.text.start)) *(.text .text.*) } > RAM
 .rodata : ALIGN(64) { *(.rodata .rodata.*) *(.srodata .srodata.*) } > RAM
 .data : ALIGN(64) { *(.data .data.*) *(.sdata .sdata.*) } > RAM
 .bss (NOLOAD) : ALIGN(64) { __bss_start = .; *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) . = ALIGN(64); __bss_end = .; } > RAM
 __stack_top = ORIGIN(RAM) + LENGTH(RAM);
 __global_pointer$ = 0;
 ASSERT(__bss_end <= __stack_top - 0x10000, "bench image too large")
 /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.init_array*) *(.fini_array*) }
}
""" % RAM_BYTES
START = """    .section .text.start, "ax", @progbits
    .globl _start
_start:
    la sp, __stack_top
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call main
3:  j 3b
"""


def build(out: Path, rom: Path, frames: int, opt: str) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    stage = out / "stage"
    nc.stage_infones(stage)
    image = rom.read_bytes()
    body = ",".join(str(b) for b in image)
    (out / "bench_rom.c").write_text(
        "#include <stdint.h>\n"
        f"const uint8_t bench_rom[{len(image)}] __attribute__((aligned(64))) = {{{body}}};\n"
        f"const uint32_t bench_rom_size = {len(image)}u;\n", encoding="ascii")
    (out / "link.ld").write_text(LINK, encoding="ascii")
    (out / "start.S").write_text(START, encoding="ascii")
    common = [*ARCH, f"-{opt}", "-g", "-ffunction-sections", "-fdata-sections", "-fno-strict-aliasing",
              "-fno-common", f"-DBENCH_FRAMES={frames}u"]
    units = [(stage / f"{u}.cpp", [*common, *nc.CXX_FLAGS, "-w", f"-I{stage}"]) for u in nc.CORE_UNITS]
    port = [*common, "-std=gnu99", "-Wall", "-Wextra", "-Werror", f"-I{stage}", f"-I{nc.PORT}"]
    units += [(nc.ROOT / "tests/o2_bench.c", port), (nc.PORT / "nes_frame.c", port),
              (nc.PORT / "nes_rom.c", port), (nc.PORT / "nes_mapper.c", port),
              (out / "bench_rom.c", port), (out / "start.S", common)]
    objects = []
    for src, flags in units:
        obj = out / (src.stem + ".o")
        nc.run([nc.GCC, *flags, "-c", src, "-o", obj])
        objects.append(obj)
    elf = out / "bench.elf"
    nc.run([nc.GCC, *ARCH, "-nostartfiles", "-T", out / "link.ld", "-Wl,--gc-sections",
            "-Wl,--no-warn-rwx-segments", "-o", elf, *objects, "-lc", "-lgcc"])
    hex_path = out / "bench.hex"
    write_hex(elf, hex_path)
    return hex_path


def write_hex(elf: Path, hex_path: Path) -> None:
    """Full-RAM word-per-line image from the ELF's PT_LOAD segments."""
    raw = elf.read_bytes()
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", raw)
    ram = bytearray(RAM_BYTES)
    for i in range(header[10]):
        kind, off, _va, pa, size, _msz, _fl, _al = struct.unpack_from("<IIIIIIII", raw, header[5] + i * header[9])
        if kind == 1 and size:
            base = pa - RAM_BASE
            ram[base:base + size] = raw[off:off + size]
    hex_path.write_text("".join(f"{int.from_bytes(ram[i:i + 4], 'little'):08x}\n"
                                for i in range(0, RAM_BYTES, 4)), encoding="ascii")


def run(hex_path: Path, stall: int, limit: int) -> dict:
    run_dir = hex_path.parent / f"stall{stall}"
    run_dir.mkdir(exist_ok=True)
    start = time.perf_counter()
    text = nc.run([SIM, f"+INIT_HEX={hex_path}", "+NOCOSIM", f"+STALL={stall}", "+SEED=7",
                   f"+LIMIT={limit}"], run_dir / "sim.log", nc.host_env(), cwd=run_dir)
    uart = (run_dir / "uart.txt").read_text(errors="replace") if (run_dir / "uart.txt").exists() else ""
    match = re.search(r"NES_BENCH frames=(\d+) avg=(\d+) min=(\d+) max=(\d+) texels_avg=(\d+) texels_max=(\d+)",
                      uart + text)
    exit_ok = re.search(r"O2_EXIT code=0 ", text) is not None
    if not match:
        return {"stall": stall, "error": "no NES_BENCH line", "exit_ok": exit_ok}
    frames, avg, low, high, tavg, tmax = map(int, match.groups())
    return {"stall": stall, "exit_ok": exit_ok, "frames": frames, "avg_cycles": avg, "min_cycles": low,
            "max_cycles": high, "texels_avg": tavg, "texels_max": tmax,
            "avg_budget_pct": round(100 * avg / FRAME_BUDGET, 1),
            "max_budget_pct": round(100 * high / FRAME_BUDGET, 1),
            "fps_if_unpaced": round(162e6 / avg, 1), "wall_seconds": round(time.perf_counter() - start, 1),
            "histogram": re.search(r"NES_HIST (.*)", uart + text).group(1).strip()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rom", type=Path, default=nc.ROOT / "roms/MARIO.NES")
    parser.add_argument("--frames", type=int, default=360)
    parser.add_argument("--stall", type=int, nargs="+", default=[0, 50, 80])
    parser.add_argument("--opt", default="O2")
    args = parser.parse_args()
    if not SIM.exists():
        raise SystemExit(f"simulator missing: {SIM}")
    out = OUT / args.rom.stem
    hex_path = build(out, args.rom, args.frames, args.opt)
    limit = args.frames * 40 * FRAME_BUDGET
    with ThreadPoolExecutor(max_workers=len(args.stall)) as pool:
        results = list(pool.map(lambda s: run(hex_path, s, limit), args.stall))
    report = {"rom": args.rom.name, "rom_sha256": nc.sha256(args.rom), "opt": args.opt,
              "frame_budget_cycles": FRAME_BUDGET, "sim_sha256": nc.sha256(SIM),
              "bench_hex_sha256": nc.sha256(hex_path), "results": results,
              "scope": "O2 RTL (Verilator), caches + burst bus with stall injection; "
                       "GPIO stores stand in for GPU FIFO stores; no DDR PHY"}
    (out / "RESULT.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    for r in results:
        print(r)
    return 0 if all(r.get("exit_ok") for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
