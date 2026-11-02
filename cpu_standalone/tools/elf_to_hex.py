"""Convert a RV32 ELF image into the SoC's little-endian SRAM words."""
from pathlib import Path
import struct
import sys

raw = Path(sys.argv[1]).read_bytes()
header = struct.unpack_from('<16sHHIIIIIHHHHHH', raw)
if raw[:6] != b'\x7fELF\x01\x01' or header[2] != 243:
    raise ValueError('little-endian RV32 ELF required')
if header[9] != 32 or header[5] + header[9] * header[10] > len(raw):
    raise ValueError('invalid program header table')
ram = bytearray([0xa5]) * (int(sys.argv[3], 0) if len(sys.argv) > 3 else 131072)
for index in range(header[10]):
    kind, offset, va, pa, size, mem_size, flags, alignment = struct.unpack_from(
        '<IIIIIIII', raw, header[5] + index * header[9])
    if kind != 1:
        continue
    base = pa - 0x80000000
    if not (0 <= base and base + mem_size <= len(ram)):
        raise ValueError('segment outside SRAM')
    if not (offset + size <= len(raw) and size <= mem_size):
        raise ValueError('invalid segment')
    ram[base:base + size] = raw[offset:offset + size]
Path(sys.argv[2]).write_text(''.join(
    f'{int.from_bytes(ram[i:i+4], "little"):08x}\n'
    for i in range(0, len(ram), 4)), newline='\n')
