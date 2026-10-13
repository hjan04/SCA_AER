#!/usr/bin/env python3
"""Run equal-physical-link Stage 4 baseline/adaptive comparisons."""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

from sweep_baseline_traffic import RunConfig, generate_trace, run_name, write_trace


ROOT = Path(__file__).resolve().parents[1]
RUN_SCRIPT = ROOT / "scripts" / "run_stage4_benchmark.sh"
TRACE_DIR = ROOT / "traces" / "generated" / "stage2"
RESULT_DIR = ROOT / "results" / "csv" / "runs" / "stage4"
RAW_DIR = ROOT / "results" / "raw" / "stage4"
WAVE_DIR = ROOT / "results" / "waves" / "stage4"
MANIFEST = ROOT / "results" / "csv" / "stage4_manifest.txt"
SUMMARY_CSV = ROOT / "results" / "csv" / "stage4_summary.csv"


@dataclass(frozen=True)
class TraceCase:
    key: str
    config: RunConfig


@dataclass(frozen=True)
class Stage4Run:
    case: TraceCase
    architecture: str
    link_width: int
    threshold: int
    ready_policy: str = "always"
    stall_period: int = 5
    stall_cycles: int = 1
    random_stall_percent: int = 20


def ensure_dirs() -> None:
    for directory in (TRACE_DIR, RESULT_DIR, RAW_DIR, WAVE_DIR, SUMMARY_CSV.parent):
        directory.mkdir(parents=True, exist_ok=True)


def count_trace_events(path: Path) -> int:
    with path.open("r", encoding="ascii") as handle:
        return sum(1 for line in handle if line.strip())


def ensure_trace(case: TraceCase, regenerate: bool = False) -> tuple[Path, int]:
    trace_path = TRACE_DIR / f"{run_name(case.config)}.trace"
    if regenerate or not trace_path.exists():
        events = generate_trace(case.config)
        write_trace(trace_path, events)
        return trace_path, len(events)
    return trace_path, count_trace_events(trace_path)


def rate_tag(rate: float) -> str:
    return f"{rate:.2f}".replace(".", "p")


def build_trace_cases(preset: str) -> list[TraceCase]:
    if preset == "smoke":
        injection_cycles = 1000
        return [
            TraceCase("uniform_low", RunConfig("uniform", "smoke_stage4_rate0.10", 1, 0.10, injection_cycles)),
            TraceCase(
                "hotspot_dense",
                RunConfig(
                    "hotspot",
                    "smoke_stage4_4x4_p80_rate0.80",
                    1,
                    0.80,
                    injection_cycles,
                    hotspot_x=6,
                    hotspot_y=6,
                    hotspot_w=4,
                    hotspot_h=4,
                    hotspot_probability=0.8,
                ),
            ),
        ]

    injection_cycles = 5000
    max_drain_cycles = 5000
    cases: list[TraceCase] = []

    for rate in [0.05, 0.10, 0.20, 0.30, 0.40, 0.60, 0.80, 1.00, 2.00]:
        cases.append(
            TraceCase(
                f"uniform_rate{rate_tag(rate)}",
                RunConfig(
                    "uniform",
                    f"stage4_rate{rate:.2f}",
                    1,
                    rate,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                ),
            )
        )

    for rate in [0.20, 0.40, 0.80]:
        cases.append(
            TraceCase(
                f"poisson_lambda{rate_tag(rate)}",
                RunConfig(
                    "poisson",
                    f"stage4_lambda{rate:.2f}",
                    1,
                    rate,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                ),
            )
        )

    for rate in [0.20, 0.40, 0.80]:
        cases.append(
            TraceCase(
                f"hotspot_rate{rate_tag(rate)}",
                RunConfig(
                    "hotspot",
                    f"stage4_4x4_p80_rate{rate:.2f}",
                    1,
                    rate,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                    hotspot_x=6,
                    hotspot_y=6,
                    hotspot_w=4,
                    hotspot_h=4,
                    hotspot_probability=0.8,
                ),
            )
        )

    for burst_rate, duration in [(2.0, 500), (4.0, 200)]:
        cases.append(
            TraceCase(
                f"burst_rate{burst_rate:.1f}_dur{duration}",
                RunConfig(
                    "burst",
                    f"stage4_burst_rate{burst_rate:.1f}_dur{duration}",
                    1,
                    0.01,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                    burst_start=2000,
                    burst_duration=duration,
                    burst_rate=burst_rate,
                ),
            )
        )

    for count in [16, 64]:
        cases.append(
            TraceCase(
                f"simultaneous_count{count}",
                RunConfig(
                    "simultaneous",
                    f"stage4_count{count}",
                    1,
                    count / injection_cycles,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                    simultaneous_count=count,
                ),
            )
        )

    for size in [16, 8, 4, 2]:
        cases.append(
            TraceCase(
                f"locality_region{size}x{size}",
                RunConfig(
                    "locality",
                    f"stage4_region{size}x{size}_rate0.20",
                    1,
                    0.20,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                    region_w=size,
                    region_h=size,
                ),
            )
        )

    return cases


