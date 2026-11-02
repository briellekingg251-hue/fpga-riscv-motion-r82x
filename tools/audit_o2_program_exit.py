"""Supplement preserved O2 results with the program's explicit success exit."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/o2_precise_io_regression'


def main():
    destination = OUT / 'PROGRAM_EXIT_AUDIT.json'
    assert not destination.exists()
    original = OUT / 'RESULT.json'
    result = json.loads(original.read_text())
    assert result['status'] == 'PASS' and len(result['cases']) == 74
    rows = []
    for case in result['cases']:
        log = OUT / case['case'] / 'sim.log'
        text = log.read_text()
        exits = re.findall(r'^O2_EXIT code=(\d+)\b.*', text, re.M)
        summaries = re.findall(r'^COSIM_SUMMARY.*', text, re.M)
        assert exits == ['1'], log
        assert len(summaries) == 1 and re.search(r'\berrors=0\b', summaries[0]), log
        assert case['exit'] == 0 and case['status'] == 'PASS'
        assert not re.search(r'MISMATCH|DEADLOCK|Fatal', text), log
        rows.append({'case': case['case'], 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
                     'program_exit': 1, 'status': 'PASS'})
    audit = {'status': 'PASS_74_UNIQUE_PROGRAM_SUCCESS_EXITS', 'cases': rows,
             'original_result_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
             'auditor_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
             'scope': 'Supplement to preserved results; no simulation rerun or original result mutation.'}
    destination.write_text(json.dumps(audit, indent=2))
    print(audit['status'])


if __name__ == '__main__':
    main()
