#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"

mkdir -p "$OUT_DIR"

echo "[RUN] link serializer/deserializer directed"
iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -o "$OUT_DIR/tb_link_serializer_directed.vvp" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/aer_link_serializer.sv" \
    "$ROOT_DIR/rtl/common/aer_link_deserializer.sv" \
    "$ROOT_DIR/tb/tests/tb_link_serializer_directed.sv"
vvp "$OUT_DIR/tb_link_serializer_directed.vvp"

echo "[RUN] baseline through physical link directed"
iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -o "$OUT_DIR/tb_baseline_link_directed.vvp" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_block_overflow_buffer.sv" \
    "$ROOT_DIR/rtl/common/aer_link_serializer.sv" \
    "$ROOT_DIR/rtl/common/aer_link_deserializer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_packetizer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_link_top.sv" \
    "$ROOT_DIR/tb/tests/tb_baseline_link_directed.sv"
vvp "$OUT_DIR/tb_baseline_link_directed.vvp"

echo "[RUN] adaptive through physical link directed"
iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -o "$OUT_DIR/tb_adaptive_link_directed.vvp" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_block_overflow_buffer.sv" \
    "$ROOT_DIR/rtl/common/aer_link_serializer.sv" \
    "$ROOT_DIR/rtl/common/aer_link_deserializer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_sparse_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_block_occupancy.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_block_selector.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_mode_controller.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_adaptive_link_top.sv" \
    "$ROOT_DIR/tb/tests/tb_adaptive_link_directed.sv"
vvp "$OUT_DIR/tb_adaptive_link_directed.vvp"

echo ""
echo "STAGE4 LINK DIRECTED TESTS: PASS"
