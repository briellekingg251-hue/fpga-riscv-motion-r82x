from pathlib import Path
import argparse, hashlib, json, re, shutil

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = 'E:/Codex_workplace/cpu_pose_touch_fusion_20261008'
DESIGN = 'hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96'

def main():
    parser = argparse.ArgumentParser(description='Prepare an isolated relocated R82x compile workspace; frozen inputs remain unchanged.')
    parser.add_argument('output', type=Path, help='New empty output directory, outside this repository')
    parser.add_argument('--vendor-dir', type=Path, required=True, help='Locally licensed PDS-generated vendor directory')
    parser.add_argument('--video-pll', type=Path, required=True, help='Locally generated video_pll.v')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists() or out == ROOT or ROOT in out.parents:
        parser.error('output must be a new directory outside the repository')
    if not args.video_pll.is_file():
        parser.error('video PLL source is missing')
    pll = args.video_pll.read_bytes()
    if b'module video_pll' not in pll:
        parser.error('video PLL source must define module video_pll')
    manifest = json.loads((ROOT / 'evidence/r82x_build/input_manifest.json').read_text(encoding='utf-8'))
    sources = []
    for name, expected in manifest.items():
        src = (args.vendor_dir / name.removeprefix('hardware/vendor/')) if name.startswith('hardware/vendor/') else (ROOT / name)
        if not src.is_file() or hashlib.sha256(src.read_bytes()).hexdigest() != expected:
            raise RuntimeError('Frozen input mismatch: ' + name)
        sources.append((name, src))
    for name, src in sources:
        dest = out / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    path = out / DESIGN / 'fn_design.v'
    raw = path.read_bytes()
    marker = b'// VENDOR_VIDEO_PLL_INSERTION_POINT'
    if raw.count(marker) != 1:
        raise RuntimeError('Expected one video PLL insertion point')
    replaced = raw.replace(marker, pll).replace(ORIGINAL.encode(), out.as_posix().encode())
    program = out.as_posix() + '/' + DESIGN + '/boot_nes_program.hex'
    replaced, count = re.subn(rb'(`define FN_PROGRAM_HEX_BITS\s+)\d+', lambda m: m.group(1) + str(len(program.encode()) * 8).encode(), replaced)
    if count != 1:
        raise RuntimeError('Expected one program path width declaration')
    path.write_bytes(replaced)
    evidence = ROOT / 'evidence/r82x_build'
    shutil.copy2(evidence / 'fn_top_apm_sites.pcf', out / 'fn_top_apm_sites.pcf')
    legacy_work = ORIGINAL + '/physical_production_r82x_nes_s4'
    for stage in ('compile', 'synthesis', 'map', 'pnr', 'sta', 'bitgen'):
        tcl = (evidence / (stage + '.tcl')).read_text(encoding='utf-8')
        tcl = tcl.replace(legacy_work, out.as_posix()).replace(ORIGINAL, out.as_posix())
        (out / (stage + '_relocated.tcl')).write_text(tcl, encoding='utf-8')
    print('Prepared', out)
    print('Run PDS: pds_shell -file <output>/compile_relocated.tcl -work_dir <output> -project_name fusion')
    print('Further relocated stage scripts are generated, but require independent validation.')

if __name__ == '__main__':
    main()