def build_runs(cases: list[TraceCase], preset: str) -> list[Stage4Run]:
    if preset == "smoke":
        return [
            Stage4Run(cases[0], "baseline", 16, 5),
            Stage4Run(cases[0], "adaptive", 16, 5),
            Stage4Run(cases[1], "baseline", 16, 5),
            Stage4Run(cases[1], "adaptive", 16, 5),
        ]

    by_key = {case.key: case for case in cases}
    runs: list[Stage4Run] = []

    primary_cases = cases
    for case in primary_cases:
        runs.append(Stage4Run(case, "baseline", 16, 5))
        runs.append(Stage4Run(case, "adaptive", 16, 5))

    link_subset = [
        by_key["uniform_rate0p40"],
        by_key["hotspot_rate0p40"],
        by_key["burst_rate2.0_dur500"],
        by_key["locality_region4x4"],
    ]
    for link_width in [8, 32]:
        for case in link_subset:
            runs.append(Stage4Run(case, "baseline", link_width, 5))
            runs.append(Stage4Run(case, "adaptive", link_width, 5))

    threshold_subset = [
        by_key["uniform_rate0p80"],
        by_key["hotspot_rate0p40"],
        by_key["burst_rate2.0_dur500"],
        by_key["locality_region4x4"],
    ]
    for threshold in [3, 4, 6, 8]:
        for case in threshold_subset:
            runs.append(Stage4Run(case, "adaptive", 16, threshold))

    backpressure_subset = [
        by_key["uniform_rate0p40"],
        by_key["hotspot_rate0p40"],
        by_key["burst_rate2.0_dur500"],
    ]
    for case in backpressure_subset:
        runs.append(Stage4Run(case, "baseline", 16, 5, ready_policy="periodic"))
        runs.append(Stage4Run(case, "adaptive", 16, 5, ready_policy="periodic"))

    return runs


def stage4_run_name(run: Stage4Run) -> str:
    ready_tag = run.ready_policy
    if run.ready_policy == "periodic":
        ready_tag = f"periodic_s{run.stall_cycles}_p{run.stall_period}"
    elif run.ready_policy == "random":
        ready_tag = f"random{run.random_stall_percent}"
    return (
        f"stage4_{run.case.key}_{run.architecture}_"
        f"l{run.link_width}_t{run.threshold}_{ready_tag}"
    )


