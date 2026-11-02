"""Emit n111116 delay-compensated ROMs and independently invert every word."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

def signed(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('export', type=Path)
    args = ap.parse_args()
    root = args.export
    layers = json.loads((root / 'layers.json').read_text())['layers']
    plans = json.loads((root / 'stream_chained_plan.json').read_text())['layers']
    params = np.load(root / 'params.npz')
    out = root / 'systolic'
    out.mkdir(exist_ok=True)
    report = []
    for layer, plan in zip(layers, plans):
        i = layer['index']
        assert i == plan['index']
        w = params[f'w{i}'].astype(np.int64)
        b = params[f'b{i}'].astype(np.int64)
        pages, cols = plan['pe_page'], plan['pe_col']
        ci, co = plan['cycle_period_in'], plan['cycle_period_out']
        rows = layer['kernel'] ** 2
        period = ci * co
        assert pages * ci == layer['cin'] and cols * co == layer['cout']
        files = []
        for p in range(pages):
            path = out / f'weight_layer{i}_page{p}.mem'
            with path.open('w') as f:
                for t in range(period):
                    for c in range(cols):
                        values = []
                        for r in reversed(range(rows)):
                            phase = (t - r - c) % period
                            values.append(int(w[c*co + phase%co, p*ci + phase//co,
                                                r//layer['kernel'], r%layer['kernel']]))
                        f.write(''.join(f'{v & 255:08b}' for v in values) + '\n')
            # Decode on-disk ROM addresses into original tensor coordinates.
            words = path.read_text().splitlines()
            seen = set()
            for address, bits in enumerate(words):
                t, c = divmod(address, cols)
                word = int(bits, 2)
                for r in range(rows):
                    phase = (t-r-c) % period
                    oc, ic = c*co + phase%co, p*ci + phase//co
                    actual = signed((word >> (8*r)) & 255, 8)
                    assert actual == w[oc, ic, r//layer['kernel'], r%layer['kernel']]
                    seen.add((oc, ic, r))
            assert len(seen) == cols*co*ci*rows
            files.append({'path': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        path = out / f'bias_layer{i}.mem'
        with path.open('w') as f:
            for t in range(co):
                for c in range(cols):
                    f.write(f'{int(b[c*co + (t-c)%co]) & 0xffffffff:032b}\n')
        for address, bits in enumerate(path.read_text().splitlines()):
            t, c = divmod(address, cols)
            assert signed(int(bits, 2), 32) == b[c*co + (t-c)%co]
        # Worst-case uint8 input, with real signed weights and bias.
        flat = w.reshape(layer['cout'], -1)
        lo = b + 255 * np.minimum(flat, 0).sum(axis=1)
        hi = b + 255 * np.maximum(flat, 0).sum(axis=1)
        assert lo.min() >= -(1 << 31) and hi.max() < (1 << 31)
        report.append({'index': i, 'src': layer['src'], 'plan': plan,
                       'acc_width': 32, 'bias_width': 32, 'weight_width': 8,
                       'acc_min': int(lo.min()), 'acc_max': int(hi.max()),
                       'shift': layer['shift'], 'signed_output': layer['out_signed'],
                       'rom_roundtrip': 'PASS', 'weights': files,
                       'bias_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (out / 'manifest.json').write_text(json.dumps({'layers': report,
        'rom_roundtrip': 'PASS', 'rtl_equivalence': 'NOT_RUN',
        'source_params_sha256': hashlib.sha256((root/'params.npz').read_bytes()).hexdigest()}, indent=2)+'\n')
    print(f'{root.parent.name}: {len(report)} layers ROM_ROUNDTRIP_PASS ACC32_BOUND_PASS')

if __name__ == '__main__':
    main()
