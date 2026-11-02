"""Build a deterministic APM site overlay from the routed R30 template.

The R30 database is the only routed build of the unchanged pose/detector
networks.  Its APM sites are reused except where they fall inside the larger
O2 CPU rectangle; those chains are re-packed upward inside the same columns.
The overlay only pins platform APMs.  CPU APMs remain region-placed by PDS.

usage: make_apm_site_overlay.py <mapped fn_top.pcf> <out.pcf> <report.json>
"""
from pathlib import Path
import collections
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'evidence'
R30_EXPORTS = [EVIDENCE / 'o2_r30_apm_groups_readonly01/placed_sites.pcf',
               EVIDENCE / 'o2_r30_native_placement_readonly01/placed_sites.pcf']
INVENTORY = EVIDENCE / 'o2_device_resource_inventory01/APM.txt'
# APM columns inside the CPU rectangle (0,114,*) and the highest APM row that
# may belong to cpu_region (0..80).  Rows 462 and 492 are both reserved so the
# platform never depends on the unproven boundary row conversion.
CPU_COLUMNS = {65, 161, 311}
CPU_MAX_ROW = 492
TOP_MIN_ROW = 522
RIGHT_MIN_COLUMN = 359
CHAIN_RE = re.compile(r'^(?P<chain>.*\.column\[\d+\])\.tap\[(?P<tap>\d+)\]\.cell_pe/N3/gopapm$')
SITE_RE = re.compile(r'^def_inst_site \{(?P<inst>[^}]+)\} APM_(?P<x>\d+)_(?P<y>\d+) XAPM_CORE_(?P<core>[UD])')

