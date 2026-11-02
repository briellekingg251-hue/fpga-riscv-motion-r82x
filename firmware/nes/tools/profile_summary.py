"""Summarise an ISS --profile histogram by function.

usage: python -I tools/profile_summary.py ELF PROFILE [TOP]
PROFILE lines: "<pc hex> <instructions> [<cycles>]".
"""
from __future__ import annotations

import bisect
import collections
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc


def main() -> int:
    elf, profile = Path(sys.argv[1]), Path(sys.argv[2])
    top = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    symbols = []
    for line in subprocess.check_output([str(nc.NM), "-n", "--defined-only", str(elf)], text=True).splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] in "tTwW":
            symbols.append((int(parts[0], 16), parts[2]))
    addresses = [a for a, _ in symbols]
    instructions, cycles = collections.Counter(), collections.Counter()
    for line in profile.read_text().splitlines():
        fields = line.split()
        index = bisect.bisect_right(addresses, int(fields[0], 16)) - 1
        name = symbols[index][1] if index >= 0 else "?"
        instructions[name] += int(fields[1])
        cycles[name] += int(fields[2]) if len(fields) > 2 else int(fields[1])
    total = sum(cycles.values())
    print(f"{'cycles':>12} {'share':>6} {'instr':>12}  function")
    for name, value in cycles.most_common(top):
        print(f"{value:12d} {100 * value / total:5.1f}% {instructions[name]:12d}  {name}")
    print("total cycles", total, "instructions", sum(instructions.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
