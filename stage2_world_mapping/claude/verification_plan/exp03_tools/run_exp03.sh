#!/usr/bin/env bash
# Exp03 driver: copy-extract -> decode -> analyze (one dataset per process) -> merge.
# Raw recordings are only read. Derived data goes to ../exp03_cache (git-ignored).
set -euo pipefail
ulimit -v 11500000   # ~11 GB cap: fail cleanly instead of OOM-killing the WSL VM
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="$HERE/../exp03_cache"
OUT="$HERE/../exp03_results"
mkdir -p "$CACHE" "$OUT"
SEPT15="/home/hj/DELTA_SDK-1.0.0/Linux/x64/RawDataSave/2026-09-15-14-27-41-DELTA.dvs"
ZDIR="/mnt/c/Users/hwiju/OneDrive/Desktop/동아리/AI 반도체 회로설계 경진 대회"
[ -f "$CACHE/2026-09-22-16-42-32-DELTA.dvs" ] || unzip -o -q "$ZDIR/2026-09-22-16-42-32-DELTA.zip" -d "$CACHE"
[ -f "$CACHE/2026-09-22-16-42-44-DELTA.dvs" ] || unzip -o -q "$ZDIR/2026-09-22-16-42-44-DELTA.zip" -d "$CACHE"
sha256sum "$SEPT15" "$CACHE"/2026-09-22-*.dvs > "$CACHE/input_sha256.txt"
declare -A SRC=( [sept15_yaw]="$SEPT15"
                 [sept22a_1642_32]="$CACHE/2026-09-22-16-42-32-DELTA.dvs"
                 [sept22b_1642_44]="$CACHE/2026-09-22-16-42-44-DELTA.dvs" )
for name in sept15_yaw sept22a_1642_32 sept22b_1642_44; do
  [ -f "$CACHE/$name.npz" ] || python3 -I "$HERE/dvs_decode.py" "${SRC[$name]}" "$CACHE/$name.npz" > "$CACHE/decode_$name.log"
  [ -f "$CACHE/$name.pkl" ] || python3 -I "$HERE/exp03_analyze.py" one "$CACHE/$name.pkl" "$name=$CACHE/$name.npz"
done
python3 -I "$HERE/exp03_analyze.py" merge "$OUT" "$CACHE"/sept15_yaw.pkl "$CACHE"/sept22a_1642_32.pkl "$CACHE"/sept22b_1642_44.pkl
cp "$CACHE/input_sha256.txt" "$OUT/input_sha256.txt"
for name in sept15_yaw sept22a_1642_32 sept22b_1642_44; do cp "$CACHE/decode_$name.log" "$OUT/decode_$name.log"; done
echo EXP03_DONE
