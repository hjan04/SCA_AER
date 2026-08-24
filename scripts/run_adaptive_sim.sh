#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"
VVP_FILE="$OUT_DIR/tb_adaptive_directed.vvp"

mkdir -p "$OUT_DIR" "$ROOT_DIR/results/waves"

iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -o "$VVP_FILE" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_block_overflow_buffer.sv" \
    "$ROOT_DIR/rtl/common/aer_output_handshake.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_sparse_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_block_occupancy.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_block_selector.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_mode_controller.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_adaptive_top.sv" \
    "$ROOT_DIR/tb/tests/tb_adaptive_directed.sv"

if vvp "$VVP_FILE"; then
    :
else
    echo "ADAPTIVE DIRECTED TESTS: FAIL"
    exit 1
fi
