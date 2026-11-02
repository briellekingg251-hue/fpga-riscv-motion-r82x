"""Per-layer folding plan for an n111116-style streaming engine (CnnHardwareGenerator_pds.py terms).

For each layer pick the smallest pe_page x pe_col (input-channel pages x output-channel
columns, each column = k*k PEs) whose cycle_period = ceil(cin/pe_page) * ceil(cout/pe_col)
fits the per-pixel cycle budget  clk / (fps * out_h * out_w).  Adjacent layers must chain
(prev pe_col == next pe_page, prev cycle_period_out == next cycle_period_in in n111116);
this script only sizes each layer independently -- treat it as a resource estimate.

  python plan_stream.py runs/poseF_plain_s16_body12_board/export_pow2u 100e6 30
"""
import json
import math
import sys
from pathlib import Path


def divisors(n):
    return [d for d in range(1, n + 1) if n % d == 0]


def plan(export_dir, clk, fps):
    meta = json.loads((Path(export_dir) / 'layers.json').read_text())
    rows, tot_pe, tot_w = [], 0, 0
    for L in meta['layers']:
        cin, cout, k = L['cin'] // L['groups'], L['cout'], L['kernel']
        oh, ow = L['out_hw']
        budget = clk / (fps * oh * ow)                    # cycles available per output pixel
        best = None
        for pp in divisors(cin):
            for pc in divisors(cout):
                period = (cin // pp) * (cout // pc)
                if period <= budget:
                    cost = pp * pc
                    if best is None or cost < best[0]:
                        best = (cost, pp, pc, period)
        cost, pp, pc, period = best
        pes = cost * k * k
        tot_pe += pes
        tot_w += cin * cout * k * k
        rows.append(f"{L['index']:>3} {L['type']:<8} {cin:>3}->{cout:<3} {oh:>3}x{ow:<3} budget {budget:7.1f}  "
                    f"pe_page {pp:>2} pe_col {pc:>2} period {period:>4}  PEs {pes:>4}")
    print(f'{export_dir}: {fps} fps @ {clk / 1e6:.0f} MHz')
    print('\n'.join(rows))
    print(f'total PEs (multipliers) {tot_pe}  ~APM if all DSP (2 x 12x9 per APM) {math.ceil(tot_pe / 2)}  '
          f'weights {tot_w} B ~ {math.ceil(tot_w * 8 / 36864)} DRM (36Kb)\n')


if __name__ == '__main__':
    plan(sys.argv[1], float(sys.argv[2]), float(sys.argv[3]))
