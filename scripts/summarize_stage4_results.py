#!/usr/bin/env python3
"""Summarize Stage 4 equal-physical-link benchmark CSVs and generate plots."""

from __future__ import annotations

import argparse
import csv
import math
import os
from collections import defaultdict
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-sca-aer")
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT_DIR = ROOT / "results" / "csv" / "runs" / "stage4"
DEFAULT_OUTPUT_CSV = ROOT / "results" / "csv" / "stage4_summary.csv"
PLOT_DIR = ROOT / "results" / "plots" / "stage4"
DOC_PATH = ROOT / "docs" / "stage4_comparison_analysis.md"


def read_rows_from_paths(paths: list[Path]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in paths:
        with path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                row["result_file"] = str(path.relative_to(ROOT))
                rows.append(row)
    return rows


def read_manifest(path: Path) -> list[Path]:
    paths: list[Path] = []
    with path.open("r", encoding="ascii") as handle:
        for line in handle:
            item = line.strip()
            if item:
                paths.append((ROOT / item).resolve())
    return paths


def write_summary_csv(rows: list[dict[str, str]], output_csv: Path) -> None:
    if not rows:
        raise RuntimeError("No Stage 4 rows to summarize")
    fieldnames = list(rows[0].keys())
    output_csv = output_csv.resolve()
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def f(row: dict[str, str], key: str, default: float = 0.0) -> float:
    value = row.get(key, "")
    if value in ("", "NA"):
        return default
    try:
        return float(value)
    except ValueError:
        return default


def i(row: dict[str, str], key: str, default: int = 0) -> int:
    value = row.get(key, "")
    if value in ("", "NA"):
        return default
    try:
        return int(float(value))
    except ValueError:
        return default


def is_primary(row: dict[str, str]) -> bool:
    return (
        i(row, "link_width") == 16
        and i(row, "dense_threshold") == 5
        and row.get("link_ready_policy") == "always"
    )


def is_uniform(row: dict[str, str]) -> bool:
    return row.get("traffic_type") == "uniform"


def arch_rows(rows: list[dict[str, str]], arch: str) -> list[dict[str, str]]:
    return [row for row in rows if row.get("architecture") == arch]


def common_key(row: dict[str, str]) -> tuple[str, str, int, int, str]:
    return (
        row.get("traffic_type", ""),
        row.get("traffic_variant", ""),
        i(row, "seed"),
        i(row, "link_width"),
        row.get("link_ready_policy", ""),
    )


def saturation(rows: list[dict[str, str]], arch: str) -> tuple[float, dict[str, str] | None]:
    candidates = [
        row
        for row in rows
        if is_primary(row)
        and is_uniform(row)
        and row.get("architecture") == arch
        and f(row, "event_loss_rate") <= 0.01
        and f(row, "throughput_events_per_cycle") >= 0.95 * f(row, "offered_events_per_cycle")
    ]
    if not candidates:
        return 0.0, None
    best = max(candidates, key=lambda row: f(row, "offered_events_per_cycle"))
    return f(best, "offered_events_per_cycle"), best


def average(rows: list[dict[str, str]], key: str) -> float:
    if not rows:
        return 0.0
    return sum(f(row, key) for row in rows) / len(rows)


def sum_int(rows: list[dict[str, str]], key: str) -> int:
    return sum(i(row, key) for row in rows)


def plot_metric_vs_rate(
    rows: list[dict[str, str]],
    metric: str,
    ylabel: str,
    title: str,
    output_name: str,
) -> None:
    PLOT_DIR.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(7.5, 4.8))
    for arch, label in [("baseline_link", "Baseline"), ("adaptive_link", "Adaptive")]:
        points = [
            (f(row, "offered_events_per_cycle"), f(row, metric))
            for row in rows
            if is_primary(row) and is_uniform(row) and row.get("architecture") == arch
        ]
        points = sorted(points)
        if points:
            xs, ys = zip(*points)
            plt.plot(xs, ys, marker="o", label=label)
    plt.xlabel("Offered Event Rate (events/cycle)")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(PLOT_DIR / output_name, dpi=160)
    plt.close()


