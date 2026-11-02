from pathlib import Path
import os
import argparse, hashlib, subprocess

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'firmware/frozen_r74/poseview'
FIRMWARE = SRC / 'fw'
REFERENCE = ROOT / 'release/r82x_s4_ai31_20261022/sdcard/GAMES/POSEVIEW/GAME.BIN'

def main():
    parser = argparse.ArgumentParser(description='Rebuild the frozen POSEVIEW executable.')
    parser.add_argument('output', type=Path, help='New output directory outside the repository')
    parser.add_argument('--toolbin', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists() or out == ROOT or ROOT in out.parents:
        parser.error('output must be a new directory outside the repository')
    out.mkdir(parents=True)
    temp = out / '_tmp'
    temp.mkdir()
    os.environ['TMP'] = os.environ['TEMP'] = str(temp)
    elf, binary = out / 'view.elf', out / 'view.bin'
    cflags = ['-march=rv32i_zmmul_zicsr', '-mabi=ilp32', '-mno-relax', '-msmall-data-limit=0',
              '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
              '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-g',
              '-DCPU_CLOCK_HZ=157500000u', '-Werror', '-I' + str(FIRMWARE), '-nostdlib', '-nostartfiles',
              '-Wl,--gc-sections', '-Wl,--no-warn-rwx-segments', '-DFN_POSE_PRODUCTION=1',
              '-DFN_GPU_POSE_YIELD=1', '-DFN_DUAL_POSE_PIP=1', '-DFN_POSE_DEBUG=1']
    names = ['start.S', 'jump.S', 'gpu.c', 'uart.c', 'game_runtime.c', 'game_pose_service.c',
             'pose_mmio_source.c', 'pose_service.c', 'p2_algo.c', 'pose_input.c']
    subprocess.run([str(args.toolbin / 'riscv-none-elf-gcc.exe'), *cflags, '-T', str(SRC / 'view_link.ld'),
                    '-o', str(elf), *[str(FIRMWARE / name) for name in names], str(SRC / 'pose_view.c'), '-lgcc'], check=True)
    subprocess.run([str(args.toolbin / 'riscv-none-elf-objcopy.exe'), '-O', 'binary', str(elf), str(binary)], check=True)
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    if digest != hashlib.sha256(REFERENCE.read_bytes()).hexdigest():
        raise SystemExit(f'MISMATCH: {digest}')
    print(f'PASS: POSEVIEW GAME.BIN {digest}')

if __name__ == '__main__':
    main()
