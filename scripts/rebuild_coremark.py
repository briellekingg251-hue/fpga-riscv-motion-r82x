from pathlib import Path
import argparse, hashlib, importlib.util, os, shutil

ROOT = Path(__file__).resolve().parents[1]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description='Rebuild independent 169.714 MHz CoreMark firmware.')
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
    src = ROOT / 'cpu_standalone'
    shutil.copytree(src / 'source', out / 'source')
    shutil.copytree(src / 'firmware/src', out / 'firmware/src')
    shutil.copytree(src / 'tools', out / 'tools')
    shutil.copy2(src / 'source_manifest.json', out / 'source_manifest.json')
    shutil.copy2(src / 'firmware/coremark_core_sha256.json', out / 'firmware/coremark_core_sha256.json')
    spec = importlib.util.spec_from_file_location('cpu_board_builder', src / 'prepare.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    builder.ROOT = out
    builder.GCCBIN = args.toolbin
    builder.GCC = args.toolbin / 'riscv-none-elf-gcc.exe'
    builder.firmware('performance', 13000)
    actual = out / 'firmware/performance_13000/program.hex'
    reference = src / 'firmware/performance_13000/program.hex'
    if sha(actual) != sha(reference):
        raise SystemExit('CoreMark firmware mismatch: ' + sha(actual))
    print('PASS: standalone CPU CoreMark program.hex ' + sha(actual))

if __name__ == '__main__':
    main()
