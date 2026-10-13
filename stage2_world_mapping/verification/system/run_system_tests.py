#!/usr/bin/env python3
"""Stage 2 V1 system regression (Claude-owned control/top RTL + Codex numeric RTL).

Steps
  1. Verilator lint of the integrated top (-Wall; UNUSED* notices reported separately)
  2. Generate scenarios + golden expectations (gen_system_vectors.py; Codex golden
     model imported read-only; grid node order checked against grid_test_image.csv)
  3. Compile tb_system for several build configurations (Icarus)
  4. Run the test matrix; every run executes a D2 DUT and an E-lite DUT on the
     same stimulus and requires: exact per-event world addresses in issue order,
     exact counters, exact final memory vs golden, D2 == E-lite bit-identical,
     event conservation.

Usage: python3 run_system_tests.py [--quick] [--build-dir DIR] [--numeric-rtl DIR]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAGE2 = HERE.parents[1]
# Path resolution: the canonical clone uses the in-tree RTL/model. The external
# fallback is retained only for older development checkouts without these files.
DEFAULT_NUMERIC = (STAGE2 / "rtl" if (STAGE2 / "rtl/include/wm_pkg.sv").exists()
                   else Path("/tmp/sca_aer_codex_modeling2/stage2_world_mapping/rtl"))
DEFAULT_CODEX = (STAGE2 / "codex" if (STAGE2 / "codex/model/fixed_point.py").exists()
                 else Path("/tmp/sca_aer_codex_modeling2/stage2_world_mapping/codex"))

CONTROL = ["wm_ctrl_pkg.sv", "wm_input_fifo.sv", "wm_skid_buffer.sv", "wm_word_unpacker.sv",
           "wm_lane_dispatch.sv", "wm_frame_ctrl.sv", "wm_grid_store.sv", "wm_reuse_cache.sv",
           "wm_meta_pipe.sv", "wm_elite_merger.sv", "wm_bank_router.sv",
           "wm_bank_update_ctrl.sv", "wm_world_mem_model.sv", "wm_status_counters.sv"]
NUMERIC = ["wm_lerp.sv", "wm_isqrt.sv", "wm_cordic_vectoring.sv", "wm_ray2angle.sv",
           "wm_world_quant.sv", "wm_mapper_lane.sv"]

# (test id, description, scenario, build, plusargs)
MATRIX = [
    ("T01", "one native word",                       "s01_one_word",          "base", ""),
    ("T02", "one event",                             "s02_one_event",         "base", ""),
    ("T03", "odd event counts",                      "s03_odd_counts",        "base", ""),
    ("T04", "two-lane dispatch / issue cycles",      "s04_two_lane_dispatch", "base", ""),
    ("T05", "mapper CE stall (periodic)",            "s04_two_lane_dispatch", "base", "+STALL=1"),
    ("T06", "metadata alignment under random CE",    "s05_dense_merge_banks", "base", "+STALL=2 +GAP=1"),
    ("T07", "same-cell merge",                       "s06_saturation_on_off", "base", ""),
    ("T08", "same-word / different-cell merge",      "s05_dense_merge_banks", "base", ""),
    ("T09", "different-bank parallel updates",       "s11_real_sept22b",      "base", ""),
    ("T10", "same-bank conflict + bank hold",        "s05_dense_merge_banks", "base", "+HOLD=1"),
    ("T11", "RAW bypass, RD_LAT=3, bank hold",       "s05_dense_merge_banks", "lat3", "+HOLD=1 +STALL=1"),
    ("T12", "ON saturation",                         "s06_saturation_on_off", "base", ""),
    ("T13", "OFF saturation, RD_LAT=3",              "s06_saturation_on_off", "lat3", "+HOLD=1"),
    ("T14", "FIFO backpressure (depth 8, heavy stall)", "s05_dense_merge_banks", "fifo8", "+STALL=3 +HOLD=1"),
    ("T15", "frame/grid swap (5 frames)",            "s07_frame_grid_swap",   "base", "+STALL=2"),
    ("T16", "partial-grid protection",               "s08_partial_grid",      "base", ""),
    ("T17", "world-memory clear (512 cycles)",       "s05_dense_merge_banks", "base", "+CLEAR=1"),
    ("T18", "invalid coordinates dropped+counted",   "s09_invalid_coords",    "base", ""),
    ("T19", "Codex numeric vectors via top",         "s10_codex_vectors",     "base", "+STALL=1"),
    ("T20", "real traffic subset (Sept22b)",         "s11_real_sept22b",      "base", "+STALL=2 +HOLD=1"),
    ("T21", "real traffic subset, no reuse, RD_LAT=3", "s11_real_sept22b",    "noreuse_lat3", ""),
]
BUILDS = {
    "base":         [],
    "lat3":         ["-DRD_LAT=3"],
    "fifo8":        ["-DFIFO_DEPTH=8"],
    "noreuse_lat3": ["-DRD_LAT=3", "-DREUSE_OFF"],
}


def sources(numeric: Path):
    return ([numeric / "include/wm_pkg.sv"] + [STAGE2 / "rtl/control/wm_ctrl_pkg.sv"] +
            [numeric / "numeric" / f for f in NUMERIC] +
            [STAGE2 / "rtl/control" / f for f in CONTROL[1:]] +
            [STAGE2 / "rtl/top/wm_world_mapper_top.sv"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--build-dir", type=Path, default=Path("/tmp/wm_system_build"))
    ap.add_argument("--numeric-rtl", type=Path, default=DEFAULT_NUMERIC)
    ap.add_argument("--codex-dir", type=Path, default=DEFAULT_CODEX)
    a = ap.parse_args()
    b = a.build_dir.resolve()
    b.mkdir(parents=True, exist_ok=True)
    src = sources(a.numeric_rtl)
    log = []

    def say(s):
        print(s, flush=True)
        log.append(s)

    # 1. lint
    lint = subprocess.run(["verilator", "--lint-only", "-Wall", "-Wno-DECLFILENAME",
                           "--top-module", "wm_world_mapper_top", *map(str, src)],
                          capture_output=True, text=True)
    msgs = [l for l in lint.stderr.splitlines() if l.startswith("%")]
    kinds = {}
    for m in msgs:
        k = re.match(r"%(\w+)(-\w+)?", m)
        key = (k.group(1) + (k.group(2) or "")) if k else m
        kinds[key] = kinds.get(key, 0) + 1
    non_unused = {k: v for k, v in kinds.items()
                  if "UNUSED" not in k and k != "Error"}
    say(f"SOURCES numeric={a.numeric_rtl} codex_model={a.codex_dir} stage2={STAGE2}")
    say(f"LINT verilator -Wall: {kinds}")
    say(f"LINT non-UNUSED warnings/errors: {non_unused if non_unused else 'none'}")

    # 2. vectors
    vec = b / "scenarios"
    g = subprocess.run([sys.executable, str(HERE / "gen_system_vectors.py"), str(vec),
                        "--codex-dir", str(a.codex_dir)] +
                       (["--quick"] if a.quick else []), capture_output=True, text=True)
    say(g.stdout.strip())
    if g.returncode != 0:
        say(g.stderr)
        return 1

    # 3. builds
    for name, defs in BUILDS.items():
        cmd = ["iverilog", "-g2012", "-s", "tb_system", "-o", str(b / f"tb_{name}.vvp"), *defs,
               *map(str, src), str(HERE / "tb_system.sv")]
        r = subprocess.run(cmd, capture_output=True, text=True)
        errs = [l for l in r.stderr.splitlines() if "sorry: constant selects" not in l and l.strip()]
        if r.returncode != 0:
            say(f"BUILD {name} FAILED:\n" + "\n".join(errs))
            return 1
        say(f"BUILD {name}: ok")

    # 4. run
    npass = 0
    for tid, desc, sc, build, plus in MATRIX:
        d = vec / sc
        if not d.exists():
            say(f"{tid} SKIP ({sc} not generated)")
            continue
        t0 = time.time()
        r = subprocess.run(["vvp", "-n", str(b / f"tb_{build}.vvp"), f"+DIR={d}", *plus.split()],
                           capture_output=True, text=True, timeout=3600)
        out = [l for l in r.stdout.splitlines() if not l.startswith("WARNING")]
        res = [l for l in out if l.startswith("TB_RESULT")]
        ok = bool(res) and "PASS" in res[0]
        npass += ok
        say(f"{tid} {'PASS' if ok else 'FAIL'}  {desc}  [{sc}, build={build} {plus}] ({time.time()-t0:.1f}s)")
        for l in out:
            if l.startswith("[") :
                say("      " + l)
        if not ok:
            say("\n".join(out[-30:]))
    say(f"SYSTEM REGRESSION: {npass}/{len(MATRIX)} passed")
    (b / "system_regression.log").write_text("\n".join(log) + "\n")
    return 0 if npass == len(MATRIX) else 1


if __name__ == "__main__":
    raise SystemExit(main())
