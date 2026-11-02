"""O2 bus / exception regression.

Runs a prebuilt simulator (ooo/sim/build.sh) on directed programs, with and
without injected bus errors and random bus backpressure, and judges every run
fail-closed from its log and uart.txt. Results go to a new output directory
(never reused) with one summary.json.

usage: python regress.py --sim <Vo2_tb.exe> --out <new dir>
                         [--fw-root <dir with fw_official/ and sim/cache_stress/>]
                         [--seeds N] [--jobs N]
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TESTS = REPO / 'tests'
FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
BUSERR_ARGS = ['+ERR_LO=80010000', '+ERR_HI=80010080', '+WERR_LO=80011000', '+WERR_HI=80011020']
BUSERR_UART = 'BUSERR uart under timer irq: 0123456789abcdefghijklmnopqrstuvwxyz\n'
MMIO_IRQ_WRITES = 6000             # GPIO stores in mmio_irq_test.S
COREMARK_CRC = {'performance': [('seedcrc', 'e9f5'), ('crclist', 'e714'), ('crcmatrix', '1fd7'), ('crcstate', '8e3a')],
                'validation': [('seedcrc', '18f2'), ('crclist', 'e3c1'), ('crcmatrix', '0747'), ('crcstate', '8d84')]}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cases(fw_root: Path, seeds: int) -> list:
    """(name, image, plusargs, cycle limit, extra check) for every run."""
    out = []
    directed = ['trap_test', 'fwd_test', 'mul_test', 'md_test']
    for name in directed:
        out.append((name, TESTS / f'{name}.hex', [], 5_000_000, None))
    out.append(('buserr', TESTS / 'buserr_test.hex', BUSERR_ARGS, 40_000_000, ('uart_exact', BUSERR_UART)))
    for beat in (0, 3, 7):          # error on one beat only: first, middle, last
        out.append((f'buserr_beat{beat}', TESTS / 'buserr_test.hex', BUSERR_ARGS + [f'+ERR_BEAT={beat}'],
                    40_000_000, ('uart_exact', BUSERR_UART)))
    out.append(('mmio_irq', TESTS / 'mmio_irq_test.hex', [], 40_000_000, ('gpio_writes', MMIO_IRQ_WRITES)))
    out.append(('headonly_alias', TESTS / 'headonly_alias_test.hex', [], 20_000_000, None))
    cache = fw_root / 'sim/cache_stress/test.hex'
    perf = fw_root / 'fw_official/performance_100/program.hex'
    val = fw_root / 'fw_official/validation_100/program.hex'
    for seed in range(1, seeds + 1):
        stall = [10, 30, 50, 70][seed % 4]
        bus = [f'+STALL={stall}', f'+SEED={seed}']
        for name in directed:
            out.append((f'{name}_s{stall}_{seed}', TESTS / f'{name}.hex', bus, 20_000_000, None))
        out.append((f'buserr_s{stall}_{seed}', TESTS / 'buserr_test.hex', BUSERR_ARGS + bus, 80_000_000,
                    ('uart_exact', BUSERR_UART)))
        out.append((f'mmio_irq_s{stall}_{seed}', TESTS / 'mmio_irq_test.hex', bus, 80_000_000,
                    ('gpio_writes', MMIO_IRQ_WRITES)))
        out.append((f'headonly_alias_s{stall}_{seed}', TESTS / 'headonly_alias_test.hex', bus, 40_000_000, None))
        if cache.exists():
            out.append((f'cache_stress_s{stall}_{seed}', cache, bus, 300_000_000,
                        ('uart_contains', 'CACHE_DIRTY_EVICTION_REFILL_PASS')))
    for name, image in [('performance', perf), ('validation', val)]:
        if image.exists():
            out.append((f'coremark_{name}_s30', image, ['+STALL=30', '+SEED=1'], 300_000_000, ('coremark', name)))
    return out


def judge(log: str, uart: str, check) -> list:
    """Reasons the run failed (empty: pass)."""
    bad = []
    if not re.search(r'O2_EXIT code=1\b', log):
        bad.append('exit code')
    if not re.search(r'COSIM_SUMMARY\b[^\n]*errors=0\b', log):
        bad.append('cosim')
    if re.search(r'MISMATCH|Fatal|DEADLOCK|TIMEOUT', log):
        bad.append('fatal/mismatch')
    if check:
        kind, value = check
        if kind == 'uart_exact' and uart != value:
            bad.append('uart text')
        if kind == 'uart_contains' and value not in uart:
            bad.append('uart marker')
        if kind == 'gpio_writes' and not re.search(rf'O2_MMIO writes=\d+ gpio_writes={value}\b', log):
            bad.append('gpio write count')
        if kind == 'coremark':
            if not all(re.search(rf'{f}\s*: 0x{v}\b', uart) for f, v in COREMARK_CRC[value]):
                bad.append('coremark crc')
    return bad


def run(sim: Path, root: Path, case) -> dict:
    name, image, args, limit, check = case
    wd = root / name
    wd.mkdir(parents=True)
    cmd = [str(sim), f'+INIT_HEX={image}', f'+LIMIT={limit}'] + args
    with (wd / 'log.txt').open('w') as f:
        rc = subprocess.run(cmd, cwd=wd, stdout=f, stderr=subprocess.STDOUT, timeout=3600,
                            creationflags=FLAGS).returncode
    log = (wd / 'log.txt').read_text(errors='replace')
    uart = (wd / 'uart.txt').read_text(errors='replace') if (wd / 'uart.txt').exists() else ''
    bad = judge(log, uart, check) + ([f'returncode {rc}'] if rc else [])
    shim = re.search(r'MEM_SHIM .*', log)
    return {'name': name, 'status': 'FAIL' if bad else 'PASS', 'reasons': bad, 'command': cmd,
            'image_sha256': sha256(image), 'shim': shim.group(0) if shim else None}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('--sim', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--fw-root', type=Path, default=Path('F:/Codex_workplace/cpu_ooo_fulltest_20261011'))
    p.add_argument('--seeds', type=int, default=8)
    p.add_argument('--jobs', type=int, default=6)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=False)
    todo = cases(a.fw_root, a.seeds)
    missing = [str(c[1]) for c in todo if not c[1].exists()]
    if missing:
        print('missing images:', *missing, sep='\n  ')
        return 2
    with ThreadPoolExecutor(max_workers=a.jobs) as pool:
        results = list(pool.map(lambda c: run(a.sim, a.out, c), todo))
    summary = {'simulator_sha256': sha256(a.sim), 'total': len(results),
               'passed': sum(r['status'] == 'PASS' for r in results), 'results': results}
    (a.out / 'summary.json').write_text(json.dumps(summary, indent=2))
    for r in results:
        if r['status'] != 'PASS':
            print('FAIL', r['name'], ', '.join(r['reasons']))
    print(f"O2_REGRESS {summary['passed']} / {summary['total']}")
    return 0 if summary['passed'] == summary['total'] else 1


if __name__ == '__main__':
    sys.exit(main())
