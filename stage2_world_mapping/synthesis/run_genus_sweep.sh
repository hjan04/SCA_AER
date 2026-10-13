#!/usr/bin/env bash
# Prepared Genus sweep (NOT RUN in the local workspace; run on the Genus server).
# Primary comparison : MODE 1 (memories black-boxed), D2 vs ELITE at 100 MHz.
# Exploration        : MODE 1 at 150 MHz and 200 MHz (timing may not close).
# Diagnostic only    : MODE 2 (memories inferred as registers) at 100 MHz.
#
# Usage: synthesis/run_genus_sweep.sh [primary|explore|diagnostic|all]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$HERE/results"
WHAT="${1:-primary}"
run() {  # config mode period tag
  local out="$RES/$1_mode$2_$4"
  mkdir -p "$out"
  WM_CONFIG=$1 WM_MODE=$2 WM_PERIOD=$3 WM_OUT="$out" \
    genus -no_gui -files "$HERE/genus_wm.tcl" -log "$out/genus" </dev/null
}
case "$WHAT" in
  primary|all)
    run D2 1 10.0 100MHz; run ELITE 1 10.0 100MHz ;;&
  explore|all)
    run D2 1 6.667 150MHz; run ELITE 1 6.667 150MHz
    run D2 1 5.0 200MHz;   run ELITE 1 5.0 200MHz ;;&
  diagnostic|all)
    run D2 2 10.0 100MHz; run ELITE 2 10.0 100MHz ;;
  primary|explore) ;;
  *) echo "usage: $0 [primary|explore|diagnostic|all]"; exit 1 ;;
esac
