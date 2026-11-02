from pathlib import Path
import argparse, json, re

def main():
    parser = argparse.ArgumentParser(description='Check all reported PDS internal timing summary rows.')
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    text = args.report.read_text(errors='replace')
    design = re.search(r'Design Summary\s*:\s*([^\r\n]+)', text)
    if not design:
        raise SystemExit('missing design summary')
    rows, section = [], None
    for line in text.splitlines():
        heading = re.match(r'\s*((?:Setup|Hold|Recovery|Removal|Minimum Pulse Width|Max Delay|Min Delay|Max Skew) Summary\([^)]*\)):', line)
        if heading:
            section = heading[1]
            continue
        if section and line.strip().startswith('==='):
            section = None
        if not section:
            continue
        if section.startswith('Minimum Pulse Width'):
            m = re.match(r'\s*(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', line)
            if m:
                launch, capture, wns, tns, fail, total = m[1], m[1], *m.groups()[1:]
            else:
                continue
        else:
            m = re.match(r'\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', line)
            if not m:
                continue
            launch, capture, wns, tns, fail, total = m.groups()
        rows.append({'section':section, 'launch':launch, 'capture':capture, 'wns_ns':float(wns),
                     'tns_ns':float(tns), 'failing_endpoints':int(fail), 'total_endpoints':int(total)})
    required = {f'{kind} Summary({corner} Corner)' for kind in ('Setup','Hold','Recovery','Removal','Minimum Pulse Width') for corner in ('Slow','Fast')}
    missing = required - {row['section'] for row in rows}
    baseline_path = Path(__file__).resolve().parents[1] / 'release/r82x_s4_ai31_20261022/physical_evidence/timing_assessment.json'
    baseline = json.loads(baseline_path.read_text(encoding='utf-8'))['summary_rows']
    expected = {(r['section'], r['launch'], r['capture']) for r in baseline}
    actual = {(r['section'], r['launch'], r['capture']) for r in rows}
    missing_rows = sorted(expected - actual)
    failed = [row for row in rows if row['wns_ns'] < 0 or row['tns_ns'] < 0 or row['failing_endpoints']]
    result = {'design_summary':design[1].strip(), 'rows':len(rows), 'missing_sections':sorted(missing),
              'missing_baseline_rows':missing_rows, 'failing_rows':failed, 'cpu_setup_slow':[r for r in rows if r['section']=='Setup Summary(Slow Corner)' and r['launch']=='cpu_clk' and r['capture']=='cpu_clk'],
              'scope':'Reported internal STA only; CDC, external IO and board operation require separate validation.'}
    print(json.dumps(result, indent=2))
    if missing or missing_rows or failed or design[1].strip() != 'All Constraints Met.':
        raise SystemExit(1)

if __name__ == '__main__':
    main()
