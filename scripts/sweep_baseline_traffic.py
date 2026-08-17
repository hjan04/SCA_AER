#!/usr/bin/env python3
"""Generate reproducible baseline AER traces and run RTL benchmark simulations."""

from __future__ import annotations

import argparse
import math
import os
import random
import subprocess
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRACE_DIR = ROOT / "traces" / "generated"
RESULT_DIR = ROOT / "results" / "csv" / "runs"
RAW_DIR = ROOT / "results" / "raw"
WAVE_DIR = ROOT / "results" / "waves"
RUN_SCRIPT = ROOT / "scripts" / "run_baseline_benchmark.sh"


@dataclass(frozen=True)
class RunConfig:
    traffic_type: str
    variant: str
    seed: int
    rate: float
    injection_cycles: int
    ack_delay: int = 0
    max_drain_cycles: int = 5000
    x_size: int = 16
    y_size: int = 16
    burst_start: int = 2000
    burst_duration: int = 500
    burst_rate: float = 1.0
    hotspot_x: int = 6
    hotspot_y: int = 6
    hotspot_w: int = 4
    hotspot_h: int = 4
    hotspot_probability: float = 0.8
    simultaneous_count: int = 0
    region_w: int = 16
    region_h: int = 16


def ensure_dirs() -> None:
    for directory in (TRACE_DIR, RESULT_DIR, RAW_DIR, WAVE_DIR, ROOT / "results" / "plots"):
        directory.mkdir(parents=True, exist_ok=True)


def event_count_for_rate(rng: random.Random, rate: float) -> int:
    whole = int(math.floor(rate))
    frac = rate - whole
    return whole + (1 if rng.random() < frac else 0)


def poisson_count(rng: random.Random, lam: float) -> int:
    if lam <= 0.0:
        return 0
    # Knuth's method is fine for the small lambdas used in this baseline sweep.
    limit = math.exp(-lam)
    k = 0
    product = 1.0
    while product > limit:
        k += 1
        product *= rng.random()
    return k - 1


def random_pixel(rng: random.Random, x_size: int, y_size: int) -> tuple[int, int]:
    return rng.randrange(x_size), rng.randrange(y_size)


def random_pixel_in_region(
    rng: random.Random,
    x_size: int,
    y_size: int,
    start_x: int,
    start_y: int,
    width: int,
    height: int,
) -> tuple[int, int]:
    max_x = min(x_size, start_x + width)
    max_y = min(y_size, start_y + height)
    return rng.randrange(start_x, max_x), rng.randrange(start_y, max_y)


def append_event(events: list[tuple[int, int, int, int]], cycle: int, x: int, y: int, pol: int) -> None:
    events.append((cycle, x, y, pol))


