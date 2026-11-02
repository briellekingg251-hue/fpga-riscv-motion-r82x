"""Build isolated round2 board images; original benchmark algorithms and CPU RTL stay intact."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
OLD = Path('F:/Codex_workplace/cpu_ooo_fulltest_20261011')
SNAP = OLD / 'round2_candidate/repo'
GCCBIN = Path('F:/Codex_workplace/tools/xpack-riscv-none-elf-gcc-15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1/bin')
GCC = GCCBIN / 'riscv-none-elf-gcc.exe'
SV2V = Path('F:/Codex_workplace/tools/sv2v-v0.0.13/sv2v-Windows/sv2v.exe')
HZ = 169714286
DIVISOR = round(HZ / 115200)
FLAGS = '-march=rv32i_zmmul_zbc -mabi=ilp32 -mno-relax -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -ffunction-sections -fdata-sections -O3 -mtune=sifive-7-series -funroll-all-loops'.split()


def sha(path: Path | str) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(cmd: list, log: Path | None = None, cwd: Path = ROOT) -> None:
    with (open(log, 'w') if log else open(ROOT / 'last_command.log', 'a')) as stream:
        stream.write(json.dumps([str(c) for c in cmd]) + '\n')
        stream.flush()
        subprocess.run([str(c) for c in cmd], cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, check=True)


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError('configuration template drift: ' + old)
    return text.replace(old, new)


def safe_child(base: Path, rel: str) -> Path:
    part = Path(rel)
    if part.drive or part.root or part.anchor or '..' in part.parts:
        raise RuntimeError('manifest outside source tree')
    target = (base / part).resolve()
    if not target.is_relative_to(base.resolve()) or target == base.resolve():
        raise RuntimeError('resolved manifest path outside source tree')
    return target


def seal() -> None:
    frozen_path = ROOT / 'frozen_source_manifest.json'
    if not frozen_path.exists():
        shutil.copy2(ROOT / 'source_manifest.json', frozen_path)
    records = json.loads(frozen_path.read_text())
    actual = []
    config_name = 'ooo/pds/src/soc_config.vh'
    for entry in records:
        rel = entry['path']
        src, dst = safe_child(SNAP, rel), safe_child(ROOT / 'source', rel)
        if sha(src) != entry['sha256']:
            raise RuntimeError('frozen source drift: ' + rel)
        expected = src.read_bytes()
        if rel == config_name:
            text = src.read_text()
            text = replace_once(text, "`define CLOCK_HZ 32'h09a7ec80", f"`define CLOCK_HZ 32'h{HZ:08x}")
            text = replace_once(text, "`define UART_DIVISOR 32'h0000057e", f"`define UART_DIVISOR 32'h{DIVISOR:08x}")
            expected = text.replace('\r\n', '\n').encode()
        if dst.read_bytes() != expected:
            raise RuntimeError('source differs from authorized config overlay: ' + rel)
        actual.append(dict(path=rel, sha256=sha(dst), frozen_sha256=entry['sha256']))
    (ROOT / 'source_manifest.json').write_text(json.dumps(actual, indent=2))
    validate_sources()


def validate_sources() -> None:
    for entry in json.loads((ROOT / 'source_manifest.json').read_text()):
        if sha(safe_child(ROOT / 'source', entry['path'])) != entry['sha256']:
            raise RuntimeError('actual source drift: ' + entry['path'])
    cfg = (ROOT / 'firmware/src/soc_config.h').read_text()
    for name, value in [('CLOCK_HZ', HZ), ('UART_DIVISOR', DIVISOR)]:
        matches = re.findall(r'^#define ' + name + r' (\d+)u$', cfg, re.M)
        if matches != [str(value)]:
            raise RuntimeError('firmware clock configuration drift: ' + name)
    for name, expected in json.loads((ROOT / 'firmware/coremark_core_sha256.json').read_text()).items():
        if sha(ROOT / 'firmware/src' / name) != expected:
            raise RuntimeError('official CoreMark core changed: ' + name)


def init() -> None:
    repo = ROOT / 'source'
    repo.mkdir(exist_ok=False)
    records = []
    for line in (OLD / 'round2_candidate/source_sha256.txt').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64}) \*(.+)', line)
        if not match:
            raise RuntimeError('invalid source manifest')
        expected, rel = match.groups()
        prefix = '/f/Codex_workplace/cpu_ooo_fulltest_20261011/round2_candidate/repo/'
        if rel.startswith(prefix):
            rel = rel[len(prefix):]
        src, dst = safe_child(SNAP, rel), safe_child(repo, rel)
        if sha(src) != expected:
            raise RuntimeError('frozen source drift: ' + rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        if sha(dst) != expected:
            raise RuntimeError('copy drift: ' + rel)
        records.append(dict(path=rel, sha256=expected))
    (ROOT / 'source_manifest.json').write_text(json.dumps(records, indent=2))
    shutil.copytree(OLD / 'fw_official/src', ROOT / 'firmware/src')
    config = ROOT / 'firmware/src/soc_config.h'
    text = replace_once(config.read_text(), '#define CLOCK_HZ 162000000u', f'#define CLOCK_HZ {HZ}u')
    text = replace_once(text, '#define UART_DIVISOR 1406u', f'#define UART_DIVISOR {DIVISOR}u')
    config.write_text(text, newline='\n')
    corefiles = ['core_list_join.c', 'core_main.c', 'core_matrix.c', 'core_state.c', 'core_util.c', 'coremark.h']
    bound = {n: sha(ROOT / 'firmware/src' / n) for n in corefiles}
    if not all(bound[n] == sha(OLD / 'fw_official/src' / n) for n in corefiles):
        raise RuntimeError('CoreMark copy drift')
    (ROOT / 'firmware/coremark_core_sha256.json').write_text(json.dumps(bound, indent=2))
    for tool in ['elf_to_hex.py', 'round2_timing_clock.py', 'capture_uart.ps1', 'run_job.py']:
        (ROOT / 'tools').mkdir(exist_ok=True)
        shutil.copy2(OLD / 'tools' / tool, ROOT / 'tools' / tool)
    # Only the copied board configuration changes. All CPU RTL remains hash identical.
    cfg = repo / 'ooo/pds/src/soc_config.vh'
    text = replace_once(cfg.read_text(), "`define CLOCK_HZ 32'h09a7ec80", f"`define CLOCK_HZ 32'h{HZ:08x}")
    text = replace_once(text, "`define UART_DIVISOR 32'h0000057e", f"`define UART_DIVISOR 32'h{DIVISOR:08x}")
    cfg.write_text(text, newline='\n')
    seal()
    print('SOURCE_FREEZE_PASS', len(records), 'Hz', HZ, 'UART divisor', DIVISOR)


def firmware(mode: str, iterations: int) -> None:
    validate_sources()
    out = ROOT / 'firmware' / f'{mode}_{iterations}'
    out.mkdir(exist_ok=False)
    source = ROOT / 'firmware/src'
    define = 'VALIDATION_RUN' if mode == 'validation' else 'PERFORMANCE_RUN'
    if mode == 'ila':
        source = ROOT / 'firmware' / f'ila_src_{iterations}'
        shutil.copytree(ROOT / 'firmware/src', source)
        port = source / 'core_portme.c'
        text = port.read_text()
        anchor = '    p->portable_id = 1;'
        if (ROOT / 'board_prelude.c').is_file():
            shutil.copy2(ROOT / 'board_prelude.c', source / 'board_prelude.c')
            text = replace_once(text, anchor, '    extern void board_prelude(void);\n    board_prelude();\n' + anchor)
        else:
            text = replace_once(text, anchor, '    p1_uart_puts("ILA_WAIT_60_SECONDS\\n");\n    p1_uart_flush();\n    unsigned long long deadline = p1_timer_read() + 60ull * CLOCK_HZ;\n    while (p1_timer_read() < deadline) {}\n    p1_uart_puts("ILA_START\\n");\n    p1_uart_flush();\n' + anchor)
        port.write_text(text, newline='\n')
    objects = []
    if mode == 'ila' and (ROOT / 'board_traps.S').is_file():
        shutil.copy2(ROOT / 'board_traps.S', source / 'board_traps.S')
    source_inputs = {x.name: sha(x) for x in source.iterdir() if x.is_file()}
    (out / 'build_inputs.json').write_text(json.dumps(source_inputs, indent=2))
    for src in sorted(source.glob('*.c')) + [source / 'start.S']:
        obj = out / (src.name + '.o')
        run([GCC, *FLAGS, '-DCOMPILER_FLAGS="' + ' '.join(FLAGS) + '"', '-I' + str(source), '-DMULTITHREAD=1', '-DMAIN_HAS_NOARGC=1', '-DMEM_METHOD=MEM_STATIC', '-DTOTAL_DATA_SIZE=2000', f'-DITERATIONS={iterations}', f'-D{define}=1', '-c', src, '-o', obj])
        objects.append(obj)
    if mode == 'ila' and (ROOT / 'board_traps.S').is_file():
        obj = out / 'board_traps.S.o'
        run([GCC, *FLAGS, '-march=rv32i_zmmul_zbc_zicsr_zifencei', '-c', source / 'board_traps.S', '-o', obj])
        objects.append(obj)
    elf = out / 'coremark.elf'
    run([GCC, *FLAGS, '-nostdlib', '-nostartfiles', '-nodefaultlibs', '-Wl,--gc-sections', '-T', source / 'link.ld', *objects, '-lm', '-lgcc', '-o', elf])
    run([sys.executable, ROOT / 'tools/elf_to_hex.py', elf, out / 'program.hex'])
    run([GCCBIN / 'riscv-none-elf-nm.exe', '-S', '--size-sort', elf], out / 'symbols.txt')
    run([GCC, '--version'], out / 'compiler.txt')
    if any(sha(source / name) != expected for name, expected in source_inputs.items()):
        raise RuntimeError('firmware inputs changed during compilation')
    (out / 'build.json').write_text(json.dumps(dict(mode=mode, iterations=iterations, nominal_hz=HZ, uart_divisor=DIVISOR, flags=FLAGS, elf_sha256=sha(elf), hex_sha256=sha(out / 'program.hex'), compiler_sha256=sha(GCC), source_inputs_sha256=sha(out / 'build_inputs.json'), source_directory=str(source)), indent=2))
    print('FIRMWARE_BUILT', mode, iterations)


def native(mode: str, iterations: int, seed: int, override_name: str | None = None) -> None:
    validate_sources()
    name = override_name or f'{mode}_{iterations}_s{seed}'
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        raise RuntimeError('invalid run name')
    firmware_dir = ROOT / 'firmware' / f'{mode}_{iterations}'
    build = json.loads((firmware_dir / 'build.json').read_text())
    if build['mode'] != mode or build['iterations'] != iterations or build['hex_sha256'] != sha(firmware_dir / 'program.hex') or build['elf_sha256'] != sha(firmware_dir / 'coremark.elf'):
        raise RuntimeError('firmware build identity mismatch')
    out = ROOT / 'pds' / name
    candidate, common = out / 'candidate', out / 'common'
    candidate.mkdir(parents=True, exist_ok=False)
    common.mkdir()
    r, b, p = [ROOT / 'source' / x for x in ['ooo/rtl', 'baseline/src', 'ooo/pds/src']]
    modules = 'o2_bitram o2_decode o2_icache o2_frontend o2_iq o2_prf o2_rename o2_lsu o2_rob o2_core o2_soc'.split()
    sources = [r / (n + '.sv') for n in modules] + [b / (n + '.sv') for n in ['p2_burst_arbiter2', 'p2_burst_sram', 'p2_peripherals']] + [p / 'o2_pds_top.sv']
    with (candidate / 'top.v').open('w') as stream, (candidate / 'sv2v.log').open('w') as log:
        subprocess.run([str(SV2V), '-DSYNTHESIS', '-I' + str(p), '-I' + str(r), '-I' + str(b), *map(str, sources)], stdout=stream, stderr=log, check=True)
    with (candidate / 'top.v').open('a') as stream:
        stream.write((p / 'p7_board_pll.v').read_text())
    top = (candidate / 'top.v').read_text()
    for old, new in [('PLL_RATIOF = 36.0', 'PLL_RATIOF = 44.0'), ('PLL_RATIO0 = 6.0', 'PLL_RATIO0 = 7.0'), ('PLL_DUTY0 = 6', 'PLL_DUTY0 = 7'), ('PLL_DUTYF = 36', 'PLL_DUTYF = 44')]:
        top = replace_once(top, old, new)
    (candidate / 'top.v').write_text(top, newline='\n')
    shutil.copy2(ROOT / 'firmware' / f'{mode}_{iterations}/program.hex', common / 'program.hex')
    fdc = (SNAP / 'repo/release162/constraints/mini162.fdc').read_text().replace('-name {clk162}', '-name {clk170}').replace('-multiply_by {162} -divide_by {27}', '-multiply_by {44} -divide_by {7}')
    if fdc.count('-multiply_by {44} -divide_by {7}') != 1:
        raise RuntimeError('generated-clock configuration mismatch')
    (common / 'mini162.fdc').write_text(fdc, newline='\n')
    flow = f'''set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
add_design {{top.v}}
add_constraint -logic -fdc {{../common/mini162.fdc}}
compile -top_module o2_pds_top
synthesize -ads -selected_syn_tool_opt 2 -frequency 170 -fanout_guide 64
dev_map
pnr -gplace_seed {seed} -groute_seed {seed} -number_of_router_thread 4
report_timing -delay_type min_max -max_path 3000 -nworst 1
gen_bit_stream
'''
    (candidate / 'full_flow.tcl').write_text(flow, newline='\n')
    (candidate / 'input_binding.json').write_text(json.dumps(dict(mode=mode, iterations=iterations, seed=seed, nominal_clock_hz=27e6 * 44 / 7, top_sha256=sha(candidate / 'top.v'), program_sha256=sha(common / 'program.hex'), fdc_sha256=sha(common / 'mini162.fdc'), source_manifest_sha256=sha(ROOT / 'source_manifest.json'), firmware_build_sha256=sha(firmware_dir / 'build.json')), indent=2))
    print('NATIVE_PREPARED', candidate)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['init', 'seal', 'firmware', 'native'])
    parser.add_argument('--mode', default='performance', choices=['performance', 'validation', 'ila'])
    parser.add_argument('--iterations', type=int, default=13000)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--name')
    args = parser.parse_args()
    if args.action == 'init':
        init()
    elif args.action == 'seal':
        seal()
    elif args.action == 'firmware':
        firmware(args.mode, args.iterations)
    else:
        native(args.mode, args.iterations, args.seed, args.name)