def locality_size(row: dict[str, str]) -> int:
    variant = row.get("traffic_variant", "")
    marker = "region"
    if marker not in variant:
        return 0
    tail = variant.split(marker, 1)[1]
    size_text = tail.split("x", 1)[0]
    try:
        return int(size_text)
    except ValueError:
        return 0


def plot_locality(
    rows: list[dict[str, str]],
    metric: str,
    ylabel: str,
    title: str,
    output_name: str,
) -> None:
    PLOT_DIR.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(7.5, 4.8))
    for arch, label in [("baseline_link", "Baseline"), ("adaptive_link", "Adaptive")]:
        points = [
            (locality_size(row), f(row, metric))
            for row in rows
            if is_primary(row)
            and row.get("traffic_type") == "locality"
            and row.get("architecture") == arch
        ]
        points = sorted(points, reverse=True)
        if points:
            xs, ys = zip(*points)
            plt.plot([str(x) + "x" + str(x) for x in xs], ys, marker="o", label=label)
    plt.xlabel("Active Region")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(PLOT_DIR / output_name, dpi=160)
    plt.close()


def plot_dense_histogram(rows: list[dict[str, str]]) -> None:
    hist = [0 for _ in range(17)]
    for row in rows:
        if (
            is_primary(row)
            and row.get("architecture") == "adaptive_link"
            and i(row, "dense_packets") > 0
        ):
            for occ in range(17):
                hist[occ] += i(row, f"dense_occ_{occ}")

    PLOT_DIR.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(7.5, 4.8))
    plt.bar(list(range(17)), hist)
    plt.xlabel("Events Represented by Dense Packet")
    plt.ylabel("Packet Count")
    plt.title("Adaptive Dense Packet Occupancy Distribution")
    plt.grid(True, axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(PLOT_DIR / "stage4_dense_occupancy_distribution.png", dpi=160)
    plt.close()


def generate_plots(rows: list[dict[str, str]]) -> None:
    plot_metric_vs_rate(
        rows,
        "throughput_events_per_cycle",
        "Delivered Throughput (events/cycle)",
        "Uniform Offered Load vs Delivered Throughput",
        "stage4_rate_vs_throughput.png",
    )
    plot_metric_vs_rate(
        rows,
        "event_loss_rate",
        "Event Loss Rate",
        "Uniform Offered Load vs Event Loss",
        "stage4_rate_vs_event_loss.png",
    )
    plot_metric_vs_rate(
        rows,
        "average_latency",
        "Average End-to-End Latency (cycles)",
        "Uniform Offered Load vs Average Latency",
        "stage4_rate_vs_average_latency.png",
    )
    plot_metric_vs_rate(
        rows,
        "physical_bits_per_event",
        "Physical Bits per Delivered Event",
        "Uniform Offered Load vs Physical Bits/Event",
        "stage4_rate_vs_physical_bits_per_event.png",
    )
    plot_locality(
        rows,
        "physical_bits_per_event",
        "Physical Bits per Delivered Event",
        "Spatial Locality vs Physical Bits/Event",
        "stage4_locality_vs_physical_bits_per_event.png",
    )
    plot_locality(
        rows,
        "throughput_events_per_cycle",
        "Delivered Throughput (events/cycle)",
        "Spatial Locality vs Delivered Throughput",
        "stage4_locality_vs_throughput.png",
    )
    plot_dense_histogram(rows)


def physical_break_even(rows: list[dict[str, str]]) -> dict[int, int]:
    result: dict[int, int] = {}
    by_width: dict[int, dict[str, int]] = defaultdict(dict)
    for row in rows:
        width = i(row, "link_width")
        if width == 0:
            continue
        by_width[width]["sparse"] = i(row, "baseline_physical_bits_per_packet")
        by_width[width]["dense"] = i(row, "dense_physical_bits_per_packet")

    for width, costs in by_width.items():
        sparse = costs.get("sparse", 0)
        dense = costs.get("dense", 0)
        threshold = 0
        if sparse > 0 and dense > 0:
            for events in range(1, 17):
                if dense < events * sparse:
                    threshold = events
                    break
        result[width] = threshold
    return result


def rows_by_arch_case(rows: list[dict[str, str]]) -> dict[tuple[str, str, int, int, str], dict[str, dict[str, str]]]:
    grouped: dict[tuple[str, str, int, int, str], dict[str, dict[str, str]]] = defaultdict(dict)
    for row in rows:
        if i(row, "dense_threshold") == 5:
            grouped[common_key(row)][row.get("architecture", "")] = row
    return grouped


def comparison_observations(rows: list[dict[str, str]]) -> tuple[list[str], list[str]]:
    baseline_better: list[str] = []
    adaptive_better: list[str] = []
    grouped = rows_by_arch_case([row for row in rows if is_primary(row)])
    for key, arch_map in grouped.items():
        base = arch_map.get("baseline_link")
        adap = arch_map.get("adaptive_link")
        if base is None or adap is None:
            continue
        label = f"{key[0]} {key[1]}"
        base_thr = f(base, "throughput_events_per_cycle")
        adap_thr = f(adap, "throughput_events_per_cycle")
        base_loss = f(base, "event_loss_rate")
        adap_loss = f(adap, "event_loss_rate")
        if base_thr > adap_thr * 1.02 or base_loss + 0.001 < adap_loss:
            baseline_better.append(
                f"{label}: baseline thr={base_thr:.4f}, loss={base_loss:.4f}; "
                f"adaptive thr={adap_thr:.4f}, loss={adap_loss:.4f}"
            )
        if adap_thr > base_thr * 1.02 or adap_loss + 0.001 < base_loss:
            adaptive_better.append(
                f"{label}: adaptive thr={adap_thr:.4f}, loss={adap_loss:.4f}; "
                f"baseline thr={base_thr:.4f}, loss={base_loss:.4f}"
            )
    return baseline_better, adaptive_better


def make_markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join(["---"] * len(headers)) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def write_analysis_doc(rows: list[dict[str, str]], output_csv: Path) -> None:
    output_csv = output_csv.resolve()
    baseline_sat, baseline_sat_row = saturation(rows, "baseline_link")
    adaptive_sat, adaptive_sat_row = saturation(rows, "adaptive_link")
    if baseline_sat > 0.0:
        improvement = (adaptive_sat / baseline_sat) - 1.0
    else:
        improvement = math.inf if adaptive_sat > 0.0 else 0.0

    break_even = physical_break_even(rows)
    baseline_better, adaptive_better = comparison_observations(rows)

    uniform_rows: list[list[str]] = []
    grouped = rows_by_arch_case([row for row in rows if is_primary(row) and is_uniform(row)])
    for key in sorted(grouped.keys(), key=lambda item: f(next(iter(grouped[item].values())), "offered_events_per_cycle")):
        arch_map = grouped[key]
        base = arch_map.get("baseline_link")
        adap = arch_map.get("adaptive_link")
        if base is None or adap is None:
            continue
        uniform_rows.append(
            [
                f"{f(base, 'offered_events_per_cycle'):.4f}",
                f"{f(base, 'throughput_events_per_cycle'):.4f}",
                f"{f(adap, 'throughput_events_per_cycle'):.4f}",
                f"{f(base, 'event_loss_rate'):.4f}",
                f"{f(adap, 'event_loss_rate'):.4f}",
                f"{f(base, 'physical_bits_per_event'):.2f}",
                f"{f(adap, 'physical_bits_per_event'):.2f}",
                str(i(adap, "dense_packets")),
            ]
        )

    threshold_variants = {
        "stage4_rate0.80",
        "stage4_4x4_p80_rate0.40",
        "stage4_burst_rate2.0_dur500",
        "stage4_region4x4_rate0.20",
    }
    threshold_rows: list[list[str]] = []
    threshold_stats: list[dict[str, float]] = []
    for threshold in [3, 4, 5, 6, 8]:
        selected = [
            row
            for row in rows
            if row.get("architecture") == "adaptive_link"
            and i(row, "link_width") == 16
            and i(row, "dense_threshold") == threshold
            and row.get("link_ready_policy") == "always"
            and row.get("traffic_variant") in threshold_variants
        ]
        if selected:
            dense_packet_total = sum_int(selected, "dense_packets")
            dense_event_total = sum_int(selected, "events_in_dense_packets")
            weighted_dense_occupancy = (
                dense_event_total / dense_packet_total if dense_packet_total else 0.0
            )
            threshold_stats.append(
                {
                    "threshold": float(threshold),
                    "throughput": average(selected, "throughput_events_per_cycle"),
                    "loss": average(selected, "event_loss_rate"),
                    "latency": average(selected, "average_latency"),
                    "physical_bits": average(selected, "physical_bits_per_event"),
                    "dense_packets": float(dense_packet_total),
                    "dense_occupancy": weighted_dense_occupancy,
                }
            )
            threshold_rows.append(
                [
                    str(threshold),
                    f"{average(selected, 'throughput_events_per_cycle'):.4f}",
                    f"{average(selected, 'event_loss_rate'):.4f}",
                    f"{average(selected, 'average_latency'):.2f}",
                    f"{average(selected, 'physical_bits_per_event'):.2f}",
                    str(dense_packet_total),
                    f"{weighted_dense_occupancy:.2f}",
                ]
            )

    recommended_threshold = 5
    if threshold_stats:
        recommended = max(
            threshold_stats,
            key=lambda item: (item["throughput"], -item["loss"], -item["physical_bits"]),
        )
        recommended_threshold = int(recommended["threshold"])

    link_width_rows: list[list[str]] = []
    link_subset_variants = {
        "stage4_rate0.40",
        "stage4_4x4_p80_rate0.40",
        "stage4_burst_rate2.0_dur500",
        "stage4_region4x4_rate0.20",
    }
    for width in sorted({i(row, "link_width") for row in rows}):
        for arch in ["baseline_link", "adaptive_link"]:
            selected = [
                row
                for row in rows
                if row.get("architecture") == arch
                and i(row, "link_width") == width
                and i(row, "dense_threshold") == 5
                and row.get("link_ready_policy") == "always"
                and row.get("traffic_variant") in link_subset_variants
            ]
            if selected:
                link_width_rows.append(
                    [
                        str(width),
                        arch,
                        f"{average(selected, 'throughput_events_per_cycle'):.4f}",
                        f"{average(selected, 'event_loss_rate'):.4f}",
                        f"{average(selected, 'physical_bits_per_event'):.2f}",
                        str(sum_int(selected, "dense_packets")),
                    ]
                )

    hotspot_rows = [
        row
        for row in rows
        if is_primary(row) and row.get("traffic_type") in ("hotspot", "burst")
    ]
    hotspot_text_rows: list[list[str]] = []
    grouped_hotspot = rows_by_arch_case(hotspot_rows)
    for key in sorted(grouped_hotspot.keys()):
        base = grouped_hotspot[key].get("baseline_link")
        adap = grouped_hotspot[key].get("adaptive_link")
        if base is None or adap is None:
            continue
        hotspot_text_rows.append(
            [
                f"{key[0]} {key[1]}",
                f"{f(base, 'event_loss_rate'):.4f}",
                f"{f(adap, 'event_loss_rate'):.4f}",
                f"{f(base, 'average_latency'):.2f}",
                f"{f(adap, 'average_latency'):.2f}",
                str(i(adap, "dense_packets")),
            ]
        )

    sparse_base = next(
        (
            row
            for row in rows
            if is_primary(row)
            and row.get("architecture") == "baseline_link"
            and row.get("traffic_type") == "uniform"
            and f(row, "offered_events_per_cycle") <= 0.06
        ),
        None,
    )
    sparse_adap = next(
        (
            row
            for row in rows
            if is_primary(row)
            and row.get("architecture") == "adaptive_link"
            and row.get("traffic_type") == "uniform"
            and f(row, "offered_events_per_cycle") <= 0.06
        ),
        None,
    )
    sparse_penalty = "NA"
    if sparse_base is not None and sparse_adap is not None:
        sparse_penalty = (
            f"baseline {f(sparse_base, 'physical_bits_per_event'):.2f} bits/event, "
            f"adaptive {f(sparse_adap, 'physical_bits_per_event'):.2f} bits/event"
        )

    q1 = "No"
    if adaptive_sat > baseline_sat:
        q1 = "Yes"
    elif adaptive_sat == baseline_sat and adaptive_sat > 0:
        q1 = "Tied under the configured saturation rule"

    lines: list[str] = []
    lines.append("# Stage 4 Physical-Link Comparison Analysis")
    lines.append("")
    lines.append("This document is generated from actual Stage 4 RTL simulation CSV rows.")
    lines.append("")
    lines.append("## Regression and Run Set")
    lines.append("")
    lines.append(f"- Summary CSV: `{output_csv.relative_to(ROOT)}`")
    lines.append(f"- Comparative simulation rows summarized: {len(rows)}")
    lines.append("- Primary comparison: `LINK_WIDTH = 16`, always-ready link, `DENSE_ENTER_THRESHOLD = 5`.")
    lines.append("- Physical latency is measured from input event generation to receiver-side packet reconstruction.")
    lines.append("")
    lines.append("## Wire-Format Costs")
    lines.append("")
    lines.append("- Header: 8 bits, `{payload_length[5:0], packet_type[1:0]}` on the wire LSB-first.")
    lines.append("- Baseline sparse payload: 9 bits; 17-bit frame; 32 physical bits on a 16-bit link.")
    lines.append("- Adaptive sparse payload: 10 bits; 18-bit frame; 32 physical bits on a 16-bit link.")
    lines.append("- Adaptive dense payload: 37 bits; 45-bit frame; 48 physical bits on a 16-bit link.")
    lines.append("")
    lines.append("## Uniform Load Sweep")
    lines.append("")
    lines.append(
        make_markdown_table(
            [
                "Offered",
                "Baseline Thr",
                "Adaptive Thr",
                "Baseline Loss",
                "Adaptive Loss",
                "Baseline Phys Bits/Event",
                "Adaptive Phys Bits/Event",
                "Adaptive Dense Packets",
            ],
            uniform_rows,
        )
    )
    lines.append("")
    lines.append("## Saturation Result")
    lines.append("")
    lines.append(
        f"- Baseline normalized saturation: {baseline_sat:.4f} events/cycle "
        "(highest uniform offered load with loss <= 1% and throughput >= 95% of offered load)."
    )
    lines.append(f"- Adaptive normalized saturation: {adaptive_sat:.4f} events/cycle under the same rule.")
    if math.isinf(improvement):
        lines.append("- Relative improvement: undefined because the baseline did not meet the rule.")
    else:
        lines.append(f"- Relative saturation change: {improvement * 100.0:.2f}%.")
    lines.append("")
    lines.append("## Hotspot and Burst Behavior")
    lines.append("")
    lines.append(
        make_markdown_table(
            [
                "Traffic",
                "Baseline Loss",
                "Adaptive Loss",
                "Baseline Avg Lat",
                "Adaptive Avg Lat",
                "Adaptive Dense Packets",
            ],
            hotspot_text_rows,
        )
    )
    lines.append("")
    lines.append("## Threshold Sweep")
    lines.append("")
    lines.append(
        make_markdown_table(
            [
                "Threshold",
                "Avg Throughput",
                "Avg Loss",
                "Avg Latency",
                "Avg Phys Bits/Event",
                "Dense Packets",
                "Avg Dense Occ",
            ],
            threshold_rows,
        )
    )
    lines.append("")
    lines.append(
        f"- Stage 4 threshold recommendation: use {recommended_threshold} as the next primary "
        "candidate and keep threshold 5 as the conservative Stage 3 reference."
    )
    lines.append(
        "- This recommendation is based on the diagnostic subset average throughput, loss, "
        "latency, physical bits/event, and dense-packet use shown above."
    )
    lines.append("")
    lines.append("## Link-Width Sensitivity")
    lines.append("")
    lines.append(
        make_markdown_table(
            [
                "Link Width",
                "Architecture",
                "Avg Throughput",
                "Avg Loss",
                "Avg Phys Bits/Event",
                "Dense Packets",
            ],
            link_width_rows,
        )
    )
    lines.append("")
    lines.append("## Physical Dense Break-Even")
    lines.append("")
    for width in sorted(break_even):
        value = break_even[width]
        if value == 0:
            lines.append(f"- LINK_WIDTH={width}: no dense occupancy from 1..16 is strictly cheaper than sparse.")
        else:
            lines.append(f"- LINK_WIDTH={width}: dense is strictly cheaper at occupancy >= {value}.")
    lines.append("")
    lines.append("## Sparse-Traffic Penalty")
    lines.append("")
    lines.append(f"- Sparse uniform low-load physical result: {sparse_penalty}.")
    lines.append("- Area and power penalty are not measured in Stage 4; that belongs to Stage 5 PPA.")
    lines.append("")
    lines.append("## Cases Where Baseline Was Better")
    lines.append("")
    if baseline_better:
        for item in baseline_better[:12]:
            lines.append(f"- {item}")
    else:
        lines.append("- None under the primary 16-bit always-ready comparison using the configured significance rule.")
    lines.append("")
    lines.append("## Cases Where Adaptive Was Better")
    lines.append("")
    if adaptive_better:
        for item in adaptive_better[:12]:
            lines.append(f"- {item}")
    else:
        lines.append("- None under the primary 16-bit always-ready comparison using the configured significance rule.")
    lines.append("")
    lines.append("## Stage 4 Questions")
    lines.append("")
    lines.append(f"- Q1: Under equal 16-bit bandwidth, does adaptive sustain a higher event rate? {q1}.")
    if baseline_sat > 0:
        lines.append(f"- Q2: Measured saturation change is {improvement * 100.0:.2f}%.")
    else:
        lines.append("- Q2: Not computed because the baseline did not satisfy the saturation rule.")
    lines.append("- Q3: The locality/hotspot rows identify the density region where dense packets activate; see the tables and dense-occupancy plot.")
    lines.append("- Q4: Hotspot/burst loss behavior is shown in the hotspot and burst table.")
    lines.append("- Q5: Latency regressions or improvements are shown in the uniform and hotspot/burst tables.")
    lines.append("- Q6: Physical bits/event improvements are shown in the uniform, locality, and link-width plots.")
    lines.append("- Q7: Sparse penalty is measured above; it is physical-bit neutral for the default 16-bit wire format in low-load sparse traffic.")
    lines.append("- Q8: Physical dense break-even is listed above and includes header plus padding.")
    lines.append(f"- Q9: Threshold 5 is functional but the Stage 4 sweep recommends threshold {recommended_threshold} for the next primary candidate.")
    lines.append("- Q10: Link-width sensitivity is summarized for 8/16/32-bit links.")
    lines.append("- Q11: Stage 5 should synthesize the legacy baseline, normalized baseline wrapper, and adaptive wrapper selected from this table.")
    lines.append("")
    lines.append("## Limitations")
    lines.append("")
    lines.append("- Results are RTL simulation metrics only; no Cadence Genus area, power, or Fmax data is included.")
    lines.append("- The physical link is a simple valid/ready model, not a full pad or CDC implementation.")
    lines.append("- The adaptive dense snapshot storage is architectural state and must be counted in Stage 5 PPA.")

    DOC_PATH.parent.mkdir(parents=True, exist_ok=True)
    DOC_PATH.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT_DIR)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output-csv", type=Path, default=DEFAULT_OUTPUT_CSV)
    args = parser.parse_args()

    if args.manifest is not None:
        paths = read_manifest(args.manifest)
    else:
        paths = sorted(args.input_dir.glob("*.csv"))
    rows = read_rows_from_paths(paths)
    output_csv = args.output_csv.resolve()
    write_summary_csv(rows, output_csv)
    generate_plots(rows)
    write_analysis_doc(rows, output_csv)
    print(f"[SUMMARY] {output_csv.relative_to(ROOT)} rows={len(rows)}")
    print(f"[PLOTS] {PLOT_DIR.relative_to(ROOT)}")
    print(f"[DOC] {DOC_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
