#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"
WAVE_DIR="$OUT_DIR/waves"

mkdir -p "$OUT_DIR"
mkdir -p "$WAVE_DIR"

iverilog -g2012 -Wall \
    -o "$OUT_DIR/tb_baseline_directed.vvp" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_output_handshake.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_packetizer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_top.sv" \
    "$ROOT_DIR/tb/tests/tb_baseline_directed.sv"

vvp "$OUT_DIR/tb_baseline_directed.vvp"
