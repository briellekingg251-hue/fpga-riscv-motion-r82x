from pathlib import Path
import argparse, hashlib, importlib.util, shutil, sys

ROOT = Path(__file__).resolve().parents[1]
LEGACY = r'E:\Codex_workplace\cpu_pose_touch_fusion_20261008\games_cpu1575'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description='Rebuild DOOM and compare the frozen SD binary.')
    parser.add_argument('output', type=Path, help='New output directory outside the repository')
    parser.add_argument('--toolbin', type=Path, required=True)
    parser.add_argument('--wad', type=Path, required=True, help='Legally obtained DOOM WAD file')
    args = parser.parse_args()
    if not args.wad.is_file():
        parser.error('WAD file not found')
    out = args.output.resolve()
    if out.exists() or out == ROOT or ROOT in out.parents:
        parser.error('output must be a new directory outside the repository')
    shutil.copytree(ROOT / 'games_cpu1575', out)
    sd = ROOT / 'release/r82x_s4_ai31_20261022/sdcard/GAMES/DOOM'
    wad = out / 'third_party/PureDOOM/doom1.wad'
    wad.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.wad, wad)
    sys.path.insert(0, str(out / 'tools'))
    spec = importlib.util.spec_from_file_location('doom_builder', out / 'tools/build_doom.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.cc.TOOLBIN = args.toolbin
    builder.cc.GCC = args.toolbin / 'riscv-none-elf-gcc.exe'
    builder.cc.OBJCOPY = args.toolbin / 'riscv-none-elf-objcopy.exe'
    builder.COMMON.append(f'-fmacro-prefix-map={out}={LEGACY}')
    old = sys.argv
    sys.argv = ['build_doom.py']
    try:
        builder.main()
    finally:
        sys.argv = old
    actual = out / 'sdcard/GAMES/DOOM/GAME.BIN'
    expected = sd / 'GAME.BIN'
    if sha(actual) != sha(expected):
        raise SystemExit('DOOM MISMATCH: ' + sha(actual))
    print('PASS: DOOM GAME.BIN ' + sha(actual))

if __name__ == '__main__':
    main()
