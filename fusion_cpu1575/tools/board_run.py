"""Program the FPGA SRAM over JTAG and capture the board UART.

Same procedure as the sealed CPU's successful 2026-09-29 board run:
open COM15 (CP210x, 115200) first, then `cdt_cfg -ip 127.0.0.1 -port 65420
-file program.tcl` (scan chain, program SRAM, verify), keep capturing.
SRAM only -- Flash is never written; power-cycling restores the old image.

usage: python tools/board_run.py --candidate work_sd_net_s2 --capture-seconds 60
capture-seconds is the UART observation window AFTER programming and verify.
"""
from __future__ import annotations

import hashlib
import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from run_pds import read_timing_summary

ROOT = Path(__file__).resolve().parents[1]
BIN = Path("F:/jinsgai/FPGA/pds_software/PDS_2022.2-SP6.4/bin")
FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)

CAPTURE_PS1 = r"""param([int]$DurationSeconds = 40)
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'uart_capture.log'
$port = [System.IO.Ports.SerialPort]::new('__PORT__', 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.DtrEnable = $false
$port.RtsEnable = $false
$port.ReadTimeout = 250
$port.Encoding = [System.Text.Encoding]::ASCII
$buffer = [System.Text.StringBuilder]::new()
$started = [DateTimeOffset]::Now
$port.Open()
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'uart_open.ready'), 'ready')
try {
    while (([DateTimeOffset]::Now - $started).TotalSeconds -lt $DurationSeconds) {
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'capture.stop')) { break }
        $chunk = $port.ReadExisting()
        if ($chunk.Length -gt 0) {
            [void]$buffer.Append($chunk)
            [System.IO.File]::WriteAllText($out, $buffer.ToString(), [System.Text.Encoding]::ASCII)
        }
        Start-Sleep -Milliseconds 40
    }
}
finally {
    if ($port.IsOpen) { $port.Close() }
    [System.IO.File]::WriteAllText($out, $buffer.ToString(), [System.Text.Encoding]::ASCII)
    $port.Dispose()
}
"""


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--capture-seconds', type=int, default=60)
    parser.add_argument('--program-timeout', type=int, default=600)
    parser.add_argument('--uart-port', default='COM15')
    parser.add_argument('--jtag-frequency', choices=['1Mhz', '500Khz'], default='1Mhz')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.candidate) or args.capture_seconds < 30 or args.program_timeout < 60:
        parser.error('candidate must be a simple build name; capture-seconds must be >= 30')
    port = args.uart_port.upper()
    if not re.fullmatch(r'COM[1-9][0-9]*', port):
        parser.error('uart-port must be a Windows COM port name')
    seconds = args.capture_seconds
    candidate = ROOT/'pds'/args.candidate
    bit = candidate/'generate_bitstream/fn_top.sbit'
    manifest = json.loads((candidate/'input_sha256.json').read_text())
    result = json.loads((candidate/'run_result.json').read_text())
    if result['exit_code'] != 0 or not bit.is_file() or not bit.stat().st_size:
        raise SystemExit('Candidate has no successfully generated bitstream')
    if not manifest or any(sha(candidate/'input'/name) != digest for name, digest in manifest.items()):
        raise SystemExit('Candidate input hash verification failed')
    bit_hash = sha(bit)
    timing = read_timing_summary(candidate/'report_timing/fn_top.rtr')
    out = ROOT / "board" / datetime.now().strftime("run_%Y%m%d_%H%M%S")
    out.mkdir(parents=True)
    (out / "capture_uart.ps1").write_text(CAPTURE_PS1.replace("__PORT__", port), encoding="utf-8")
    (out / "program.tcl").write_text("\n".join([
        "cfg_set_tcl_break -flag true",
        f"cfg_set_cable_property -index 0 -freq {args.jtag_frequency}",
        "cfg_scan_chain",
        f"cfg_assign_file -file {{{bit.as_posix()}}} -device_index 0",
        "cfg_program -device_index 0",
        "cfg_verify -device_index 0",
        "cfg_disconnect",
        "cfg_close", ""]), encoding="ascii")
    (out / "bitstream.sha256").write_text(f"{bit_hash}  {bit}\n")
    print(f"run dir {out}\nbitstream {bit} sha256 {bit_hash[:16]}...", flush=True)

    cap_log = open(out / "capture_console.log", "w")
    cap = subprocess.Popen(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                            str(out / "capture_uart.ps1"), "-DurationSeconds", str(args.program_timeout + seconds + 30)],
                           cwd=out, stdout=cap_log, stderr=subprocess.STDOUT, creationflags=FLAGS)
    try:
        for _ in range(100):
            if (out / "uart_open.ready").exists():
                break
            if cap.poll() is not None:
                raise SystemExit(f"UART capture on {port} exited early, see capture_console.log")
            time.sleep(0.1)
        else:
            raise SystemExit("UART open timeout")
        print(f"{port} open, programming SRAM ...")
        t0 = time.time()
        deadline = time.monotonic() + args.program_timeout
        with open(out / "configuration_console.log", "w", errors="replace") as log:
            rc = subprocess.run([str(BIN / "cdt_cfg.exe"), "-ip", "127.0.0.1", "-port", "65420",
                                 "-file", str(out / "program.tcl")], cwd=out, stdout=log,
                                stderr=subprocess.STDOUT, timeout=args.program_timeout, creationflags=FLAGS).returncode
        print(f"cdt_cfg exit {rc} after {time.time() - t0:.1f} s")
        # cdt_cfg is a launcher; its return code alone is not the configuration
        # task's completion. Keep UART open through the actual verify result.
        while time.monotonic() < deadline:
            cfg_path = out/'configuration_tcl.log'
            cfg_progress = cfg_path.read_text(errors='replace') if cfg_path.exists() else ''
            if 'cfg_verify succeed' in cfg_progress or re.search(r'cfg_\w+\s+(?:fail\w*|error)\b', cfg_progress, re.I):
                break
            if cap.poll() is not None:
                raise RuntimeError('UART capture exited during programming; see capture_console.log')
            time.sleep(0.25)
        else:
            raise RuntimeError('Configuration task timed out; inspect logs before any retry')
        print('Configuration task finished; observing board UART ...', flush=True)
        time.sleep(seconds)
        (out/'capture.stop').write_text('stop')
        cap.wait(timeout=10)
    finally:
        (out/'capture.stop').write_text('stop')
        if cap.poll() is None:
            cap.terminate()
            cap.wait(timeout=10)
        cap_log.close()
    cfg = (out / "configuration_tcl.log").read_text(errors="replace") if (out / "configuration_tcl.log").exists() else ""
    print(cfg.strip())
    uart = (out / "uart_capture.log").read_text(errors="replace") if (out / "uart_capture.log").exists() else ""
    print("---- UART ----")
    print(uart.strip())
    ok = rc == 0 and all(f"{s} succeed" in cfg for s in ("cfg_scan_chain", "cfg_program", "cfg_verify")) and sha(bit) == bit_hash
    sd_capacity = re.search(r'SD INIT OK capacity sectors (\d+)', uart)
    (out/'receipt.json').write_text(json.dumps(dict(status='PROGRAM_VERIFY_PASS' if ok else 'FAIL',
        candidate=args.candidate, bitstream=str(bit), bitstream_sha256=bit_hash,
        input_sha256=manifest, declared_clock_timing=timing, uart_port=port,
        jtag_frequency=args.jtag_frequency,
        sd_initialization='PASS' if sd_capacity else ('FAIL' if 'SD INITIALIZATION FAILED' in uart else 'NOT_OBSERVED'),
        sd_capacity_sectors=int(sd_capacity.group(1)) if sd_capacity else None,
        physical_sd_write='NOT_RUN', game_on_board='NOT_RUN'),indent=2),encoding='utf-8')
    print("PROGRAM+VERIFY", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
