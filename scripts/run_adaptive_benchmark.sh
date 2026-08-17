#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"

: "${TRACE_FILE:?TRACE_FILE must point to an event trace}"

RUN_NAME="${RUN_NAME:-adaptive_benchmark}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/results/csv/runs/stage3/${RUN_NAME}.csv}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/results/raw/stage3/${RUN_NAME}.log}"
WAVE_FILE="${WAVE_FILE:-$ROOT_DIR/results/waves/stage3/${RUN_NAME}.vcd}"
TRAFFIC_TYPE="${TRAFFIC_TYPE:-unknown}"
TRAFFIC_VARIANT="${TRAFFIC_VARIANT:-unknown}"
SEED="${SEED:-0}"
INJECTION_CYCLES="${INJECTION_CYCLES:-5000}"
MAX_DRAIN_CYCLES="${MAX_DRAIN_CYCLES:-5000}"
ACK_DELAY_CYCLES="${ACK_DELAY_CYCLES:-0}"
OFFERED_EVENTS_PER_CYCLE="${OFFERED_EVENTS_PER_CYCLE:-0.0}"
DENSE_ENTER_THRESHOLD="${DENSE_ENTER_THRESHOLD:-5}"

VVP_FILE="$OUT_DIR/tb_benchmark_adaptive_t${DENSE_ENTER_THRESHOLD}.vvp"

mkdir -p "$OUT_DIR" "$ROOT_DIR/results/raw/stage3" \
    "$ROOT_DIR/results/csv/runs/stage3" "$ROOT_DIR/results/waves/stage3"

iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -P "tb_benchmark_adaptive.DENSE_ENTER_THRESHOLD=$DENSE_ENTER_THRESHOLD" \
    -o "$VVP_FILE" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_output_handshake.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_sparse_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_block_occupancy.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_block_selector.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_mode_controller.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_adaptive_top.sv" \
    "$ROOT_DIR/tb/common/tb_output_sink.sv" \
    "$ROOT_DIR/tb/tests/tb_benchmark_adaptive.sv"

vvp "$VVP_FILE" \
    +TRACE_FILE="$TRACE_FILE" \
    +RESULT_FILE="$RESULT_FILE" \
    +TRAFFIC_TYPE="$TRAFFIC_TYPE" \
    +TRAFFIC_VARIANT="$TRAFFIC_VARIANT" \
    +SEED="$SEED" \
    +INJECTION_CYCLES="$INJECTION_CYCLES" \
    +MAX_DRAIN_CYCLES="$MAX_DRAIN_CYCLES" \
    +ACK_DELAY_CYCLES="$ACK_DELAY_CYCLES" \
    +OFFERED_EVENTS_PER_CYCLE="$OFFERED_EVENTS_PER_CYCLE" \
    +WAVE_FILE="$WAVE_FILE" | tee "$LOG_FILE"
