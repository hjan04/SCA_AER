#!/usr/bin/env python3
"""Replay every adaptive Stage 4 condition on the Model2 hysteresis RTL.

The original Stage 4 suite has 34 adaptive-link configurations at threshold 5:
all 23 primary traffic cases, the eight non-default link-width cases, and
three periodic-backpressure cases.  This runner executes that exact adaptive
configuration set at thresholds 3 and 5, without altering Model1 artifacts.
"""

from __future__ import annotations

import argparse
from dataclasses import replace
from pathlib import Path

import sweep_stage4 as stage4


ROOT = Path(__file__).resolve().parents[1]
RESULT_ROOT = ROOT / "results"


def configure_output_paths() -> None:
    stage4.RESULT_DIR = RESULT_ROOT / "csv" / "runs" / "stage4_model2"
    stage4.RAW_DIR = RESULT_ROOT / "raw" / "stage4_model2"
    stage4.WAVE_DIR = RESULT_ROOT / "waves" / "stage4_model2"
    stage4.MANIFEST = RESULT_ROOT / "csv" / "stage4_model2_manifest.txt"
    stage4.SUMMARY_CSV = RESULT_ROOT / "csv" / "stage4_model2_summary.csv"


def build_model2_runs() -> list[stage4.Stage4Run]:
    cases = stage4.build_trace_cases("stage4")
    reference_runs = stage4.build_runs(cases, "stage4")
    adaptive_reference = [
        run
        for run in reference_runs
        if run.architecture == "adaptive" and run.threshold == 5
    ]
    assert len(adaptive_reference) == 34, len(adaptive_reference)
    return [
        replace(run, threshold=threshold)
        for threshold in (3, 5)
        for run in adaptive_reference
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--regenerate-traces", action="store_true")
    parser.add_argument("--reuse-results", action="store_true")
    args = parser.parse_args()

    configure_output_paths()
    stage4.ensure_dirs()
    runs = build_model2_runs()
    result_paths = [
        stage4.execute_run(
            run,
            regenerate_traces=args.regenerate_traces,
            reuse_results=args.reuse_results,
        )
        for run in runs
    ]
    stage4.write_manifest(result_paths)
    stage4.combine_results(result_paths)
    print(f"[DONE] {len(result_paths)} Model2 Stage 4 simulations")


if __name__ == "__main__":
    main()
