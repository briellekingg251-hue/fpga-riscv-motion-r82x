"""Fail-closed parsing of all ten native PDS timing summary classes."""
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
rtr = root / 'report_timing/o2_pds_top.rtr'
with rtr.open(errors='replace') as file:
    text = file.read(50000)
rows = []
for corner in ['Slow', 'Fast']:
    for check in ['Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width']:
        pattern = re.escape(f'{check} Summary({corner} Corner):') + r'\s*(.*?)(?=\n=+)'
        section = re.search(pattern, text, re.S)
        if section is None:
            raise RuntimeError(f'missing summary: {corner}/{check}')
        values = []
        for line in section.group(1).splitlines():
            match = re.search(r'\s(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', line)
            if match:
                values.append({'wns_ns': float(match[1]), 'tns_ns': float(match[2]), 'failed_endpoints': int(match[3]), 'total_endpoints': int(match[4]), 'line': line.strip()})
        if not values:
            raise RuntimeError(f'empty timing class: {corner}/{check}')
        rows.append({'corner': corner, 'check': check, 'paths': values,
                     'pass': all(v['wns_ns'] >= 0 and v['tns_ns'] == 0 and v['failed_endpoints'] == 0 for v in values)})
passed = all(row['pass'] for row in rows)
prr = root / 'place_route/o2_pds_top.prr'
report = prr.read_text(errors='replace')
luts = [int(v) for v in re.findall(r'^\|\s+LUT\s+\|\s*(\d+)\s*\|', report, re.M)][:2]
if len(luts) != 2:
    raise RuntimeError('missing CLMA/CLMS LUT utilization')
result = {'status': 'TIMING_PASS' if passed else 'TIMING_FAIL', 'all_checks_pass': passed,
          'classes': rows, 'lut_clma_clms': sum(luts), 'rtr_sha256': hashlib.sha256(rtr.read_bytes()).hexdigest(),
          'prr_sha256': hashlib.sha256(prr.read_bytes()).hexdigest(), 'timing_models': 'Pre-silicon',
          'clock_summary': text[text.index(' Clock Summary:'):text.index(' Clock Groups:')]}
for name in ['top.v', 'full_flow.tcl', '../common/program.hex', '../common/mini162.fdc', 'place_route/o2_pds_top_pnr.adf']:
    p = root / name
    if not p.is_file():
        raise RuntimeError(f'missing binding artifact: {p}')
    result.setdefault('artifact_sha256', {})[name] = hashlib.sha256(p.read_bytes()).hexdigest()
# round 2: the generated clock under test is named on the command line
clock = re.search(r'^\s+' + re.escape(sys.argv[2]) + r'\s+(\d+\.\d+)\s+', text, re.M)
if clock is None:
    raise RuntimeError('missing requested clock ' + sys.argv[2])
result['clock_name'] = sys.argv[2]
result['clock_period_ns'] = float(clock[1])
bit = root / 'generate_bitstream/o2_pds_top.sbit'
if bit.is_file():
    generation = root / 'generate_bitstream/o2_pds_top.bgr'
    generated = generation.read_text(errors='replace')
    if 'Generating Programming File done.' not in generated or (root/'place_route/o2_pds_top_pnr.adf').as_posix() not in generated.replace('\\','/'):
        raise RuntimeError('missing bitstream generation / PNR DB binding')
    result['artifact_sha256']['generate_bitstream/o2_pds_top.bgr'] = hashlib.sha256(generation.read_bytes()).hexdigest()
    result['bitstream_sha256'] = hashlib.sha256(bit.read_bytes()).hexdigest()
route_log = (root/'place_route/run.log').read_text(errors='replace')
routing = re.findall(r'Total net:\s*(\d+), route succeed net:\s*(\d+)',route_log)
if not routing or routing[-1][0] != routing[-1][1]:
    raise RuntimeError('missing final all-nets-routed result')
result['routed_nets'] = int(routing[-1][0])
result['io_boundary'] = 'Internal multi-corner STA. key0_n/uart_tx/led external IO have no external delay constraints in inherited FDC.'
(root / 'timing_assessment.json').write_text(json.dumps(result, indent=2))
print(result['status'], 'classes', len(rows), 'LUT', sum(luts))
raise SystemExit(0 if passed else 1)
