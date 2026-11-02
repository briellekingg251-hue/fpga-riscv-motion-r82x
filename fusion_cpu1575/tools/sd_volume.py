"""64 MiB FAT32 superfloppy layout shared by the UDP installer and the simulator.

make_volume(source) returns {lba: 512-byte sector} for every initialized sector
plus SHA-256 hashes of the installed files.  Packages are the directories in
<source>/GAMES:
  * resource ABI 1/2 (FRUIT, SUBWAY): exactly GAME.BIN SPRITES.BIN PALETTE.BIN
    MANIFEST.BIN SAVE.DAT, as checked by the resident loader;
  * resource ABI 3 (PAL): MANIFEST.BIN and GAME.BIN executed from DDR3, plus
    any number of 8.3 resource and save files.
Every file is allocated contiguously; directories may span several clusters.
"""
import hashlib
import struct
import zlib
from pathlib import Path

SECTORS, RESERVED, FAT_SIZE, FATS = 131072, 32, 1024, 2
DATA = RESERVED + FAT_SIZE * FATS
ABI12_FILES = {'GAME.BIN', 'SPRITES.BIN', 'PALETTE.BIN', 'MANIFEST.BIN', 'SAVE.DAT'}
DDR_GAME_MIN, DDR_GAME_MAX = 0x80020000, 0x83000000


def short_name(name):
    parts = name.upper().split('.')
    if len(parts) > 2 or not 1 <= len(parts[0]) <= 8 or (len(parts) == 2 and not 1 <= len(parts[1]) <= 3):
        raise ValueError(f'8.3 filename required: {name}')
    allowed = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-'
    if any(c not in allowed for p in parts for c in p):
        raise ValueError(f'unsupported filename: {name}')
    return (parts[0].ljust(8) + (parts[1] if len(parts) == 2 else '').ljust(3)).encode('ascii')


def check_package(game):
    """Validate one game directory against the loader ABI; return its file names."""
    short_name(game.name)
    files = {p.name: p for p in game.iterdir() if p.is_file()}
    if 'MANIFEST.BIN' not in files:
        raise ValueError(f'{game}: MANIFEST.BIN missing')
    manifest = files['MANIFEST.BIN'].read_bytes()
    if len(manifest) != 32:
        raise ValueError('invalid manifest length')
    m = struct.unpack('<8I', manifest)
    if m[0] != 0x53444731 or m[7] != zlib.crc32(manifest[:28]):
        raise ValueError(f'{game}: invalid manifest')
    program = files['GAME.BIN'].read_bytes() if 'GAME.BIN' in files else b''
    if m[1] in (1, 2):
        if set(files) != ABI12_FILES:
            raise ValueError(f'{game}: expected exactly {sorted(ABI12_FILES)}')
        sprites, palette = files['SPRITES.BIN'].read_bytes(), files['PALETTE.BIN'].read_bytes()
        if m[2] != len(program) or not 0 < m[2] <= 0x17c00 - 8192:
            raise ValueError('invalid package ABI/manifest')
        if len(sprites) != (73728 if m[1] == 1 else 262144) or len(palette) != 768 or \
                tuple(m[3:6]) != tuple(zlib.crc32(b) for b in (program, sprites, palette)):
            raise ValueError('package CRC/size mismatch')
        if files['SAVE.DAT'].stat().st_size != 1024:
            raise ValueError('SAVE.DAT must contain two sectors')
    elif m[1] == 3:
        size, crc, load, entry = m[2], m[3], m[4], m[5]
        if not program or size != len(program) or crc != zlib.crc32(program) or load % 64 or \
                not DDR_GAME_MIN <= load <= DDR_GAME_MAX or size > DDR_GAME_MAX - load or \
                not load <= entry < load + size or entry % 4:
            raise ValueError(f'{game}: invalid ABI 3 program')
        for name in files:
            short_name(name)
    else:
        raise ValueError(f'{game}: unsupported resource ABI {m[1]}')
    return sorted(files)


def make_volume(source):
    """Return all initialized sectors; the boot sector must be committed last."""
    writes, hashes, _ = make_volume_with_owners(source)
    return writes, hashes


