#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"

: "${TRACE_FILE:?TRACE_FILE must point to an event trace}"

ARCH="${ARCH:-baseline}"
LINK_WIDTH="${LINK_WIDTH:-16}"
DENSE_ENTER_THRESHOLD="${DENSE_ENTER_THRESHOLD:-5}"

case "$ARCH" in
    baseline|baseline_link)
        ARCH_ID=0
        ARCH_NAME="baseline_link"
        ;;
    adaptive|adaptive_link)
        ARCH_ID=1
        ARCH_NAME="adaptive_link"
        ;;
    *)
        echo "ARCH must be baseline or adaptive, got: $ARCH" >&2
        exit 2
        ;;
esac

RUN_NAME="${RUN_NAME:-stage4_${ARCH_NAME}_l${LINK_WIDTH}_t${DENSE_ENTER_THRESHOLD}}"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/results/csv/runs/stage4/${RUN_NAME}.csv}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/results/raw/stage4/${RUN_NAME}.log}"
WAVE_FILE="${WAVE_FILE:-$ROOT_DIR/results/waves/stage4/${RUN_NAME}.vcd}"
TRAFFIC_TYPE="${TRAFFIC_TYPE:-unknown}"
TRAFFIC_VARIANT="${TRAFFIC_VARIANT:-unknown}"
SEED="${SEED:-0}"
READY_SEED="${READY_SEED:-324508639}"
INJECTION_CYCLES="${INJECTION_CYCLES:-5000}"
MAX_DRAIN_CYCLES="${MAX_DRAIN_CYCLES:-5000}"
OFFERED_EVENTS_PER_CYCLE="${OFFERED_EVENTS_PER_CYCLE:-0.0}"
LINK_READY_POLICY="${LINK_READY_POLICY:-always}"
STALL_PERIOD="${STALL_PERIOD:-5}"
STALL_CYCLES="${STALL_CYCLES:-1}"
RANDOM_STALL_PERCENT="${RANDOM_STALL_PERCENT:-20}"
DUMP_WAVES="${DUMP_WAVES:-0}"

VVP_FILE="$OUT_DIR/tb_stage4_compare_${ARCH_NAME}_l${LINK_WIDTH}_t${DENSE_ENTER_THRESHOLD}.vvp"

mkdir -p "$OUT_DIR" "$ROOT_DIR/results/raw/stage4" \
    "$ROOT_DIR/results/csv/runs/stage4" "$ROOT_DIR/results/waves/stage4"

iverilog -g2012 -Wall -I "$ROOT_DIR" \
    -P "tb_stage4_compare.ARCH=$ARCH_ID" \
    -P "tb_stage4_compare.LINK_WIDTH=$LINK_WIDTH" \
    -P "tb_stage4_compare.DENSE_ENTER_THRESHOLD=$DENSE_ENTER_THRESHOLD" \
    -o "$VVP_FILE" \
    "$ROOT_DIR/rtl/common/aer_pkg.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/aer_link_serializer.sv" \
    "$ROOT_DIR/rtl/common/aer_link_deserializer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_packetizer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_link_top.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_sparse_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_block_occupancy.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_block_selector.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_mode_controller.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_adaptive_link_top.sv" \
    "$ROOT_DIR/tb/tests/tb_stage4_compare.sv"

vvp "$VVP_FILE" \
    +TRACE_FILE="$TRACE_FILE" \
    +RESULT_FILE="$RESULT_FILE" \
    +TRAFFIC_TYPE="$TRAFFIC_TYPE" \
    +TRAFFIC_VARIANT="$TRAFFIC_VARIANT" \
    +SEED="$SEED" \
    +READY_SEED="$READY_SEED" \
    +INJECTION_CYCLES="$INJECTION_CYCLES" \
    +MAX_DRAIN_CYCLES="$MAX_DRAIN_CYCLES" \
    +OFFERED_EVENTS_PER_CYCLE="$OFFERED_EVENTS_PER_CYCLE" \
    +LINK_READY_POLICY="$LINK_READY_POLICY" \
    +STALL_PERIOD="$STALL_PERIOD" \
    +STALL_CYCLES="$STALL_CYCLES" \
    +RANDOM_STALL_PERCENT="$RANDOM_STALL_PERCENT" \
    +WAVE_FILE="$WAVE_FILE" \
    +DUMP_WAVES="$DUMP_WAVES" | tee "$LOG_FILE"
