"""Shared paths, toolchain and InfoNES staging for the NES port tools."""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INFONES = ROOT / "third_party/InfoNES"
PORT = ROOT / "port"
BOARD = ROOT / "board_fw"
TOOLBIN = Path("F:/Codex_workplace/tools/xpack-riscv-none-elf-gcc-15.2.0-1/"
               "xpack-riscv-none-elf-gcc-15.2.0-1/bin")
GCC = TOOLBIN / "riscv-none-elf-gcc.exe"
OBJCOPY = TOOLBIN / "riscv-none-elf-objcopy.exe"
OBJDUMP = TOOLBIN / "riscv-none-elf-objdump.exe"
NM = TOOLBIN / "riscv-none-elf-nm.exe"
SIZE = TOOLBIN / "riscv-none-elf-size.exe"
HOST_BIN = Path("D:/Codex_workplace/tools/w64devkit-2.10.0-r2/w64devkit/bin")
HOST_GCC = HOST_BIN / "gcc.exe"
PYTHON = Path("E:/Python/python.exe")

# Core units, compiled as C++ as upstream intends (the mappers use C++ type
# names).  InfoNES_Mapper.cpp #includes every mapper/*.cpp.  The headers wrap
# all declarations in extern "C", so the C port links to them directly.
CORE_UNITS = ["InfoNES", "K6502", "InfoNES_Mapper", "InfoNES_pAPU"]
CORE_HEADERS = ["InfoNES.h", "InfoNES_Mapper.h", "InfoNES_System.h", "InfoNES_Types.h",
                "InfoNES_pAPU.h", "K6502.h", "K6502_rw.h"]


# Source fixes applied to the staged copy only; third_party stays pristine.
# Each entry must match exactly once or staging fails.
PATCHES = [
    ("K6502.cpp",
     "#define AA_ABS   ( K6502_Read( PC++ ) | (WORD)K6502_Read( PC++ ) << 8 )",
     "#define AA_ABS   ({ WORD wLo_ = K6502_Read( PC++ ); wLo_ | (WORD)K6502_Read( PC++ ) << 8; })",
     "Two unsequenced PC++ in one expression (undefined behaviour). GCC fetches the "
     "high byte first, so LDA $2002 reads $0220 and games hang at their first V-blank wait."),
    ("K6502.cpp",
     "#define AA_ABS2  ( K6502_Read( PC++ ) | (WORD)K6502_Read( PC ) << 8 )",
     "#define AA_ABS2  ({ WORD wLo_ = K6502_Read( PC++ ); wLo_ | (WORD)K6502_Read( PC ) << 8; })",
     "Same defect in the JSR operand fetch: PC is read and incremented unsequenced."),
    ("InfoNES.cpp",
     "    InfoNES_DrawLine();\n  }\n",
     "    InfoNES_DrawLine();\n    InfoNES_LoadLine();\n  }\n",
     "Per-scanline hook (InfoNES's own LoadLine API from its LM4F232 port): the port "
     "diffs and uploads each line while it is still in the data cache."),
    ("InfoNES_System.h",
     "void InfoNES_LoadFrame();\n",
     "void InfoNES_LoadFrame();\n\n/* Transfer the scanline just rendered (PPU_Scanline) */\nvoid InfoNES_LoadLine();\n",
     "Declaration for the per-scanline hook."),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage_infones(dest: Path) -> dict[str, str]:
    """Copy the InfoNES core into dest with one consistent header set.

    Upstream's mapper/ directory also carries stale copies of InfoNES.h,
    InfoNES_Types.h, ... from a RAM_LACK (LM4F232) port.  A quoted #include in
    a mapper file would find those first and silently compile the mappers
    against different struct sizes.  Only the per-mapper sources are staged,
    so every unit resolves the top-level headers.  Returns source hashes.
    """
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "mapper").mkdir(parents=True)
    hashes = {}
    for unit in CORE_UNITS:
        src = INFONES / f"{unit}.cpp"
        shutil.copyfile(src, dest / f"{unit}.cpp")
        hashes[str(src.relative_to(ROOT))] = sha256(src)
    for name in CORE_HEADERS:
        shutil.copyfile(INFONES / name, dest / name)
        hashes[str((INFONES / name).relative_to(ROOT))] = sha256(INFONES / name)
    mappers = sorted((INFONES / "mapper").glob("InfoNES_Mapper_[0-9][0-9][0-9].cpp"))
    if not mappers:
        raise RuntimeError("no mapper sources found")
    for src in mappers:
        shutil.copyfile(src, dest / "mapper" / src.name)
        hashes[str(src.relative_to(ROOT))] = sha256(src)
    for name, old, new, _reason in PATCHES:
        path = dest / name
        text = path.read_text(encoding="latin-1")
        if text.count(old) != 1:
            raise RuntimeError(f"patch target not found exactly once in {name}: {old}")
        path.write_text(text.replace(old, new), encoding="latin-1")
    stray = [p.name for p in (dest / "mapper").iterdir() if p.suffix == ".h"]
    if stray:
        raise RuntimeError(f"stale mapper headers staged: {stray}")
    return hashes


# No exceptions, RTTI or C++ runtime: the core is C-style code.
CXX_FLAGS = ["-x", "c++", "-std=gnu++17", "-fno-exceptions", "-fno-rtti",
             "-fno-threadsafe-statics", "-fno-use-cxa-atexit"]


def run(args: list, log: Path | None = None, env: dict | None = None, cwd: Path | None = None) -> str:
    res = subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env, cwd=cwd)
    if log:
        log.write_text(res.stdout + res.stderr, encoding="utf-8")
    if res.returncode:
        raise RuntimeError(f"{Path(str(args[0])).name} failed ({res.returncode}):\n{res.stdout}{res.stderr}")
    return res.stdout


def host_env() -> dict:
    env = os.environ.copy()
    env["PATH"] = str(HOST_BIN) + os.pathsep + env["PATH"]
    return env
