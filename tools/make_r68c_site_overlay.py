"""R68c site overlay: the R57 overlay without the four u_pose/ai constant-multiplier pins.

Every edit of p2_vision_ai lets synthesis renumber the four small constant
multipliers directly under u_pose/ai (cell index y*12+x / y*10+x feeding the
*3 / *6 result word offsets), which breaks a name-bound pin. R68c therefore
leaves exactly those four 8..11-bit APMs to the placer and keeps every other
pin of make_r57_site_overlay.py's output (R54 overlay minus the two merged
post_view pins) byte for byte. The overlay no longer depends on the renumbered
names, so it is fixed before synthesis. The mapped netlist must prove it:
  * mapped APMs 555 (551 platform), DRMs 415 (357 platform), as R57;
  * the pins name exactly the mapped platform APM/DRM instances except the
    APMs directly under u_pose/ai;
  * those are exactly four, and their configuration signatures in this work's
    synthesis APM report equal the four signatures of the baseline R65-NES
    pins (N817/N820/N833/N835), so nothing else moved off the overlay;
  * every kept CDC-register pin names a mapped instance.

usage: make_r68c_site_overlay.py <mapped fn_top.pcf> <out.pcf> <report.json>
"""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PARENT = ROOT / 'hardware/production_r54_o2_noeth/site_overlay.pcf'
REMOVED = ('u_pose/mmio/post_view/N3/gopapm', 'u_pose/mmio/post_view/lut_1/gopdrm_18k')
UNPINNED_OLD = ('u_pose/ai/N817/gopapm', 'u_pose/ai/N820/gopapm', 'u_pose/ai/N833/gopapm', 'u_pose/ai/N835/gopapm')
MAPPED_APMS, PLATFORM_APMS = 555, 551
MAPPED_DRMS, PLATFORM_DRMS = 415, 357
BASE_REPORT = ROOT / 'physical_production_r65_nes_s1/synthesize/apm_drm_lutram_utilization.log'
HEADER = '# Claude R68c site overlay: R57 overlay without the four u_pose/ai constant-multiplier APM pins'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def inst_of(line):
    return line.split('{', 1)[1].split('}', 1)[0]


def ai_top_apms(report):
    out = {}
    for line in Path(report).read_text(errors='replace').splitlines():
        m = re.match(r'\|\s*(u_pose/ai/N\d+)\s*\|(.*)$', line)
        if m:
            out[m.group(1) + '/gopapm'] = tuple(c.strip() for c in m.group(2).split('|'))
    return out


def overlay_lines():
    parent_meta = json.loads((PARENT.parent / 'ASSEMBLY.json').read_text())
    require(sha(PARENT) == parent_meta['files']['site_overlay.pcf'], 'R54 overlay differs from its assembly')
    parent = [l for l in PARENT.read_text().splitlines() if l.startswith('def_inst_site ')]
    require(len(parent) == parent_meta['APM_site_overlay']['pinned_total'], 'R54 overlay size changed')
    for inst in REMOVED + UNPINNED_OLD:
        require(sum(inst_of(l) == inst for l in parent) == 1, 'Parent overlay lacks ' + inst)
    return [l for l in parent if inst_of(l) not in REMOVED + UNPINNED_OLD]


def main():
    mapped, out, report_path = (Path(a) for a in sys.argv[1:4])
    work = mapped.parent.parent
    kept = overlay_lines()
    base_sig = ai_top_apms(BASE_REPORT)
    require(set(base_sig) == set(UNPINNED_OLD), 'baseline u_pose/ai top APMs: %s' % sorted(base_sig))
    new_sig = ai_top_apms(work / 'synthesize/apm_drm_lutram_utilization.log')
    require(len(new_sig) == 4 and sorted(new_sig.values()) == sorted(base_sig.values()),
            'u_pose/ai top APMs are not the four baseline multipliers: %s' % sorted(new_sig))

    regions = {}
    for line in mapped.read_text().splitlines():
        if line.startswith('def_inst_region {'):
            inst = inst_of(line)
            require(inst not in regions, 'Duplicate mapped region: ' + inst)
            regions[inst] = line.rsplit(' ', 1)[1]
    require(not any(i.startswith('u_pose/mmio/post_view/') for i in regions), 'post_view still mapped')
    apms = {i for i in regions if i.endswith('/gopapm')}
    drms = {i for i in regions if '/gopdrm_' in i}
    platform = {i for i in apms | drms if not i.startswith('u_sys/u_cpu/')}
    require(len(apms) == MAPPED_APMS and len({i for i in apms if i in platform}) == PLATFORM_APMS,
            'Mapped APM count is not R57: %d' % len(apms))
    require(len(drms) == MAPPED_DRMS and len({i for i in drms if i in platform}) == PLATFORM_DRMS,
            'Mapped DRM count is not R57: %d' % len(drms))
    require(set(new_sig) <= platform, 'renumbered multipliers are not mapped platform APMs')
    macro_pins = {inst_of(l) for l in kept if inst_of(l).endswith('/gopapm') or '/gopdrm_' in inst_of(l)}
    require(macro_pins == platform - set(new_sig), 'Pinned macros differ from mapped platform macros: missing %s, extra %s' %
            (sorted(platform - set(new_sig) - macro_pins)[:5], sorted(macro_pins - platform)[:5]))
    other = [inst_of(l) for l in kept if inst_of(l) not in macro_pins]
    require(all(i in regions for i in other), 'A CDC pin names an unmapped instance')

    out.write_text('\n'.join([HEADER] + kept) + '\n')
    report = {'status': 'PASS_STATIC_R68C_OVERLAY', 'mapped_pcf': str(mapped), 'mapped_pcf_sha256': sha(mapped),
              'parent_overlay': str(PARENT), 'parent_overlay_sha256': sha(PARENT), 'tool_sha256': sha(__file__),
              'removed': list(REMOVED), 'unpinned_baseline_names': list(UNPINNED_OLD),
              'unpinned_now': sorted(new_sig), 'signatures': sorted(list(v) for v in new_sig.values()),
              'baseline_report': str(BASE_REPORT), 'baseline_report_sha256': sha(BASE_REPORT),
              'overlay': str(out), 'overlay_sha256': sha(out),
              'pinned_platform_macros': len(macro_pins), 'pinned_CDC_registers': len(other), 'pinned_total': len(kept)}
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(report['status'], len(macro_pins), 'macros +', len(other), 'CDC registers pinned; 4 multipliers placer-chosen')


if __name__ == '__main__':
    main()