# Columns re-packed from row 522 upward.  Every chain keeps its R30 column and
# vertical order and moves by at most two sites; 'site' entries keep the R30
# D/U sharing of single-tap PEs.
TAP0 = '/dot/page[0].column[%d].tap[0].cell_pe/N3/gopapm'
REPACK = {
    65: [('chain', 'u_pose/ai/det_net/layer6/dot/page[0].column[1]'),
         ('chain', 'u_pose/ai/det_net/layer6/dot/page[0].column[0]'),
         ('chain', 'u_pose/ai/det_net/layer8/dot/page[0].column[0]'),
         ('chain', 'u_pose/ai/det_net/layer5/dot/page[0].column[0]'),
         ('chain', 'u_pose/ai/pose_net/layer12/dot/page[0].column[1]'),
         ('chain', 'u_pose/ai/pose_net/layer12/dot/page[0].column[2]'),
         ('site', {'D': 'u_sys/u_gpu/gpu/u_raster/N84_m1/gopapm', 'U': 'u_sys/u_gpu/gpu/u_raster/N84_m2/gopapm'}),
         ('site', {'D': 'u_sys/u_gpu/gpu/u_raster/N81_m1/gopapm', 'U': 'u_sys/u_gpu/gpu/u_raster/N81_m2/gopapm'}),
         ('site', {'D': 'u_sys/u_gpu/gpu/u_raster/N259/gopapm', 'U': 'u_sys/u_gpu/gpu/u_raster/N256/gopapm'})],
    161: [('chain', 'u_pose/ai/det_net/layer8/dot/page[0].column[1]'),
          ('chain', 'u_pose/ai/det_net/layer7/dot/page[0].column[0]'),
          ('chain', 'u_pose/ai/det_net/layer1/dot/page[0].column[0]'),
          ('chain', 'u_pose/ai/det_net/layer3/dot/page[0].column[0]'),
          ('chain', 'u_pose/ai/pose_net/layer12/dot/page[0].column[0]')],
    311: [('chain', 'u_pose/ai/det_net/layer7/dot/page[0].column[1]'),
          ('site', {'D': 'u_pose/ai/det_net/layer10' + TAP0 % 0, 'U': 'u_pose/ai/pose_net/layer14' + TAP0 % 0}),
          ('site', {'D': 'u_pose/ai/pose_net/layer13' + TAP0 % 0, 'U': 'u_pose/ai/pose_net/layer13' + TAP0 % 1}),
          ('chain', 'u_pose/ai/det_net/layer2/dot/page[0].column[0]'),
          ('chain', 'u_pose/ai/det_net/layer0/dot/page[0].column[0]'),
          ('chain', 'u_pose/ai/det_net/layer4/dot/page[0].column[0]')],
}
# Singles that shared a chain-end site in R30 follow that chain end (free U core
# beside tap 8).  The VIEW post filter is new and takes the free D core next to
# the R30 post filter.
CHAIN_END_U = {
    'u_pose/ai/det_net/layer9' + TAP0 % 0: 'u_pose/ai/det_net/layer6/dot/page[0].column[1]',
    'u_pose/ai/pose_net/layer14' + TAP0 % 2: 'u_pose/ai/det_net/layer8/dot/page[0].column[1]',
    'u_pose/ai/pose_net/layer14' + TAP0 % 1: 'u_pose/ai/det_net/layer7/dot/page[0].column[1]',
    'u_pose/ai/N820/gopapm': 'u_pose/ai/det_net/layer7/dot/page[0].column[0]',
    'u_pose/ai/N835/gopapm': 'u_pose/ai/det_net/layer1/dot/page[0].column[0]',
    'u_pose/ai/N833/gopapm': 'u_pose/ai/det_net/layer2/dot/page[0].column[0]',
    'u_pose/ai/N817/gopapm': 'u_pose/ai/det_net/layer0/dot/page[0].column[0]',
}
NEW_SITES = {'u_pose/mmio/post_view/N3/gopapm': (461, 336, 'D')}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def main():
    mapped, out, report_path = (Path(a) for a in sys.argv[1:4])
    columns = collections.defaultdict(list)
    for line in INVENTORY.read_text().splitlines():
        m = re.fullmatch(r'APM_(\d+)_(\d+)', line.strip())
        if m:
            columns[int(m[1])].append(int(m[2]))
    for x in columns:
        columns[x].sort()
    require(sum(map(len, columns.values())) == 370, 'APM inventory changed')

    regions = {}
    for line in mapped.read_text().splitlines():
        if line.startswith('def_inst_region {') and line.split('}', 1)[0].endswith('/gopapm'):
            inst = line.split('{', 1)[1].split('}', 1)[0]
            require(inst not in regions, 'Duplicate mapped APM region: ' + inst)
            regions[inst] = line.rsplit(' ', 1)[1]
    require(len(regions) == 556, 'Mapped APM count changed: %d' % len(regions))
    targets = {i: r for i, r in regions.items() if not i.startswith('u_sys/u_cpu/')}
    require(len(targets) == 552 and all(r == 'cpu_region' for i, r in regions.items() if i not in targets),
            'CPU/platform APM split changed')

    template = {}
    for export in R30_EXPORTS:
        for line in export.read_text().splitlines():
            m = SITE_RE.match(line)
            if m and not m['inst'].startswith('u_sys/u_cpu/'):
                site = (int(m['x']), int(m['y']), m['core'])
                require(template.get(m['inst'], site) == site, 'R30 exports disagree: ' + m['inst'])
                template[m['inst']] = site

    assigned = {}
    groups = collections.defaultdict(dict)
    for inst in targets:
        m = CHAIN_RE.match(inst)
        if m:
            groups[m['chain']][int(m['tap'])] = inst
    chains = {name: taps for name, taps in groups.items() if len(taps) == 9}
    require(len(chains) == 57 and all(sorted(t) == list(range(9)) for t in chains.values()) and
            all(sorted(t) == [0] for name, t in groups.items() if name not in chains) and
            len(groups) - len(chains) == 7, 'Cascade/single-tap PE structure changed')

    def place_chain(chain, x, base_index):
        for tap, inst in chains[chain].items():
            assigned[inst] = (x, columns[x][base_index + tap // 2], 'D' if tap % 2 == 0 else 'U')

    repacked = set()
    for x, items in REPACK.items():
        index = columns[x].index(TOP_MIN_ROW)
        for kind, value in items:
            if kind == 'chain':
                require(value in chains and template[chains[value][0]][0] == x,
                        'Re-packed chain must exist and keep its R30 column: ' + value)
                place_chain(value, x, index)
                repacked.add(value)
                index += 5
            else:
                for core, inst in value.items():
                    require(inst in targets and inst not in assigned, 'Bad re-packed single: ' + inst)
                    assigned[inst] = (x, columns[x][index], core)
                index += 1
    for chain, taps in chains.items():
        if chain in repacked:
            continue
        x, y, core = template[taps[0]]
        require(core == 'D', 'R30 chain head is not a D core: ' + chain)
        place_chain(chain, x, columns[x].index(y))
        for tap, inst in taps.items():
            require(assigned[inst] == template[inst], 'R30 chain is not contiguous: ' + inst)
    for inst, chain in CHAIN_END_U.items():
        require(inst in targets and inst not in assigned, 'Bad chain-end single: ' + inst)
        x, y, core = assigned[chains[chain][8]]
        assigned[inst] = (x, y, 'U')
    for inst in targets:
        if inst in assigned:
            continue
        site = NEW_SITES.get(inst) or template.get(inst)
        require(site is not None, 'No template site for ' + inst)
        assigned[inst] = site
    require(set(assigned) == set(targets), 'Assignment does not cover every platform APM')

    used = collections.Counter(assigned.values())
    require(all(n == 1 for n in used.values()), 'APM core assigned twice')
    moved = sorted(i for i in assigned if template.get(i) != assigned[i])
    region_issues = []
    for inst, (x, y, core) in assigned.items():
        require(y in columns.get(x, []), 'Unknown APM site for ' + inst)
        require(not (x in CPU_COLUMNS and y <= CPU_MAX_ROW), 'Platform APM inside CPU rectangle: ' + inst)
        region = targets[inst]
        right_ok = x >= RIGHT_MIN_COLUMN
        top_ok = y >= TOP_MIN_ROW
        ok = {'platform_right': right_ok, 'crop_region': right_ok, 'platform_top': top_ok,
              'platform_left_top': top_ok and x in CPU_COLUMNS}.get(region)
        if not ok:
            region_issues.append({'inst': inst, 'region': region, 'site': [x, y, core]})
    require(not region_issues, 'Pinned sites disagree with mapped regions: ' + json.dumps(region_issues[:5]))

    lines = ['# Claude R48 APM site overlay: R30 routed template, CPU rectangle rows <=%d excluded' % CPU_MAX_ROW]
    lines += ['def_inst_site {%s} APM_%d_%d XAPM_CORE_%s' % (inst, *assigned[inst]) for inst in sorted(assigned)]
    out.write_text('\n'.join(lines) + '\n')
    free = {x: [y for y in ys if not any((x, y, c) in used for c in 'UD')] for x, ys in columns.items()}
    report = {
        'status': 'PASS_STATIC_APM_OVERLAY',
        'mapped_pcf': str(mapped), 'mapped_pcf_sha256': sha(mapped),
        'template_exports': {str(p): sha(p) for p in R30_EXPORTS}, 'inventory_sha256': sha(INVENTORY),
        'tool_sha256': sha(__file__), 'overlay': str(out), 'overlay_sha256': sha(out),
        'pinned_platform_APMs': len(assigned), 'chains': len(chains), 'single_tap_PEs': len(groups) - len(chains), 'cpu_APMs_left_to_region': 4,
        'moved_from_R30': moved, 'moved_count': len(moved),
        'free_sites_per_column': {str(x): v for x, v in sorted(free.items())},
        'cpu_rectangle_guard': {'columns': sorted(CPU_COLUMNS), 'max_reserved_row': CPU_MAX_ROW},
    }
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(report['status'], len(assigned), 'pinned;', len(moved), 'moved from R30')


if __name__ == '__main__':
    main()
