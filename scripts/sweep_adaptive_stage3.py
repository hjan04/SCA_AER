#!/usr/bin/env python3
"""Run the Stage 3 adaptive replay subset and threshold sweep."""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUN_SCRIPT = ROOT / "scripts" / "run_adaptive_benchmark.sh"
SUMMARY_CSV = ROOT / "results" / "csv" / "adaptive_stage3_summary.csv"


CASES = [
    {
        "name": "uniform_low",
        "trace": "uniform_rate0.10_rate0p100_seed1_ack0.trace",
        "traffic_type": "uniform",
        "traffic_variant": "rate0.10",
        "seed": 1,
        "offered": 0.10,
        "ack_delay": 0,
    },
    {
        "name": "uniform_near_sat",
        "trace": "uniform_rate0.30_rate0p300_seed1_ack0.trace",
        "traffic_type": "uniform",
        "traffic_variant": "rate0.30",
        "seed": 1,
        "offered": 0.30,
        "ack_delay": 0,
    },
    {
        "name": "uniform_high",
        "trace": "uniform_rate0.80_rate0p800_seed1_ack0.trace",
        "traffic_type": "uniform",
        "traffic_variant": "rate0.80",
        "seed": 1,
        "offered": 0.80,
        "ack_delay": 0,
    },
    {
        "name": "hotspot_4x4",
        "trace": "hotspot_4x4_p80_rate0.40_rate0p400_seed1_ack0.trace",
        "traffic_type": "hotspot",
        "traffic_variant": "4x4_p80_rate0.40",
        "seed": 1,
        "offered": 0.40,
        "ack_delay": 0,
    },
    {
        "name": "burst_rate2_dur500",
        "trace": "burst_burst_rate2.0_dur500_rate0p010_seed1_ack0.trace",
        "traffic_type": "burst",
        "traffic_variant": "burst_rate2.0_dur500",
        "seed": 1,
        "offered": 0.209,
        "ack_delay": 0,
    },
    {
        "name": "locality_4x4",
        "trace": "locality_region4x4_rate0.20_rate0p200_seed1_ack0.trace",
        "traffic_type": "locality",
        "traffic_variant": "region4x4_rate0.20",
        "seed": 1,
        "offered": 0.20,
        "ack_delay": 0,
    },
]


def run_case(case: dict[str, object], threshold: int) -> Path:
    run_name = f"stage3_{case['name']}_t{threshold}"
    result_file = ROOT / "results" / "csv" / "runs" / "stage3" / f"{run_name}.csv"
    log_file = ROOT / "results" / "raw" / "stage3" / f"{run_name}.log"
    wave_file = ROOT / "results" / "waves" / "stage3" / f"{run_name}.vcd"
    trace_file = ROOT / "traces" / "generated" / "stage2" / str(case["trace"])

    env = os.environ.copy()
    env.update(
        {
            "TRACE_FILE": str(trace_file),
            "RUN_NAME": run_name,
            "RESULT_FILE": str(result_file),
            "LOG_FILE": str(log_file),
            "WAVE_FILE": str(wave_file),
            "TRAFFIC_TYPE": str(case["traffic_type"]),
            "TRAFFIC_VARIANT": str(case["traffic_variant"]),
            "SEED": str(case["seed"]),
            "OFFERED_EVENTS_PER_CYCLE": str(case["offered"]),
            "ACK_DELAY_CYCLES": str(case["ack_delay"]),
            "DENSE_ENTER_THRESHOLD": str(threshold),
            "INJECTION_CYCLES": "5000",
            "MAX_DRAIN_CYCLES": "5000",
        }
    )

    print(f"[RUN] {run_name}")
    subprocess.run([str(RUN_SCRIPT)], cwd=ROOT, env=env, check=True)
    return result_file


def combine_results(result_files: list[Path]) -> None:
    rows: list[dict[str, str]] = []
    fieldnames: list[str] | None = None

    for result_file in result_files:
        with result_file.open(newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                row["result_file"] = str(result_file.relative_to(ROOT))
                rows.append(row)
                if fieldnames is None:
                    fieldnames = list(reader.fieldnames or []) + ["result_file"]

    if fieldnames is None:
        raise RuntimeError("No result rows were produced")

    SUMMARY_CSV.parent.mkdir(parents=True, exist_ok=True)
    with SUMMARY_CSV.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"[SUMMARY] {SUMMARY_CSV.relative_to(ROOT)} rows={len(rows)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--thresholds",
        default="3,4,5,6,8",
        help="Comma-separated dense-entry thresholds to run.",
    )
    args = parser.parse_args()

    thresholds = [int(item) for item in args.thresholds.split(",") if item]
    result_files: list[Path] = []

    for threshold in thresholds:
        for case in CASES:
            result_files.append(run_case(case, threshold))

    combine_results(result_files)


if __name__ == "__main__":
    main()
