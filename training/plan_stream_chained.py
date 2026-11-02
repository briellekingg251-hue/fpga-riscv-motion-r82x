"""Arithmetic folding estimate with exact adjacent-channel schedule constraints.

Not an RTL timing, FIFO, DSP packing or RAM utilization certificate.
"""
import argparse
import functools
import json
from pathlib import Path


def plan(meta, clock, fps):
    layers = meta['layers']
    children = {i: [] for i in range(-1, len(layers))}
    for i, layer in enumerate(layers):
        assert layer['index'] == i and layer['groups'] == 1
        children[layer['src']].append(i)

    @functools.lru_cache(None)
    def solve(i, pages):
        layer = layers[i]
        cin, cout = layer['cin'], layer['cout']
        if cin % pages:
            return None
        cycles_in = cin // pages
        budget = clock / (fps * layer['out_hw'][0] * layer['out_hw'][1])
        best = None
        for columns in range(1, cout + 1):
            if cout % columns:
                continue
            cycles_out = cout // columns
            period = cycles_in * cycles_out
            if period > budget:
                continue
            cost = pages * columns * layer['kernel'] ** 2
            rows = [dict(index=i, pe_page=pages, pe_col=columns,
                         cycle_period_in=cycles_in, cycle_period_out=cycles_out,
                         cycle_period=period, multiplier_slots=cost)]
            for child in children[i]:
                assert layers[child]['cin'] == cout
                result = solve(child, columns)
                if result is None:
                    break
                cost += result[0]
                rows += result[1]
            else:
                if best is None or cost < best[0]:
                    best = cost, rows
        return best

    assert children[-1] == [0]
    candidates = [solve(0, p) for p in range(1, layers[0]['cin'] + 1)
                  if layers[0]['cin'] % p == 0]
    valid = [x for x in candidates if x is not None]
    if not valid:
        raise ValueError('No exact chained arithmetic schedule satisfies target')
    cost, rows = min(valid, key=lambda x: x[0])
    rows.sort(key=lambda x: x['index'])
    for row in rows:
        src = layers[row['index']]['src']
        if src >= 0:
            assert rows[src]['pe_col'] == row['pe_page']
            assert rows[src]['cycle_period_out'] == row['cycle_period_in']
    return dict(clock_hz=clock, target_fps=fps, multiplier_slots=cost, layers=rows,
                status='ARITHMETIC_ESTIMATE_ONLY',
                limitations=['No FIFO/backpressure proof', 'No DSP packing proof',
                             'No physical RAM accounting', 'No latency or timing signoff'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('export_dir', type=Path)
    parser.add_argument('--clock', type=float, default=100e6)
    parser.add_argument('--fps', type=float, default=30)
    args = parser.parse_args()
    result = plan(json.loads((args.export_dir / 'layers.json').read_text()), args.clock, args.fps)
    (args.export_dir / 'stream_chained_plan.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
