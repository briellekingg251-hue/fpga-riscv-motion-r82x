"""Tiny FAT32 reader for rv32sim SD images: list GAMES/<dir>, extract or replace files in place."""
import struct, sys
from pathlib import Path

class Image:
    def __init__(self, path):
        self.path = Path(path); self.data = bytearray(self.path.read_bytes())
        b = self.data[:512]
        self.spc = b[13]; reserved = struct.unpack_from('<H', b, 14)[0]; nf = b[16]
        fs = struct.unpack_from('<I', b, 36)[0]; self.root = struct.unpack_from('<I', b, 44)[0]
        self.fat = reserved * 512; self.base = (reserved + nf * fs) * 512
    def chain(self, c):
        out = []
        while 2 <= c < 0x0ffffff8:
            out.append(c); c = struct.unpack_from('<I', self.data, self.fat + 4 * c)[0] & 0x0fffffff
        return out
    def entries(self, cluster):
        for c in self.chain(cluster):
            off = self.base + (c - 2) * self.spc * 512
            for i in range(self.spc * 16):
                e = self.data[off + 32 * i: off + 32 * i + 32]
                if e[0] == 0: return
                if e[0] == 0xe5 or e[11] == 0x0f: continue
                name = e[:8].decode().strip() + ('.' + e[8:11].decode().strip() if e[8:11].strip() else '')
                yield name, struct.unpack_from('<H', e, 20)[0] << 16 | struct.unpack_from('<H', e, 26)[0], struct.unpack_from('<I', e, 28)[0]
    def find(self, *path):
        c = self.root
        for p in path:
            c, size = next((cl, s) for n, cl, s in self.entries(c) if n == p)
        return c, size
    def read(self, *path):
        c, size = self.find(*path)
        return b''.join(bytes(self.data[self.base + (x - 2) * self.spc * 512: self.base + (x - 1) * self.spc * 512]) for x in self.chain(c))[:size]
    def replace(self, contents, *path):
        c, size = self.find(*path)
        if len(contents) != size: raise ValueError('size must match')
        clusters = self.chain(c); n = self.spc * 512
        for i, x in enumerate(clusters):
            chunk = contents[i * n:(i + 1) * n]
            self.data[self.base + (x - 2) * n: self.base + (x - 2) * n + len(chunk)] = chunk
    def save(self, path=None): Path(path or self.path).write_bytes(self.data)
