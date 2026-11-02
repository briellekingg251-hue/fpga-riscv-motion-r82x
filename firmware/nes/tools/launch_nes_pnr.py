"""Launch the native physical flow for the NES hardware variant (one seed).

Mirrors the fusion session's R64 launch exactly (same tool, flags and pnr-extra
options), on a NES hardware variant (default production_r65_nes_cpu162), as a WMI-created process so
the run survives this shell.  Refuses to start when:
  * the NES tree no longer matches its ASSEMBLY record,
  * two or more PDS flows are already running (the machine's memory limit),
  * the work directory already exists.

usage: python -I tools/launch_nes_pnr.py --seed N --slot {1,2} [--hardware NAME] [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nes_common as nc

FUSION = Path("E:/Codex_workplace/cpu_pose_touch_fusion_20261008")
HARDWARE = "production_r65_nes_cpu162"
PNR_EXTRA = "-optimize_gp_recovery -logic_optimize_enable TRUE -fix_hold_violation_in_route TRUE"
MAX_FLOWS = 2


def running_flows() -> list[str]:
    """Top-level pds_shell processes (a flow = a pds_shell whose parent is not pds_shell)."""
    script = ("$p=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'pds_shell.exe'});"
              "$ids=@($p.ProcessId);"
              "$p | Where-Object {$_.ParentProcessId -notin $ids} | ForEach-Object {$_.CommandLine}")
    out = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True)
    return [line for line in out.stdout.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--slot", type=int, choices=[1, 2], required=True)
    parser.add_argument("--hardware", default=HARDWARE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    hardware = FUSION / "hardware" / args.hardware
    meta = json.loads((hardware / "ASSEMBLY.json").read_text())
    drift = [n for n, d in meta["files"].items() if nc.sha256(hardware / n) != d]
    if drift:
        raise SystemExit(f"NES hardware drifted from its record: {drift}")
    # production_r65_nes_cpu162 -> physical_production_r65_nes_s<seed>
    tag = args.hardware.removeprefix("production_").removesuffix("_cpu162")
    work = f"physical_production_{tag}_s{args.seed}"
    if (FUSION / work).exists():
        raise SystemExit(f"{work} already exists")
    flows = running_flows()
    if len(flows) >= MAX_FLOWS:
        raise SystemExit(f"{len(flows)} PDS flows running; slot not free:\n" + "\n".join(flows))
    log = FUSION / "log" / f"{tag}_s{args.seed}_driver.log"
    command = (f'cmd /c "cd /d {FUSION} && E:\\Python\\python.exe -B tools\\run_native_o2.py {work} '
               f'--hardware {args.hardware} --seed {args.seed} --through sta --pnr-slot {args.slot} '
               f'--pnr-extra "{PNR_EXTRA}" > {log} 2>&1"')
    print("running flows:", len(flows))
    print(command)
    if args.dry_run:
        return 0
    ps = ("$r=Invoke-CimMethod -ClassName Win32_Process -MethodName Create "
          f"-Arguments @{{CommandLine='{command.replace(chr(39), chr(39) * 2)}'}}; "
          "Write-Output ($r.ReturnValue.ToString() + ' ' + $r.ProcessId)")
    out = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True)
    print(out.stdout.strip(), out.stderr.strip())
    return 0 if out.stdout.strip().startswith("0 ") else 1


if __name__ == "__main__":
    sys.exit(main())