def execute_run(run: Stage4Run, regenerate_traces: bool, reuse_results: bool) -> Path:
    trace_path, event_count = ensure_trace(run.case, regenerate=regenerate_traces)
    run_name_text = stage4_run_name(run)
    result_path = RESULT_DIR / f"{run_name_text}.csv"

    if reuse_results and result_path.exists():
        print(f"[SKIP] {run_name_text}")
        return result_path

    offered = event_count / run.case.config.injection_cycles
    env = os.environ.copy()
    env.update(
        {
            "ARCH": run.architecture,
            "LINK_WIDTH": str(run.link_width),
            "DENSE_ENTER_THRESHOLD": str(run.threshold),
            "RUN_NAME": run_name_text,
            "TRACE_FILE": str(trace_path),
            "RESULT_FILE": str(result_path),
            "LOG_FILE": str(RAW_DIR / f"{run_name_text}.log"),
            "WAVE_FILE": str(WAVE_DIR / f"{run_name_text}.vcd"),
            "TRAFFIC_TYPE": run.case.config.traffic_type,
            "TRAFFIC_VARIANT": run.case.config.variant,
            "SEED": str(run.case.config.seed),
            "READY_SEED": "324508639",
            "INJECTION_CYCLES": str(run.case.config.injection_cycles),
            "MAX_DRAIN_CYCLES": str(run.case.config.max_drain_cycles),
            "OFFERED_EVENTS_PER_CYCLE": f"{offered:.8f}",
            "LINK_READY_POLICY": run.ready_policy,
            "STALL_PERIOD": str(run.stall_period),
            "STALL_CYCLES": str(run.stall_cycles),
            "RANDOM_STALL_PERCENT": str(run.random_stall_percent),
            "DUMP_WAVES": "0",
        }
    )

    print(
        f"[RUN] {run_name_text}: events={event_count} "
        f"offered={offered:.4f}"
    )
    subprocess.run([str(RUN_SCRIPT)], cwd=ROOT, env=env, check=True)
    return result_path


def write_manifest(result_paths: list[Path]) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with MANIFEST.open("w", encoding="ascii") as handle:
        for path in result_paths:
            handle.write(str(path.relative_to(ROOT)) + "\n")
    print(f"[MANIFEST] {MANIFEST.relative_to(ROOT)} rows={len(result_paths)}")


def combine_results(result_paths: list[Path]) -> None:
    rows: list[dict[str, str]] = []
    fieldnames: list[str] | None = None
    for result_path in result_paths:
        with result_path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                row["result_file"] = str(result_path.relative_to(ROOT))
                rows.append(row)
                if fieldnames is None:
                    fieldnames = list(reader.fieldnames or []) + ["result_file"]

    if fieldnames is None:
        raise RuntimeError("No Stage 4 result rows were produced")

    with SUMMARY_CSV.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"[SUMMARY] {SUMMARY_CSV.relative_to(ROOT)} rows={len(rows)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preset", choices=["smoke", "stage4"], default="stage4")
    parser.add_argument("--regenerate-traces", action="store_true")
    parser.add_argument("--reuse-results", action="store_true")
    parser.add_argument("--only-generate-traces", action="store_true")
    parser.add_argument("--skip-summary", action="store_true")
    parser.add_argument("--max-runs", type=int, default=0)
    args = parser.parse_args()

    ensure_dirs()
    cases = build_trace_cases(args.preset)
    runs = build_runs(cases, args.preset)
    if args.max_runs > 0:
        runs = runs[: args.max_runs]

    if args.only_generate_traces:
        for case in cases:
            trace_path, event_count = ensure_trace(case, regenerate=args.regenerate_traces)
            print(f"[TRACE] {trace_path.relative_to(ROOT)} events={event_count}")
        return

    result_paths = [
        execute_run(run, regenerate_traces=args.regenerate_traces, reuse_results=args.reuse_results)
        for run in runs
    ]
    write_manifest(result_paths)
    if not args.skip_summary:
        combine_results(result_paths)
        subprocess.run(
            [
                str(ROOT / "scripts" / "summarize_stage4_results.py"),
                "--manifest",
                str(MANIFEST),
                "--output-csv",
                str(SUMMARY_CSV),
            ],
            cwd=ROOT,
            check=True,
        )

    print(f"[DONE] {len(result_paths)} Stage 4 simulations")


if __name__ == "__main__":
    main()