def make_volume_with_owners(source):
    """Like make_volume, plus {lba: 'GAMES/<dir>/<file>'} for every file data sector."""
    owners = {}
    writes = {i: bytes(512) for i in range(RESERVED)}
    fat = bytearray(FAT_SIZE * 512)
    struct.pack_into('<2I', fat, 0, 0x0ffffff8, 0x0fffffff)
    cursor = 2
    hashes = {}

    def allocate(contents, owner=None):
        nonlocal cursor
        count = max(1, (len(contents) + 511) // 512)
        first = cursor
        if cursor + count - 2 > SECTORS - DATA:
            raise ValueError('packages exceed the 64 MiB volume')
        for j in range(count):
            c = cursor + j
            struct.pack_into('<I', fat, c * 4, c + 1 if j + 1 < count else 0x0fffffff)
            writes[DATA + c - 2] = contents[j * 512:(j + 1) * 512].ljust(512, b'\0')
            if owner:
                owners[DATA + c - 2] = owner
        cursor += count
        return first

    def place(cluster, contents):
        """Write directory contents into an already allocated cluster chain."""
        sectors = (len(contents) + 511) // 512
        for j in range(sectors):
            writes[DATA + cluster + j - 2] = contents[j * 512:(j + 1) * 512].ljust(512, b'\0')

    def entry(name, cluster, size=0, directory=False):
        row = bytearray(32)
        row[:11] = short_name(name)
        row[11] = 0x10 if directory else 0x20
        struct.pack_into('<H', row, 20, cluster >> 16)
        struct.pack_into('<H', row, 26, cluster & 65535)
        struct.pack_into('<I', row, 28, size)
        return row

    def dot_rows(own, parent):
        rows = []
        for name, cluster in [(b'.          ', own), (b'..         ', parent)]:
            row = bytearray(entry('DOT', cluster, directory=True))
            row[:11] = name
            rows.append(row)
        return rows

    game_dirs = sorted(p for p in (Path(source) / 'GAMES').iterdir() if p.is_dir())
    if not 1 <= len(game_dirs) <= 8:
        raise ValueError('one to eight game packages required')
    names = {game: check_package(game) for game in game_dirs}
    root = allocate(bytes(512))
    games_dir = allocate(bytes(512 * (((len(game_dirs) + 3) * 32 + 511) // 512)))
    game_rows = []
    for game in game_dirs:
        files = names[game]
        game_cluster = allocate(bytes(512 * (((len(files) + 3) * 32 + 511) // 512)))
        rows = dot_rows(game_cluster, games_dir)
        for filename in files:
            contents = (game / filename).read_bytes()
            rows.append(entry(filename, allocate(contents, f'GAMES/{game.name}/{filename}'), len(contents)))
            hashes[f'GAMES/{game.name}/{filename}'] = hashlib.sha256(contents).hexdigest()
        place(game_cluster, b''.join(rows) + bytes(32))
        game_rows.append(entry(game.name, game_cluster, directory=True))
    place(games_dir, b''.join(dot_rows(games_dir, 0) + game_rows) + bytes(32))
    place(root, entry('GAMES', games_dir, directory=True) + bytes(32))
    boot = bytearray(512)
    boot[:11] = b'\xeb\x58\x90SDGAME  '
    struct.pack_into('<HBHBHHBHHHII', boot, 11, 512, 1, RESERVED, FATS, 0, 0, 0xf8, 0, 63, 255, 0, SECTORS)
    struct.pack_into('<IHHIHH', boot, 36, FAT_SIZE, 0, 0, root, 1, 6)
    boot[64:67] = b'\x80\x00\x29'
    struct.pack_into('<I', boot, 67, 0x53444731)
    boot[71:82], boot[82:90] = b'SD GAMES   ', b'FAT32   '
    boot[510:512] = b'\x55\xaa'
    fsinfo = bytearray(512)
    struct.pack_into('<I', fsinfo, 0, 0x41615252)
    struct.pack_into('<III', fsinfo, 484, 0x61417272, SECTORS - DATA - (cursor - 2), cursor)
    struct.pack_into('<I', fsinfo, 508, 0xaa550000)
    writes[0], writes[6] = bytes(boot), bytes(boot)
    writes[1], writes[7] = bytes(fsinfo), bytes(fsinfo)
    for copy in range(FATS):
        for i in range(FAT_SIZE):
            writes[RESERVED + copy * FAT_SIZE + i] = bytes(fat[i * 512:(i + 1) * 512])
    return writes, hashes, owners


def write_image(source, image):
    """Materialize the volume as a raw 64 MiB card image (simulation only)."""
    writes, hashes = make_volume(source)
    data = bytearray(SECTORS * 512)
    for lba, sector in writes.items():
        data[lba * 512:(lba + 1) * 512] = sector
    Path(image).write_bytes(bytes(data))
    return writes, hashes


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='write a simulation SD image')
    parser.add_argument('image', type=Path)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1] / 'sdcard')
    args = parser.parse_args()
    w, h = write_image(args.source, args.image)
    print(f'{args.image}: {len(w)} initialized sectors, {len(h)} files')
