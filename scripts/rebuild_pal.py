from pathlib import Path
import os
import argparse, datetime, hashlib, importlib.util, os, shutil, sys

ROOT = Path(__file__).resolve().parents[1]
LEGACY = r'E:\Codex_workplace\cpu_pose_touch_fusion_20261008\fusion_cpu1575'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description='Rebuild PAL and compare the frozen SD package.')
    parser.add_argument('output', type=Path, help='New output directory outside the repository')
    parser.add_argument('--toolbin', type=Path, required=True)
    parser.add_argument('--data', type=Path, required=True, help='Legally obtained PAL DOS game data directory')
    parser.add_argument('--navy-root', type=Path, required=True, help='Locally obtained navy-apps source root')
    args = parser.parse_args()
    if not args.data.is_dir() or not args.navy_root.is_dir():
        parser.error('game data and navy-apps source directories must exist')
    out = args.output.resolve()
    if out.exists() or out == ROOT or ROOT in out.parents:
        parser.error('output must be a new directory outside the repository')
    shutil.copytree(ROOT / 'fusion_cpu1575', out)
    shutil.copytree(args.navy_root, out / 'third_party/navy-apps')
    temp = out / '_tmp'
    temp.mkdir()
    os.environ['TMP'] = os.environ['TEMP'] = str(temp)
    release = ROOT / 'release/r82x_s4_ai31_20261022/sdcard/GAMES/PAL'
    data = out / 'game_data/PAL_DOS'
    data.mkdir(parents=True)
    for path in args.data.iterdir():
        if path.is_file():
            shutil.copy2(path, data / path.name)
    sys.path.insert(0, str(out / 'tools'))
    spec = importlib.util.spec_from_file_location('pal_builder', out / 'tools/build_pal_game.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.cc.TOOLBIN = args.toolbin
    builder.cc.GCC = args.toolbin / 'riscv-none-elf-gcc.exe'
    builder.cc.OBJCOPY = args.toolbin / 'riscv-none-elf-objcopy.exe'
    builder.cc.SIZE = args.toolbin / 'riscv-none-elf-size.exe'
    builder.OBJDUMP = args.toolbin / 'riscv-none-elf-objdump.exe'
    for flags in (builder.ENGINE_FLAGS, builder.PORT_FLAGS, builder.FW_FLAGS):
        flags.append(f'-fmacro-prefix-map={out}={LEGACY}')
    epoch = int(datetime.datetime(2026, 10, 10, 12, tzinfo=datetime.timezone.utc).timestamp())
    previous = os.environ.get('SOURCE_DATE_EPOCH')
    old_argv = sys.argv
    os.environ['SOURCE_DATE_EPOCH'] = str(epoch)
    sys.argv = ['build_pal_game.py']
    try:
        builder.main()
    finally:
        sys.argv = old_argv
        if previous is None:
            os.environ.pop('SOURCE_DATE_EPOCH', None)
        else:
            os.environ['SOURCE_DATE_EPOCH'] = previous
    actual = out / 'sdcard/GAMES/PAL'
    if release.is_dir():
        for path in release.iterdir():
            if path.is_file() and (not (actual / path.name).is_file() or sha(actual / path.name) != sha(path)):
                raise SystemExit('PAL mismatch: ' + path.name)
    print('PASS: PAL built with locally supplied dependencies and game data')

if __name__ == '__main__':
    main()
