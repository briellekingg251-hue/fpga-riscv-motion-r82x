from pathlib import Path
import os
import argparse, hashlib, subprocess

ROOT = Path(__file__).resolve().parents[1]
FW = ROOT / 'firmware/frozen_boot/fw'
REFERENCE = ROOT / 'hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/boot_nes_program.hex'

def main():
    parser = argparse.ArgumentParser(description='Rebuild the frozen R82x startup ROM.')
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
    elf, binary = out / 'boot.elf', out / 'boot.bin'
    flags = ['-march=rv32i_zmmul_zicsr','-mabi=ilp32','-mno-relax','-msmall-data-limit=0',
             '-O2','-ffreestanding','-fno-builtin','-fno-stack-protector','-ffunction-sections',
             '-fdata-sections','-Wall','-Wextra','-g','-DCPU_CLOCK_HZ=157500000u','-Werror',
             '-I' + str(FW),'-nostdlib','-nostartfiles','-Wl,--gc-sections','-Wl,--no-warn-rwx-segments']
    names = ['start.S','jump.S','boot.c','cardlink.c','uartlink.c','gpu.c','uart.c','fat32.c','sd_spi.c','game_runtime.c']
    subprocess.run([str(args.toolbin / 'riscv-none-elf-gcc.exe'), *flags, '-T', str(FW / 'boot_link.ld'),
                    '-o', str(elf), *[str(FW / name) for name in names], '-lgcc'], check=True)
    subprocess.run([str(args.toolbin / 'riscv-none-elf-objcopy.exe'), '-O', 'binary', str(elf), str(binary)], check=True)
    boot = binary.read_bytes()
    if len(boot) > 24576:
        raise SystemExit('boot exceeds reserved ROM space')
    ram = bytearray(131072)
    ram[0x18000:0x18000 + len(boot)] = boot
    content = ''.join(f'{int.from_bytes(ram[i:i+4], "little"):08x}\r\n' for i in range(0, len(ram), 4)).encode('ascii')
    (out / 'program.hex').write_bytes(content)
    digest = hashlib.sha256(content).hexdigest()
    if digest != hashlib.sha256(REFERENCE.read_bytes()).hexdigest():
        raise SystemExit('boot ROM mismatch: ' + digest)
    print('PASS: R82x boot ROM ' + digest)

if __name__ == '__main__':
    main()
