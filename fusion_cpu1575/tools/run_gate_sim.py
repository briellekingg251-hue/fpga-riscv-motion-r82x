"""Functional simulation of the post-route PDS netlist with the official Pango
bsim primitive models, then match the LCD frames against the reference model.

usage: python tools/run_gate_sim.py [frames]
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELSIM = Path("E:/modelsim/win64")
BSIM = Path("F:/jinsgai/FPGA/pds_software/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/bsim")
NETLIST = ROOT / "pds" / "work" / "generate_netlist" / "fn_top_sim.v"


def main() -> int:
    frames = sys.argv[1] if len(sys.argv) > 1 else "3"
    sim = ROOT / "sim"
    out = sim / "out_gate"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir()
    text = NETLIST.read_text(encoding="utf-8", errors="replace")
    prims = sorted(set(re.findall(r"^\s+(V_\w+)\s+(?:/\*.*?\*/\s*)?(?:#\(|\\|\w)", text, re.M)))
    # the official V_GPLL simulates the VCO at 1 fs resolution (hours for one
    # frame); the PLL is a hard block, so use an ideal-clock stand-in instead
    models = [BSIM / f"{p}.v" for p in prims if p != "V_GPLL"]
    if "V_GPLL" in prims:
        models.append(sim / "V_GPLL_ideal.v")
    models += [BSIM / "INT_LUTMUX2_UDP.v", BSIM / "INT_LUTMUX4_UDP.v"]
    if "GRS_INST" not in text:
        models.append(BSIM / "V_GRS.v")
    missing = [str(m) for m in models if not m.exists()]
    if missing:
        raise SystemExit(f"missing models: {missing}")
    tb = sim / "tb_gate.v"
    if "GRS_INST" not in text and "V_GRS GRS_INST" not in tb.read_text():
        raise SystemExit("netlist has no GRS_INST: add `V_GRS GRS_INST(.GRS_N(1'b1));` to tb_gate.v")
    print(f"netlist primitives: {', '.join(prims)}")
    lib = sim / "work_gate"
    shutil.rmtree(lib, ignore_errors=True)
    log = open(sim / "gate_sim.log", "w", encoding="utf-8", errors="replace")
    t0 = time.time()

    def run(argv):
        rc = subprocess.run([str(a) for a in argv], cwd=sim, stdout=log, stderr=subprocess.STDOUT).returncode
        if rc:
            raise SystemExit(f"{argv[0]} failed ({rc}), see sim/gate_sim.log")

    run([MODELSIM / "vlib.exe", "work_gate"])
    run([MODELSIM / "vlog.exe", "-work", "work_gate", "-suppress", "2263", "-y", BSIM, "+libext+.v",
         *models, NETLIST, tb])
    run([MODELSIM / "vsim.exe", "-c", "-lib", "work_gate", "tb_gate", f"+FRAMES={frames}",
         "-do", "run -all; quit -f"])
    log.close()
    print(f"gate simulation took {time.time() - t0:.0f} s")
    return subprocess.run([sys.executable, str(ROOT / "tools" / "check_gate.py")]).returncode


if __name__ == "__main__":
    raise SystemExit(main())
