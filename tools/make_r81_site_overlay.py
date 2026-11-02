"""R81 site overlay: the R68c overlay with the 18 crop APM pins renamed to the R81 synthesis
names (2026-10-22, Claude).

R81 edits p2_crop (zero-row skip), so synthesis renumbers the crop's 18 bilinear APMs:
u_pose/ai/crop/N<k> becomes N<k+35> for every one of them (N595 exists in both netlists but
names different multipliers, so the renaming is applied as one permutation, never string by
string). make_r68c_site_overlay.py runs unchanged (same parent overlay and proofs: pinned
macros == mapped platform macros except the four placer-chosen u_pose/ai multipliers, CDC pins
mapped) with that one substitution: each crop pin keeps its site and takes the new name.
Before that, pin by pin: the configuration row of the old instance in the R80x synthesis report
equals the row of the new instance in this work's synthesis report, including the cascade
partner (renamed by the same permutation). The report keeps the R68c status.

usage: make_r81_site_overlay.py <mapped fn_top.pcf> <out.pcf> <report.json>
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE_TOOL = ROOT / 'tools/make_r68c_site_overlay.py'
OLD_REPORT = ROOT / 'physical_production_r80x_nes_s4/synthesize/apm_drm_lutram_utilization.log'
OLD = [535, 538, 543, 546, 552, 555, 560, 563, 569, 572, 577, 580, 592, 595, 603, 606, 614, 617]
SHIFT = 35
NAME = 'u_pose/ai/crop/N%d'
RENAME = {NAME % k + '/gopapm': NAME % (k + SHIFT) + '/gopapm' for k in OLD}
HEADER = '# Claude R81 site overlay: R68c overlay with the 18 crop APM pins renamed to the R81 names'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def crop_rows(report):
    out = {}
    for line in Path(report).read_text(errors='replace').splitlines():
        m = re.match(r'\|\s*(u_pose/ai/crop/N\d+)\s*\|(.*)$', line)
        if m:
            out[m.group(1)] = [c.strip() for c in m.group(2).split('|')]
    return out


def main():
    spec = importlib.util.spec_from_file_location('r68c_overlay', BASE_TOOL)
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    mapped = Path(sys.argv[1])
    work = mapped.parent.parent
    old_rows = crop_rows(OLD_REPORT)
    new_rows = crop_rows(work / 'synthesize/apm_drm_lutram_utilization.log')
    plain = {k.rsplit('/', 1)[0]: v.rsplit('/', 1)[0] for k, v in RENAME.items()}
    base.require(sorted(old_rows) == sorted(plain), 'R80x crop APMs are not the expected 18: %s' % sorted(old_rows))
    base.require(sorted(new_rows) == sorted(plain.values()), 'R81 crop APMs are not the renamed 18: %s' % sorted(new_rows))
    for old, new in plain.items():
        # one pass: every crop name in the cascade column through the same permutation
        cascade = re.sub(r'u_pose/ai/crop/N\d+', lambda m: plain.get(m.group(0), m.group(0)), old_rows[old][0])
        base.require([cascade] + old_rows[old][1:] == new_rows[new],
                     'crop APM %s -> %s configuration differs: %s vs %s' % (old, new, old_rows[old], new_rows[new]))
    r68c_lines = base.overlay_lines
    renamed = []

    def overlay_lines():
        out = []
        for line in r68c_lines():
            inst = base.inst_of(line)
            if inst in RENAME:
                line = 'def_inst_site {%s} %s' % (RENAME[inst], line.split('} ', 1)[1])
                renamed.append(inst)
            out.append(line)
        base.require(sorted(renamed) == sorted(RENAME), 'R68c overlay does not pin exactly the 18 crop APMs')
        return out

    base.overlay_lines = overlay_lines
    base.HEADER = HEADER
    base.main()
    report_path = Path(sys.argv[3])
    report = json.loads(report_path.read_text())
    report.update(r81_tool=str(Path(__file__)), r81_tool_sha256=sha(__file__), r68c_tool_sha256=sha(BASE_TOOL),
                  r80x_synthesis_report=str(OLD_REPORT), r80x_synthesis_report_sha256=sha(OLD_REPORT),
                  crop_APM_renamed=RENAME)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('R81_OVERLAY', len(RENAME), 'crop APM pins renamed (+%d), signatures equal' % SHIFT)


if __name__ == '__main__':
    main()
