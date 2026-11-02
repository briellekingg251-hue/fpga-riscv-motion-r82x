"""Extract the iNES images embedded in RiscV_GameConsole_FPGA's rom.c.

The upstream console compiles exactly one ROM into its firmware, selected by an
#ifdef block in nes_test/application/rom.c.  This tool turns every block into a
standalone .NES file so the SD build can carry several games.

The images are commercial game dumps that ship in the upstream repository.  They
are written only to a local, git-ignored directory for personal testing; this
workspace never commits or redistributes them.

usage: python -I tools/extract_repo_roms.py <rom.c> <out_dir>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

INES_MAGIC = b"NES\x1a"
HEADER_BYTES = 16
PRG_UNIT = 0x4000
CHR_UNIT = 0x2000
TRAINER_BYTES = 512
# 8.3 names for the FAT directory; keys are the #ifdef symbols in rom.c.
NAMES = {
    "tank": "TANK", "MARIO": "MARIO", "HDL": "HDL", "MXT": "MXT",
    "SLMS": "SLMS", "contra": "CONTRA", "ICanRemember": "ICANREM",
}
BLOCK = re.compile(r"^#ifdef\s+(\w+)\s*$(.*?)^#endif", re.M | re.S)
ARRAY = re.compile(r"nes_rom\s*\[\s*(\d*)\s*\]\s*=\s*\{(.*?)\}\s*;", re.S)
NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|\d+")
COMMENT = re.compile(r"/\*.*?\*/|//[^\n]*", re.S)


def expected_size(image: bytes) -> int:
    """Size implied by the iNES header (header + trainer + PRG + CHR)."""
    if image[:4] != INES_MAGIC:
        raise ValueError("missing iNES magic")
    prg, chr_banks, flags6 = image[4], image[5], image[6]
    if prg == 0:
        raise ValueError("zero PRG banks")
    trainer = TRAINER_BYTES if flags6 & 4 else 0
    return HEADER_BYTES + trainer + prg * PRG_UNIT + chr_banks * CHR_UNIT


def parse_blocks(text: str) -> dict[str, bytes]:
    roms: dict[str, bytes] = {}
    for symbol, body in BLOCK.findall(text):
        match = ARRAY.search(body)
        if match is None:
            continue
        values = [int(tok, 0) for tok in NUMBER.findall(COMMENT.sub(" ", match.group(2)))]
        if any(v < 0 or v > 255 for v in values):
            raise ValueError(f"{symbol}: byte value out of range")
        declared = int(match.group(1)) if match.group(1) else None
        if declared is not None and declared != len(values):
            raise ValueError(f"{symbol}: declared {declared} bytes, initializer has {len(values)}")
        roms[symbol] = bytes(values)
    return roms


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("rom_c", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()
    roms = parse_blocks(args.rom_c.read_text(encoding="latin-1"))
    if not roms:
        print("no nes_rom arrays found", file=sys.stderr)
        return 1
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = []
    for symbol, image in roms.items():
        name = NAMES.get(symbol)
        if name is None:
            raise ValueError(f"no 8.3 name for #ifdef {symbol}")
        size = expected_size(image)
        if len(image) < size:
            raise ValueError(f"{symbol}: {len(image)} bytes, header needs {size}")
        image = image[:size]  # drop padding past the last CHR bank
        path = args.out_dir / f"{name}.NES"
        path.write_bytes(image)
        mapper = (image[6] >> 4) | (image[7] & 0xF0)
        report.append({"symbol": symbol, "file": path.name, "bytes": len(image),
                       "prg_16k": image[4], "chr_8k": image[5], "mapper": mapper,
                       "sha256": hashlib.sha256(image).hexdigest()})
    (args.out_dir / "EXTRACTED.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    for row in report:
        print(f"{row['file']:12} {row['bytes']:7} B  mapper {row['mapper']:3}  "
              f"PRG {row['prg_16k']:2}x16K  CHR {row['chr_8k']:2}x8K")
    return 0


if __name__ == "__main__":
    sys.exit(main())
