#!/usr/bin/env python3
"""Measure baseline and Model2 throughput around the uniform-load break-even."""

from __future__ import annotations

import csv
import os
import subprocess
from pathlib import Path

from sweep_baseline_traffic import RunConfig, generate_trace, run_name, write_trace


ROOT = Path(__file__).resolve().parents[1]
RUN_SCRIPT = ROOT / "scripts" / "run_stage4_benchmark.sh"
TRACE_DIR = ROOT / "traces" / "generated" / "stage2"
RESULT_DIR = ROOT / "results" / "csv" / "runs" / "stage4_breakeven"
RAW_DIR = ROOT / "results" / "raw" / "stage4_breakeven"
SUMMARY = ROOT / "results" / "csv" / "stage4_breakeven_summary.csv"


def main() -> None:
    for directory in (TRACE_DIR, RESULT_DIR, RAW_DIR, SUMMARY.parent):
        directory.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    for rate in (0.70, 0.85, 0.90, 0.95):
        config = RunConfig(
            "uniform", f"stage4_breakeven_rate{rate:.2f}", 1, rate, 5000,
            max_drain_cycles=5000,
        )
        trace_path = TRACE_DIR / f"{run_name(config)}.trace"
        events = generate_trace(config)
        write_trace(trace_path, events)
        offered = len(events) / config.injection_cycles

        for architecture, threshold in (("baseline", 5), ("adaptive", 3)):
            name = f"stage4_breakeven_rate{rate:.2f}_{architecture}_l16_t{threshold}"
            result = RESULT_DIR / f"{name}.csv"
            env = os.environ.copy()
            env.update({
                "ARCH": architecture, "LINK_WIDTH": "16",
                "DENSE_ENTER_THRESHOLD": str(threshold), "RUN_NAME": name,
                "TRACE_FILE": str(trace_path), "RESULT_FILE": str(result),
                "LOG_FILE": str(RAW_DIR / f"{name}.log"),
                "TRAFFIC_TYPE": "uniform", "TRAFFIC_VARIANT": config.variant,
                "SEED": "1", "READY_SEED": "324508639",
                "INJECTION_CYCLES": "5000", "MAX_DRAIN_CYCLES": "5000",
                "OFFERED_EVENTS_PER_CYCLE": f"{offered:.8f}",
                "LINK_READY_POLICY": "always", "DUMP_WAVES": "0",
            })
            print(f"[RUN] {name}: offered={offered:.4f}", flush=True)
            subprocess.run([str(RUN_SCRIPT)], cwd=ROOT, env=env, check=True)
            with result.open(newline="") as handle:
                rows.extend(csv.DictReader(handle))

    SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    with SUMMARY.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"[SUMMARY] {SUMMARY.relative_to(ROOT)} rows={len(rows)}")


if __name__ == "__main__":
    main()
