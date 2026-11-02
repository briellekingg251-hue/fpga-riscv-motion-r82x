#!/bin/bash
# Build the O2 Verilator simulation.
#   OBJ=<dir>   output directory (default: obj next to this script)
#   extra arguments go to Verilator, e.g. -DTB_RAM_BYTES=2097152 for the
#   large-RAM fixture, or -MAKEFLAGS "OPT_FAST=-O3 OPT_SLOW=-O3" for long runs
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
D=$(cd "$S/../.." && pwd)
source "$D/tools/env.sh"
R=$D/ooo/rtl; B=$D/baseline/src
cd "$S"
verilator_bin --binary --timing --assert --top-module o2_tb --build-jobs 16 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
  -CFLAGS "-std=c++20 -O2" --Mdir "${OBJ:-obj}" -I"$R" -I"$B" \
  "$R/o2_bitram.sv" "$R/o2_decode.sv" "$R/o2_icache.sv" "$R/o2_frontend.sv" "$R/o2_iq.sv" "$R/o2_prf.sv" "$R/o2_rename.sv" \
  "$R/o2_lsu.sv" "$R/o2_rob.sv" "$R/o2_core.sv" "$R/o2_soc.sv" \
  "$B/p2_burst_arbiter2.sv" "$B/p2_burst_sram.sv" "$B/p2_peripherals.sv" \
  "$S/o2_mem_shim.sv" "$S/o2_tb.sv" "$S/cosim.cpp" "$@"