def generate_trace(config: RunConfig) -> list[tuple[int, int, int, int]]:
    rng = random.Random(config.seed)
    events: list[tuple[int, int, int, int]] = []

    if config.traffic_type in ("uniform", "sparse"):
        for cycle in range(config.injection_cycles):
            for _ in range(event_count_for_rate(rng, config.rate)):
                x, y = random_pixel(rng, config.x_size, config.y_size)
                append_event(events, cycle, x, y, rng.randrange(2))

    elif config.traffic_type == "poisson":
        for cycle in range(config.injection_cycles):
            for _ in range(poisson_count(rng, config.rate)):
                x, y = random_pixel(rng, config.x_size, config.y_size)
                append_event(events, cycle, x, y, rng.randrange(2))

    elif config.traffic_type == "hotspot":
        for cycle in range(config.injection_cycles):
            for _ in range(event_count_for_rate(rng, config.rate)):
                if rng.random() < config.hotspot_probability:
                    x, y = random_pixel_in_region(
                        rng,
                        config.x_size,
                        config.y_size,
                        config.hotspot_x,
                        config.hotspot_y,
                        config.hotspot_w,
                        config.hotspot_h,
                    )
                else:
                    x, y = random_pixel(rng, config.x_size, config.y_size)
                append_event(events, cycle, x, y, rng.randrange(2))

    elif config.traffic_type == "burst":
        for cycle in range(config.injection_cycles):
            in_burst = config.burst_start <= cycle < config.burst_start + config.burst_duration
            rate = config.burst_rate if in_burst else config.rate
            for _ in range(event_count_for_rate(rng, rate)):
                x, y = random_pixel(rng, config.x_size, config.y_size)
                append_event(events, cycle, x, y, rng.randrange(2))

    elif config.traffic_type == "simultaneous":
        pixels = [(x, y) for y in range(config.y_size) for x in range(config.x_size)]
        rng.shuffle(pixels)
        cycle = min(100, max(0, config.injection_cycles // 2))
        for x, y in pixels[: config.simultaneous_count]:
            append_event(events, cycle, x, y, rng.randrange(2))

    elif config.traffic_type == "locality":
        start_x = (config.x_size - config.region_w) // 2
        start_y = (config.y_size - config.region_h) // 2
        for cycle in range(config.injection_cycles):
            for _ in range(event_count_for_rate(rng, config.rate)):
                x, y = random_pixel_in_region(
                    rng,
                    config.x_size,
                    config.y_size,
                    start_x,
                    start_y,
                    config.region_w,
                    config.region_h,
                )
                append_event(events, cycle, x, y, rng.randrange(2))

    else:
        raise ValueError(f"unknown traffic type: {config.traffic_type}")

    events.sort(key=lambda item: item[0])
    return events


def run_name(config: RunConfig) -> str:
    rate = f"{config.rate:.3f}".replace(".", "p")
    return (
        f"{config.traffic_type}_{config.variant}_rate{rate}_"
        f"seed{config.seed}_ack{config.ack_delay}"
    )


def write_trace(path: Path, events: list[tuple[int, int, int, int]]) -> None:
    with path.open("w", encoding="ascii") as handle:
        for event_id, (cycle, x, y, polarity) in enumerate(events):
            handle.write(f"{event_id},{cycle},{x},{y},{polarity}\n")


def execute_run(config: RunConfig, dry_run: bool = False) -> Path:
    name = run_name(config)
    trace_path = TRACE_DIR / f"{name}.trace"
    result_path = RESULT_DIR / f"{name}.csv"
    log_path = RAW_DIR / f"{name}.log"
    wave_path = WAVE_DIR / f"{name}.vcd"

    events = generate_trace(config)
    write_trace(trace_path, events)

    if dry_run:
        print(f"[DRY] {name}: events={len(events)} trace={trace_path}")
        return result_path

    env = os.environ.copy()
    env.update(
        {
            "RUN_NAME": name,
            "TRACE_FILE": str(trace_path),
            "RESULT_FILE": str(result_path),
            "LOG_FILE": str(log_path),
            "WAVE_FILE": str(wave_path),
            "TRAFFIC_TYPE": config.traffic_type,
            "TRAFFIC_VARIANT": config.variant,
            "SEED": str(config.seed),
            "INJECTION_CYCLES": str(config.injection_cycles),
            "MAX_DRAIN_CYCLES": str(config.max_drain_cycles),
            "ACK_DELAY_CYCLES": str(config.ack_delay),
            "OFFERED_EVENTS_PER_CYCLE": f"{len(events) / config.injection_cycles:.8f}",
        }
    )

    print(f"[RUN] {name}: events={len(events)}")
    subprocess.run([str(RUN_SCRIPT)], cwd=ROOT, env=env, check=True)
    return result_path


def build_configs(preset: str) -> list[RunConfig]:
    if preset == "smoke":
        return [
            RunConfig("uniform", "smoke_rate0p10", 1, 0.10, 1000),
            RunConfig("hotspot", "smoke_4x4_p80_rate0p40", 1, 0.40, 1000),
            RunConfig("burst", "smoke_burst_rate2p00", 1, 0.01, 1000, burst_start=300, burst_duration=100, burst_rate=2.0),
        ]

    seeds = [1, 2, 3]
    injection_cycles = 5000
    max_drain_cycles = 5000
    configs: list[RunConfig] = []

    uniform_rates = [0.01, 0.05, 0.10, 0.20, 0.30, 0.40, 0.60, 0.80, 1.00, 2.00]
    poisson_rates = [0.05, 0.10, 0.20, 0.40, 0.80, 1.20]
    hotspot_rates = [0.05, 0.10, 0.20, 0.40, 0.80]

    configs.append(RunConfig("sparse", "uniform_rate0p01", 1, 0.01, injection_cycles))

    for rate in uniform_rates:
        for seed in seeds:
            configs.append(RunConfig("uniform", f"rate{rate:.2f}", seed, rate, injection_cycles, max_drain_cycles=max_drain_cycles))

    for rate in poisson_rates:
        for seed in seeds:
            configs.append(RunConfig("poisson", f"lambda{rate:.2f}", seed, rate, injection_cycles, max_drain_cycles=max_drain_cycles))

    for rate in hotspot_rates:
        for seed in seeds:
            configs.append(
                RunConfig(
                    "hotspot",
                    f"4x4_p80_rate{rate:.2f}",
                    seed,
                    rate,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                    hotspot_x=6,
                    hotspot_y=6,
                    hotspot_w=4,
                    hotspot_h=4,
                    hotspot_probability=0.8,
                )
            )

    for ack_delay in [1, 2, 4, 8]:
        configs.append(RunConfig("uniform", f"ack_delay_{ack_delay}", 1, 0.20, injection_cycles, ack_delay=ack_delay, max_drain_cycles=max_drain_cycles))

    for burst_rate, duration in [(1.0, 200), (2.0, 200), (2.0, 500), (4.0, 200)]:
        configs.append(
            RunConfig(
                "burst",
                f"burst_rate{burst_rate:.1f}_dur{duration}",
                1,
                0.01,
                injection_cycles,
                max_drain_cycles=max_drain_cycles,
                burst_start=2000,
                burst_duration=duration,
                burst_rate=burst_rate,
            )
        )

    for count in [4, 8, 16, 32, 64]:
        configs.append(
            RunConfig(
                "simultaneous",
                f"count{count}",
                1,
                count / injection_cycles,
                injection_cycles,
                max_drain_cycles=max_drain_cycles,
                simultaneous_count=count,
            )
        )

    for size in [16, 8, 4, 2]:
        for seed in seeds:
            configs.append(
                RunConfig(
                    "locality",
                    f"region{size}x{size}_rate0.20",
                    seed,
                    0.20,
                    injection_cycles,
                    max_drain_cycles=max_drain_cycles,
                    region_w=size,
                    region_h=size,
                )
            )

    return configs


def main() -> None:
    global TRACE_DIR, RESULT_DIR, RAW_DIR, WAVE_DIR

    parser = argparse.ArgumentParser()
    parser.add_argument("--preset", choices=["smoke", "stage2"], default="stage2")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-summary", action="store_true")
    args = parser.parse_args()

    TRACE_DIR = TRACE_DIR / args.preset
    RESULT_DIR = RESULT_DIR / args.preset
    RAW_DIR = RAW_DIR / args.preset
    WAVE_DIR = WAVE_DIR / args.preset

    ensure_dirs()
    configs = build_configs(args.preset)
    result_paths = [execute_run(config, dry_run=args.dry_run) for config in configs]

    if not args.dry_run and not args.skip_summary:
        subprocess.run(
            [
                str(ROOT / "scripts" / "summarize_baseline_results.py"),
                "--input-dir",
                str(RESULT_DIR),
                "--output-csv",
                str(ROOT / "results" / "csv" / "baseline_summary.csv"),
            ],
            cwd=ROOT,
            check=True,
        )

    print(f"[DONE] {len(result_paths)} benchmark configurations")


if __name__ == "__main__":
    main()
