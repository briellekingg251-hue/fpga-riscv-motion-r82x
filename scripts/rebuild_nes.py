from pathlib import Path
import os
import argparse, hashlib, importlib.util, shutil, sys

ROOT = Path(__file__).resolve().parents[1]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description='Rebuild the NES emulator binary without bundled commercial ROMs.')
    parser.add_argument('output', type=Path, help='New output directory outside the repository')
    parser.add_argument('--toolbin', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists() or out == ROOT or ROOT in out.parents:
        parser.error('output must be a new directory outside the repository')
    shutil.copytree(ROOT / 'firmware/nes', out)
    temp = out / '_tmp'
    temp.mkdir()
    os.environ['TMP'] = os.environ['TEMP'] = str(temp)
    sys.path.insert(0, str(out / 'tools'))
    spec = importlib.util.spec_from_file_location('nes_builder', out / 'tools/build_nes.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.CPU_HZ = 157500000
    for attr, executable in [('GCC','riscv-none-elf-gcc.exe'), ('OBJCOPY','riscv-none-elf-objcopy.exe'),
                             ('OBJDUMP','riscv-none-elf-objdump.exe'), ('NM','riscv-none-elf-nm.exe'),
                             ('SIZE','riscv-none-elf-size.exe')]:
        setattr(builder.nc, attr, args.toolbin / executable)
    old = sys.argv
    sys.argv = ['build_nes.py']
    try:
        if builder.main() != 0:
            raise SystemExit('NES builder failed')
    finally:
        sys.argv = old
    release = ROOT / 'release/r82x_s4_ai31_20261022/sdcard/GAMES/NES'
    result = out / 'build/sdcard/GAMES/NES'
    for name in ('GAME.BIN', 'MANIFEST.BIN'):
        if sha(result / name) != sha(release / name):
            raise SystemExit('NES mismatch: ' + name + ' actual ' + sha(result / name))
    print('PASS: NES executable and manifest match; ROMs remain external')

if __name__ == '__main__':
    main()
