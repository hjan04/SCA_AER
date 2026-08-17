#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/results"

mkdir -p "$OUT_DIR"

iverilog -g2012 -Wall \
    -o "$OUT_DIR/tb_aer_tx_hybrid.vvp" \
    "$ROOT_DIR/rtl/aer_tx_hybrid.sv" \
    "$ROOT_DIR/tb/tb_aer_tx_hybrid.sv"

vvp "$OUT_DIR/tb_aer_tx_hybrid.vvp"
