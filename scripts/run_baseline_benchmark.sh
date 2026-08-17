#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"
VVP_FILE="$OUT_DIR/tb_benchmark_baseline.vvp"

: "${TRACE_FILE:?TRACE_FILE must point to an event trace}"

RUN_NAME="${RUN_NAME:-baseline_benchmark}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/results/csv/runs/${RUN_NAME}.csv}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/results/raw/${RUN_NAME}.log}"
WAVE_FILE="${WAVE_FILE:-$ROOT_DIR/results/waves/${RUN_NAME}.vcd}"
TRAFFIC_TYPE="${TRAFFIC_TYPE:-unknown}"
TRAFFIC_VARIANT="${TRAFFIC_VARIANT:-unknown}"
SEED="${SEED:-0}"
INJECTION_CYCLES="${INJECTION_CYCLES:-5000}"
MAX_DRAIN_CYCLES="${MAX_DRAIN_CYCLES:-5000}"
ACK_DELAY_CYCLES="${ACK_DELAY_CYCLES:-0}"
OFFERED_EVENTS_PER_CYCLE="${OFFERED_EVENTS_PER_CYCLE:-0.0}"

mkdir -p "$OUT_DIR" "$ROOT_DIR/results/raw" "$ROOT_DIR/results/csv/runs" \
    "$ROOT_DIR/results/waves"

iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -o "$VVP_FILE" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_output_handshake.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_packetizer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_top.sv" \
    "$ROOT_DIR/tb/common/tb_output_sink.sv" \
    "$ROOT_DIR/tb/tests/tb_benchmark_baseline.sv"

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
