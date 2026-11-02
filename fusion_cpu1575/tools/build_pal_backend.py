"""Build PAL miniSDL input/timing and validate host models plus actual s80 RTL.

The host executable checks API behavior; it is not a PC PAL game executable.
The RV32 smoke executes the actual PAL-Navy input source on the existing CPU.
No complete engine link, game resources, bitstream, or board run is implied.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_fw as cc

OUT = ROOT / 'build/pal_backend'
TCC = Path('F:/Codex_workplace/tools/tcc-0.9.27-win64/tcc/tcc.exe')
IVERILOG = Path('F:/Codex_workplace/tools/iverilog-sd-portable/ucrt64/bin')
NAVY_INCLUDE = ROOT / 'third_party/navy-apps/libs/libminiSDL/include'
PAL_INPUT = ROOT / 'third_party/pal-navy/src/device/input.c'
SOURCES = [ROOT / 'fw/pal/pal_sdl_event.c', ROOT / 'fw/pal/pal_sdl_timer.c',
           ROOT / 'fw/pal/pal_touch.c']
INCLUDES = ['-I' + str(ROOT / 'fw'), '-I' + str(NAVY_INCLUDE),
            '-I' + str(ROOT / 'third_party/pal-navy/include'),
            '-I' + str(ROOT / 'third_party/navy-apps/libs/libfixedptc/include')]
DEFINES = ['-D__NAVY__', '-DPAL_CLASSIC=1']


def run(command: list[object], name: str, env: dict[str, str] | None = None,
        timeout: int = 120) -> str:
    try:
        result = subprocess.run([str(arg) for arg in command], cwd=ROOT, env=env,
                                capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ''
        stderr = exc.stderr or ''
        if isinstance(stdout, bytes):
            stdout = stdout.decode('utf-8', errors='replace')
        if isinstance(stderr, bytes):
            stderr = stderr.decode('utf-8', errors='replace')
        (OUT / (name + '.log')).write_text(stdout + stderr +
                                         f'\nTIMEOUT after {timeout} seconds\n', encoding='utf-8')
        raise
    log = result.stdout + result.stderr
    (OUT / (name + '.log')).write_text(log, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'{name} failed ({result.returncode}); {OUT / (name + ".log")}\n{log}')
    return log


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    status_path = OUT / 'status.json'
    # An unsuccessful rerun must not leave a previous PASS as current evidence.
    report = {'status': 'RUNNING', 'isa': 'rv32i_zmmul_zicsr', 'abi': 'ilp32',
              'full_engine_link': 'NOT_RUN', 'full_game_cpu_execution': 'NOT_RUN',
              'board_backend': 'NOT_RUN', 'game_assets': 'NOT_INCLUDED'}
    status_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    try:
        objects = []
        for source in SOURCES:
            obj = OUT / (source.stem + '.o')
            run([cc.GCC, *cc.CFLAGS, '-std=c99', '-Werror', *INCLUDES, '-c', source, '-o', obj], source.stem)
            objects.append(obj)
        input_obj = OUT / 'pal_navy_input.o'
        run([cc.GCC, *cc.CFLAGS, '-std=gnu99', '-Wno-unused-parameter',
             *DEFINES, *INCLUDES, '-c', PAL_INPUT, '-o', input_obj], 'pal_navy_input')
        objects.append(input_obj)
        host = OUT / 'host.exe'
        run([TCC, *DEFINES, *INCLUDES, '-o', host,
             ROOT / 'tests/pal_backend_host.c', SOURCES[2], PAL_INPUT], 'host_build')
        host_log = run([host], 'host_behavior', timeout=20)
        expected = ['PAL_SDL_TIMER_PASS', 'PAL_SDL_TOUCH_EVENTS_PASS',
                    'PAL_SDL_QUEUE_PASS', 'PAL_NAVY_INPUT_REAL_PASS']
        if not all(marker in host_log for marker in expected):
            raise RuntimeError('Host behavior success markers missing')
        elf = OUT / 'cpu.elf'
        run([cc.GCC, *cc.CFLAGS, '-std=gnu99', '-Wno-unused-parameter',
             *DEFINES, *INCLUDES, '-nostdlib', '-nostartfiles',
             '-T', ROOT / 'fw/boot_link.ld', '-Wl,--gc-sections',
             '-Wl,--no-warn-rwx-segments', '-Wl,-Map=' + str(OUT / 'cpu.map'),
             '-o', elf, ROOT / 'fw/start.S', ROOT / 'tests/pal_backend_cpu.c',
             *objects, '-lgcc'], 'cpu_link')
        run([cc.OBJCOPY, '-O', 'binary', elf, OUT / 'cpu.bin'], 'cpu_binary')
        data = (OUT / 'cpu.bin').read_bytes()
        if len(data) > 0x6000:
            raise RuntimeError('CPU smoke exceeds 24 KiB code/data reservation')
        image = bytearray(128 * 1024)
        image[0x18000:0x18000 + len(data)] = data
        (OUT / 'cpu.hex').write_text(''.join(
            f'{int.from_bytes(image[i:i + 4], "little"):08x}\n'
            for i in range(0, len(image), 4)), encoding='ascii')
        env = os.environ.copy()
        env['PATH'] = str(IVERILOG) + os.pathsep + env.get('PATH', '')
        env['TMP'] = env['TEMP'] = str(OUT)
        vvp = OUT / 'cpu.vvp'
        run([IVERILOG / 'iverilog.exe', '-g2012', '-s', 'tb_pal_backend_cpu',
             '-o', vvp, ROOT / 'tests/tb_pal_backend_cpu.v',
             ROOT / 'rtl/cpu/fn_cpu_base.v', ROOT / 'rtl/cpu/fn_soc_ext.v',
             ROOT / 'rtl/cpu/fn_cpu_core.v', ROOT / 'rtl/cpu/fn_mem_split.v'], 'cpu_rtl_compile', env=env)
        # VVP simulates the actual 162,000 cycles in SDL_Delay(1). With a PDS
        # job sharing this host that takes several minutes; TB progress and
        # the independent 600,000-cycle watchdog remain enabled.
        cpu_log = run([IVERILOG / 'vvp.exe', '-i', vvp], 'cpu_behavior', env=env, timeout=600)
        if 'PAL_SDL_BACKEND_S80_PASS' not in cpu_log:
            raise RuntimeError('Actual s80 execution success marker missing')
        evidence_sources = [*SOURCES, ROOT / 'fw/pal/pal_sdl_backend.h', PAL_INPUT,
                            ROOT / 'fw/touch.h', ROOT / 'fw/soc.h',
                            ROOT / 'tests/pal_backend_host.c', ROOT / 'tests/pal_backend_cpu.c',
                            ROOT / 'tests/tb_pal_backend_cpu.v', Path(__file__).resolve(),
                            ROOT / 'fw/start.S', ROOT / 'fw/boot_link.ld', ROOT / 'tools/build_fw.py',
                            ROOT / 'rtl/cpu/fn_cpu_base.v', ROOT / 'rtl/cpu/fn_soc_ext.v',
                            ROOT / 'rtl/cpu/fn_cpu_core.v', ROOT / 'rtl/cpu/fn_mem_split.v']
        report.update(status='PAL_SDL_BACKEND_COMPONENT_PASS',
                      host_behavior='PASS', actual_s80_component='PASS',
                      smoke_size=run([cc.SIZE, elf], 'cpu_size').strip(),
                      source_sha256={str(path.relative_to(ROOT)).replace('\\', '/'):
                                     hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in evidence_sources})
        report['artifact_sha256'] = {str(path.relative_to(ROOT)).replace('\\', '/'):
                                     hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in [elf, OUT / 'cpu.hex']}
        print(host_log.strip())
        print(cpu_log.strip())
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        report.update(status='FAIL', error=str(exc))
        raise
    finally:
        status_path.write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
