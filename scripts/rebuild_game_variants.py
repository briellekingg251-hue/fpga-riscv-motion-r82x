from pathlib import Path
import os
import argparse, hashlib, importlib.util, shutil, sys

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'release/r82x_s4_ai31_20261022/sdcard/GAMES'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description='Rebuild and compare four frozen FRUIT/SUBWAY game executables.')
    parser.add_argument('output', type=Path, help='New output directory outside the repository')
    parser.add_argument('--toolbin', type=Path, required=True, help='xPack 15.2.0-1 bin directory')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists() or out == ROOT or ROOT in out.parents:
        parser.error('output must be a new directory outside the repository')
    out.mkdir(parents=True)
    temp = out / '_tmp'
    temp.mkdir()
    os.environ['TMP'] = os.environ['TEMP'] = str(temp)
    fake = out / 'assets'
    for game in ('FRUIT', 'SUBWAY'):
        dest = fake / 'fusion_cpu1575/sdcard/GAMES' / game
        dest.mkdir(parents=True)
        for filename in ('SPRITES.BIN', 'PALETTE.BIN'):
            shutil.copy2(RELEASE / game / filename, dest / filename)
    sys.path.insert(0, str(ROOT / 'fusion_cpu1575/tools'))
    spec = importlib.util.spec_from_file_location('variant_builder', ROOT / 'tools/build_uart_game_variants.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.ROOT = fake
    builder.cc.GCC = args.toolbin / 'riscv-none-elf-gcc.exe'
    builder.cc.OBJCOPY = args.toolbin / 'riscv-none-elf-objcopy.exe'
    builder.cc.SIZE = args.toolbin / 'riscv-none-elf-size.exe'
    mismatches = []
    for folder, mode in (('frozen_r74', 'POSE'), ('frozen_touch', 'TOUCH')):
        for game in ('FRUIT', 'SUBWAY'):
            builder.FW = ROOT / 'firmware' / folder / game.lower() / 'fw'
            target = out / f'{game.lower()}_{mode.lower()}'
            old = sys.argv
            sys.argv = ['build_uart_game_variants.py', '--output', str(target)]
            try:
                builder.main()
            finally:
                sys.argv = old
            output_game = target / 'sdcard/GAMES' / game
            for filename in (mode + '.BIN', mode + '.MAN', 'GAME.BIN', 'MANIFEST.BIN'):
                actual = output_game / filename
                expected = RELEASE / game / filename
                match = sha(actual) == sha(expected)
                print(f'{game}/{mode}/{filename}: {"MATCH" if match else "MISMATCH"}', flush=True)
                if not match:
                    mismatches.append(f'{game}/{mode}/{filename}')
    if mismatches:
        raise SystemExit('Mismatch: ' + ', '.join(mismatches))
    print('PASS: all four binaries, manifests and dispatchers match frozen SD release')

if __name__ == '__main__':
    main()
