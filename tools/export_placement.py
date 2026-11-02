"""Export native placed primitives while proving all four input DBs unchanged."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PDS = Path('F:/jinsgai/FPGA/pds_software/PDS_2022.2-SP6.4/bin/pds_shell.exe')


def digest(path):
    with path.open('rb') as handle:
        result = hashlib.sha256()
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('native_directory', type=Path)
    parser.add_argument('evidence_name')
    parser.add_argument('--top', default='fn_top')
    parser.add_argument('--apm-groups', action='store_true',
                        help='Export APM macro groups and their primitive details')
    args = parser.parse_args()
    out = ROOT / 'evidence' / args.evidence_name
    assert out.resolve().parent == (ROOT / 'evidence').resolve()
    assert not out.exists(), 'Keep prior exports immutable; choose a fresh name'
    native = args.native_directory.resolve()
    files = {
        'db': native / 'place_route' / (args.top + '_pnr.adf'),
        'devmap_db': native / 'device_map' / (args.top + '_map.adf'),
        'synthesize_db': native / 'synthesize' / (args.top + '_syn.adf'),
        'compile_db': native / 'compile' / (args.top + '_comp.adf'),
    }
    before = {str(path): digest(path) for path in files.values()}
    out.mkdir()
    (out / 'INPUTS.json').write_text(json.dumps(before, indent=2) + '\n')
    command = 'generate_constraint ' + ' '.join('-' + key + ' {' + path.as_posix() + '}' for key, path in files.items())
    script = out / 'export.tcl'
    export_flags = ' -device APM -group -detail' if args.apm_groups else ' -prim'
    script.write_text('set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676\n' + command +
                      ' -file {' + (out / 'placed_sites.pcf').as_posix() + '}' + export_flags + '\n')
    row = {'status': 'RUNNING_EXPORT', 'start': time.time(), 'inputs': before,
           'native_directory': str(native), 'input_tool_sha256': digest(PDS),
           'export_flags': export_flags, 'input_helper_sha256': digest(Path(__file__))}
    receipt = out / 'RESULT.json'
    receipt.write_text(json.dumps(row, indent=2) + '\n')
    (out / 'EXPORT_HELPER.py').write_bytes(Path(__file__).read_bytes())
    with (out / 'console.log').open('w') as log:
        proc = subprocess.Popen([str(PDS), '-file', str(script), '-work_dir', str(out), '-project_name', 'export'],
                                stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        row['pid'] = proc.pid
        receipt.write_text(json.dumps(row, indent=2) + '\n')
        code = proc.wait()
    after = {str(path): digest(path) for path in files.values()}
    row.update(exit=code, end=time.time(), databases_unchanged=(after == before), after=after)
    pcf = out / 'placed_sites.pcf'
    errors = [line for line in (out / 'console.log').read_text(errors='replace').splitlines() if line.startswith('E:')]
    row['native_errors'] = errors
    row['status'] = 'PASS_NATIVE_READONLY_PLACEMENT_EXPORT' if code == 0 and after == before and pcf.is_file() and not errors else 'FAIL_EXPORT'
    row['output_files'] = {name: digest(out / name) for name in ['export.tcl', 'console.log', 'EXPORT_HELPER.py']}
    if pcf.is_file():
        row['output_files']['placed_sites.pcf'] = digest(pcf)
    receipt.write_text(json.dumps(row, indent=2) + '\n')
    assert row['status'] == 'PASS_NATIVE_READONLY_PLACEMENT_EXPORT', row
    print(row['status'], str(out), flush=True)


if __name__ == '__main__':
    main()
