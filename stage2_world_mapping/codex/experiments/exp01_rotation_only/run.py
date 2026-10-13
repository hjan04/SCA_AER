#!/usr/bin/env python3
"""Run deterministic synthetic Experiment 01 and write its evidence."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

CODEX = Path(__file__).resolve().parents[2]
ROOT = CODEX.parents[1]
sys.path.insert(0, str(CODEX))

from evaluation.compare import make_mappers
from evaluation.complexity import operation_rows
from evaluation.metrics import summarize_errors
from model.common import (CameraConfig, angles_to_ray, angular_distance_deg,
                          project_world_direction, ray_to_world_pixel, world_pixel_distance)
from synthetic.generator import Event, project_feature, seeded_static_field


OUT = CODEX / "results" / "exp01"
OUT.mkdir(parents=True, exist_ok=True)
CFG = CameraConfig(sensor_w=960, sensor_h=720, world_w=256, world_h=128,
                   fx=800.0, fy=800.0)
SEED = 20261006
MODEL_NAMES = {"G": "Model G - geometric golden", "L": "Model L - yaw LUT", "A": "Model A - linear"}


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"no rows to write: {path}")
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def event_grid() -> list[Event]:
    yaws = [math.radians(d) for d in range(-40, 41, 1)]
    features = [
        (30.0, 0.0), (-30.0, 0.0), (0.0, 0.0), (65.0, 0.0), (-65.0, 0.0),
        (25.0, -30.0), (25.0, 30.0), (-50.0, -20.0), (50.0, 20.0),
        (math.degrees(math.atan(CFG.cx / CFG.fx)), 0.0),
        (-math.degrees(math.atan(CFG.cx / CFG.fx)), 0.0),
    ]
    events = []
    for fid, (az, el) in enumerate(features):
        for i, yaw in enumerate(yaws):
            e = project_feature(math.radians(az), math.radians(el), yaw, i, fid, CFG)
            if e is not None:
                events.append(e)
    # Seeded field makes the metric sweep reproducibly broader than handpicked points.
    for fid, (az, el) in enumerate(seeded_static_field(20, seed=SEED), start=len(features)):
        for i, yaw in enumerate(yaws):
            e = project_feature(az, el, yaw, i, fid, CFG)
            if e is not None:
                events.append(e)
    # Explicitly exercise world-azimuth wrapping around +/-180 degrees.
    wrap_cases = ((179.0, 179.0), (-179.0, -179.0))
    wrap_yaws = (175.0, 179.0, 180.0, -179.0, -175.0)
    fid = len(features) + 20
    for az, yaw in wrap_cases:
        for i, yaw_deg in enumerate(wrap_yaws):
            e = project_feature(math.radians(az), 0.0, math.radians(yaw_deg),
                                i, fid, CFG)
            if e is not None:
                events.append(e)
        fid += 1
    return events


def one_feature_track():
    rows = []
    mappers = make_mappers(CFG)
    for yaw_deg in range(0, 41):
        yaw = math.radians(yaw_deg)
        event = project_feature(math.radians(30), 0.0, yaw, yaw_deg, 0, CFG)
        if event is None:
            raise RuntimeError(f"+30 degree feature unexpectedly outside image at yaw {yaw_deg}")
        truth = (math.radians(30), 0.0)
        for code, mapper in mappers.items():
            recovered = mapper.map_angles(event.x, event.y, yaw)
            rows.append({"yaw_deg": yaw_deg, "model": code, "model_name": MODEL_NAMES[code],
                         "x": event.x, "y": event.y,
                         "angular_error_deg": angular_distance_deg(recovered, truth)})
    return rows


def build_metrics(events: list[Event]):
    mappers = make_mappers(CFG)
    rows = []
    for code, mapper in mappers.items():
        angles, pixels, truth_angles, truth_pixels = [], [], [], []
        for event in events:
            angles.append(mapper.map_angles(event.x, event.y, event.yaw))
            pixels.append(mapper.map_pixel(event.x, event.y, event.yaw))
            truth = event.truth_azimuth, event.truth_elevation
            truth_angles.append(truth)
            truth_pixels.append(ray_to_world_pixel(angles_to_ray(*truth), CFG))
        stats = summarize_errors(angles, pixels, truth_angles, truth_pixels, CFG)
        rows.append({"model": code, "model_name": MODEL_NAMES[code], **stats})
    return rows


def accumulation():
    features = [(math.radians(a), math.radians(e))
                for a, e in ((30, 0), (-30, 0), (0, 0), (55, 20), (-55, -20),
                             (20, 30), (-20, -30), (65, -10), (-65, 10))]
    yaws = [math.radians(d) for d in range(0, 41)]
    events = []
    for fid, (az, el) in enumerate(features):
        for i, yaw in enumerate(yaws):
            event = project_feature(az, el, yaw, i, fid, CFG)
            if event is not None:
                events.append(event)
    mats = {name: [[0 for _ in range(CFG.world_w)] for _ in range(CFG.world_h)]
            for name in ("naive", "golden", "lut", "linear")}
    mappers = make_mappers(CFG)
    for event in events:
        # Naive accumulation treats each image coordinate as a fixed direction,
        # ignoring the known camera yaw.
        nx = min(CFG.world_w - 1, max(0, int(event.x * CFG.world_w / CFG.sensor_w)))
        ny = min(CFG.world_h - 1, max(0, int(event.y * CFG.world_h / CFG.sensor_h)))
        mats["naive"][ny][nx] += 1
        for code, label in (("G", "golden"), ("L", "lut"), ("A", "linear")):
            wx, wy = mappers[code].map_pixel(event.x, event.y, event.yaw)
            mats[label][wy][wx] += 1
    concentrations = {}
    for name, matrix in mats.items():
        vals = [v for row in matrix for v in row]
        concentrations[name] = max(vals) / sum(vals) if sum(vals) else 0.0
        fig, ax = plt.subplots(figsize=(9, 4.8), constrained_layout=True)
        im = ax.imshow(matrix, origin="upper", aspect="auto", cmap="magma", interpolation="nearest")
        ax.set_title(f"{name.capitalize()} accumulation (synthetic stationary directions)")
        ax.set_xlabel("world map x (azimuth bin)")
        ax.set_ylabel("world map y (elevation bin)")
        fig.colorbar(im, ax=ax, label="event count")
        fig.savefig(OUT / f"{name}_accumulation.png", dpi=150)
        plt.close(fig)
    return concentrations, len(events), len(features)


def main(argv=None):
    global CFG, SEED
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sensor-w", type=int, default=960)
    parser.add_argument("--sensor-h", type=int, default=720)
    parser.add_argument("--fx", type=float, default=800.0,
                        help="synthetic/configurable focal length in pixels; not derived from 6 mm")
    parser.add_argument("--fy", type=float, default=800.0,
                        help="synthetic/configurable focal length in pixels; not derived from 6 mm")
    parser.add_argument("--world-w", type=int, default=256)
    parser.add_argument("--world-h", type=int, default=128)
    parser.add_argument("--seed", type=int, default=20261006)
    args = parser.parse_args(argv)
    CFG = CameraConfig(sensor_w=args.sensor_w, sensor_h=args.sensor_h,
                       world_w=args.world_w, world_h=args.world_h,
                       fx=args.fx, fy=args.fy)
    SEED = args.seed
    config_doc = {
        "experiment": "Experiment 01 - rotation only",
        "classification": {
            "competition_discussion_facts": {"sensor_resolution": "960x720", "focal_length_mentioned_mm": 6},
            "assumptions": {"rotation_known": True, "pitch_deg": 0, "roll_deg": 0,
                            "translation": 0, "camera_y_axis_follows_positive_image_v": True,
                            "euler_convention": "R = Rz(roll) * Ry(yaw) * Rx(pitch)"},
            "synthetic_parameters": {"fx_px": CFG.fx, "fy_px": CFG.fy,
                                     "principal_point": [CFG.cx, CFG.cy],
                                     "world_map": [CFG.world_w, CFG.world_h],
                                     "target_feature_deg": [30, 0], "yaw_primary_deg": [0, 40],
                                     "yaw_metric_sweep_deg": [-40, 40], "seed": SEED,
                                     "pixel_sampling": "round projected subpixel coordinate to nearest integer"}
        },
        "intrinsics_note": "fx/fy are configurable synthetic values; 6 mm was not converted to pixels",
        "models": {"G": "floating point full Euler geometric reference",
                   "L": "column angle LUT plus yaw; geometric vertical coordinate",
                   "A": "center-slope horizontal linear approximation plus yaw; geometric vertical coordinate"},
        "synthetic_ground_truth": "known stationary world directions generated and projected by this script; not competition ground truth"
    }
    (OUT / "config.json").write_text(json.dumps(config_doc, indent=2) + "\n", encoding="utf-8")
    events = event_grid()
    metrics = build_metrics(events)
    write_csv(OUT / "metrics.csv", metrics)
    write_csv(OUT / "complexity.csv", operation_rows(CFG))
    yaw_rows = one_feature_track()
    fig, ax = plt.subplots(figsize=(8, 4.8), constrained_layout=True)
    for code in ("G", "L", "A"):
        points = [r for r in yaw_rows if r["model"] == code]
        ax.plot([r["yaw_deg"] for r in points], [r["angular_error_deg"] for r in points],
                label=MODEL_NAMES[code])
    ax.set(xlabel="known camera yaw (degrees)", ylabel="great-circle mapping error (degrees)",
           title="Stationary +30° synthetic feature under yaw-only rotation")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.savefig(OUT / "mapping_error_vs_yaw.png", dpi=160)
    plt.close(fig)
    concentrations, accumulation_n, accumulation_features = accumulation()
    summary = [
        "# Experiment 01 summary",
        "",
        "This reproducible experiment uses synthetic stationary world directions as ground truth. It is not competition ground truth.",
        "",
        "## Setup",
        "",
        f"- Sensor: {CFG.sensor_w}x{CFG.sensor_h} (competition discussion resolution).",
        f"- `fx=fy={CFG.fx:.1f}` px are chosen synthetic parameters; the mentioned 6 mm focal length was not converted.",
        f"- Map: {CFG.world_w}x{CFG.world_h} equirectangular direction bins.",
        "- Pose is known; yaw varies, pitch/roll/translation are zero. Convention: `Rz(roll) * Ry(yaw) * Rx(pitch)`.",
        f"- Main accuracy sweep contains {len(events)} visible synthetic event observations over yaw -40° to +40°.",
        f"- Accumulation contains {accumulation_n} observations of {accumulation_features} fixed directions over yaw 0° to +40°.",
        "",
        "## Accuracy",
        "",
        "`metrics.csv` reports mean, median, p95, and maximum great-circle error and mean/maximum wrapped world-bin distance over the full visible synthetic event set.",
        "",
        "| Model | Mean angular (deg) | Median (deg) | P95 (deg) | Max (deg) | Mean world pixels | Max world pixels |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in metrics:
        summary.append(f"| {row['model']} | {row['mean_angular_error_deg']:.6f} | {row['median_angular_error_deg']:.6f} | {row['p95_angular_error_deg']:.6f} | {row['max_angular_error_deg']:.6f} | {row['mean_world_pixel_error']:.6f} | {row['max_world_pixel_error']:.6f} |")
    summary += ["", "## Accumulation concentration", "",
                "Concentration is exactly `maximum bin count / total event count`; higher means more counts occupy one bin, but this is only a simple sharpness indicator.", "",
                "| Accumulator | Concentration |", "|---|---:|"]
    for name, value in concentrations.items():
        summary.append(f"| {name} | {value:.6f} |")
    summary += ["", "## Interpretation limits", "",
                "Model G is the geometric reference for these configured pinhole assumptions. Model L and Model A implement yaw-only paths. These accuracy measurements do not establish operation under uncertain pose, calibration error, translation, real event noise, or competition recordings.",
                "Complexity figures are source-level conceptual operation estimates, not equivalent silicon area, timing, power, or PPA.", ""]
    (OUT / "experiment_summary.md").write_text("\n".join(summary), encoding="utf-8")
    print(f"Wrote Experiment 01 outputs to {OUT}")
    print(f"Visible metric events: {len(events)}; accumulation events: {accumulation_n}")
    for row in metrics:
        print(f"{row['model']}: mean={row['mean_angular_error_deg']:.6f} deg, "
              f"p95={row['p95_angular_error_deg']:.6f} deg, max={row['max_angular_error_deg']:.6f} deg")


if __name__ == "__main__":
    main()
