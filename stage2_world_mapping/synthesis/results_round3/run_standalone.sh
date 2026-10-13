#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
export TOP=wm_ray_path_baseline_top
export OUT="$ROOT/synthesis/results_round3/standalone_cordic_100MHz"
export RTL_FILES="$ROOT/rtl/numeric/wm_isqrt.sv $ROOT/rtl/numeric/wm_cordic_vectoring.sv $ROOT/rtl/numeric/wm_ray2angle.sv $ROOT/rtl/numeric/wm_world_quant.sv $ROOT/rtl/numeric/wm_ray_path_baseline_top.sv"
/tools/cadence/DDI231/bin/genus -files "$ROOT/synthesis/results_round3/run_standalone.tcl" -log "$OUT/genus.log" -overwrite
export TOP=wm_ray_path_direct_top
export OUT="$ROOT/synthesis/results_round3/standalone_direct_100MHz"
export RTL_FILES="$ROOT/rtl/numeric/wm_direct_bin.sv $ROOT/rtl/numeric/wm_ray_path_direct_top.sv"
/tools/cadence/DDI231/bin/genus -files "$ROOT/synthesis/results_round3/run_standalone.tcl" -log "$OUT/genus.log" -overwrite
