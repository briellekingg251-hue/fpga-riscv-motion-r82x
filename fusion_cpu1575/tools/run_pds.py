"""Snapshot synthesis inputs and run PDS in a fresh evidence directory."""
from __future__ import annotations

import subprocess
import sys
import time
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PDS = Path("F:/jinsgai/FPGA/pds_software/PDS_2022.2-SP6.4/bin/pds_shell.exe")


def read_timing_summary(report: Path) -> dict:
    if not report.is_file():
        return {'status': 'NOT_RUN', 'report': str(report)}
    rows = []
    section = None
    for line in report.read_text(errors='replace').splitlines():
        match = re.fullmatch(r'(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):', line.strip())
        if match:
            section = match.groups()
            continue
        if section:
            pattern = r'\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*'
            if section[0] == 'Minimum Pulse Width':
                pattern = r'\s*(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*'
            row = re.fullmatch(pattern, line)
            if row:
                if section[0] == 'Minimum Pulse Width':
                    launch, slack, total, failed, endpoints = row.groups()
                    capture = launch
                else:
                    launch, capture, slack, total, failed, endpoints = row.groups()
                rows.append(dict(kind=section[0], corner=section[1], launch=launch, capture=capture,
                                 slack_ns=float(slack), total_slack_ns=float(total),
                                 failed_endpoints=int(failed), endpoints=int(endpoints)))
            elif rows and line.startswith('==='):
                section = None
    kinds = {(row['kind'], row['corner']) for row in rows}
    complete = all((kind, corner) in kinds for kind in ('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width')
                   for corner in ('Slow', 'Fast'))
    failed = any(row['slack_ns'] < 0 or row['total_slack_ns'] < 0 or row['failed_endpoints'] for row in rows)
    return {'status': 'FAIL' if failed else ('PASS' if complete else 'INCOMPLETE'),
            'report': str(report), 'rows': rows,
            'scope': 'Declared clock constraints; external SD/RGMII IO timing is not yet signed off'}


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument('--work',default='work_net')
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--route-iterations', type=int, default=0)
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.work) or args.seed < 1 or args.route_iterations < 0:
        parser.error('work must be a simple directory name; seed >= 1 and iterations >= 0')
    subprocess.run([sys.executable, str(ROOT / "tools" / "gen_paths.py")], check=True)
    subprocess.run([sys.executable, str(ROOT / "tools" / "pack_rtl.py")], check=True)
    work = ROOT / "pds" / args.work
    if (work/'pds_console.log').exists():
        raise SystemExit('Existing build evidence retained; choose a new --work name')
    work.mkdir(parents=True, exist_ok=True)
    inputs=work/'input';inputs.mkdir(exist_ok=True)
    for filename in ['program.hex','font.hex','palette.hex']:
        shutil.copyfile(ROOT/'build'/filename,inputs/filename)
    source=(ROOT/'build/fn_design.v').read_text(encoding='utf-8')
    source=source.replace((ROOT/'build').as_posix(),inputs.as_posix())
    source=re.sub(r'(`define FN_PROGRAM_HEX_BITS) \d+',rf'\g<1> {len((inputs/"program.hex").as_posix())*8}',source)
    (inputs/'fn_design.v').write_text(source,encoding='utf-8')
    shutil.copyfile(ROOT/'pds/fruit_ninja.fdc',inputs/'fruit_ninja.fdc')
    flow=(ROOT/'pds/flow.tcl').read_text().replace((ROOT/'build/fn_design.v').as_posix(),(inputs/'fn_design.v').as_posix())
    flow=flow.replace((ROOT/'pds/fruit_ninja.fdc').as_posix(),(inputs/'fruit_ninja.fdc').as_posix())
    flow = flow.replace('-gplace_seed 1 -groute_seed 1',
                        f'-gplace_seed {args.seed} -groute_seed {args.seed}')
    if args.route_iterations:
        flow = flow.replace('-number_of_router_thread 4',
            '-number_of_router_thread 4 -enable_route_constraint_iterate '
            f'-route_constraint_iterate_times {args.route_iterations} '
            '-route_constraint_slack 0.1 -route_constraint_max_timing_path 80 '
            '-share_router_control_signal false')
    (inputs/'flow.tcl').write_text(flow)
    manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs.iterdir() if p.is_file()}
    (work/'input_sha256.json').write_text(json.dumps(manifest,indent=2))
    (work/'build_options.json').write_text(json.dumps(vars(args), indent=2))
    t0 = time.time()
    with open(work / "pds_console.log", "w", encoding="utf-8", errors="replace") as log:
        rc = subprocess.run([str(PDS), "-file", str(inputs / "flow.tcl"),
                             "-work_dir", str(work), "-project_name", "fruit_ninja"],
                            stdout=log, stderr=subprocess.STDOUT, cwd=work).returncode
    print(f"pds_shell exit {rc} after {time.time() - t0:.0f} s")
    (work/'run_result.json').write_text(json.dumps({'exit_code':rc,'elapsed_seconds':time.time()-t0,
        'timing':read_timing_summary(work/'report_timing/fn_top.rtr'),
        'acceptance':'BOARD_VERIFICATION_AND_EXTERNAL_IO_TIMING_REQUIRED'},indent=2))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
