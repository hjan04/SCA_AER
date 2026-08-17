# SCA AER

Digital RTL project for comparing a conventional AER baseline against a future
traffic-adaptive AER architecture for DVS-like pixel event traffic.

## Current Stage

Stage 1 is implemented:

- conventional baseline AER RTL,
- two-level row/column round-robin arbitration,
- one-event-per-pixel pending capture semantics,
- `{polarity, y, x}` output packet,
- synchronous four-phase `REQ/ACK` output interface,
- directed self-checking baseline simulation.

Stage 2 baseline characterization is also implemented:

- reproducible trace generation,
- baseline RTL replay benchmark,
- per-run CSV metrics,
- summary CSV generation,
- diagnostic plots,
- baseline bottleneck and bitmap break-even analysis.

Stage 3 traffic-adaptive sparse/dense block bitmap AER is implemented:

- same one-event-per-pixel capture semantics as the baseline,
- sparse packet mode for low-density traffic,
- 4x4 dense block bitmap packet mode,
- directed self-checking adaptive simulation,
- preliminary Stage 2 trace replay and threshold sweep.

Final equal-bandwidth baseline-vs-adaptive claims are intentionally deferred
until Stage 4 adds a common fixed-width physical output link or serializer.

## Quick Start

Run the baseline directed tests:

```bash
scripts/run_baseline_sim.sh
```

Expected final line:

```text
BASELINE DIRECTED TESTS: PASS
```

The waveform is written to:

```text
results/waves/baseline_directed.vcd
```

Run a small benchmark smoke test:

```bash
scripts/sweep_baseline_traffic.py --preset smoke
```

Run the full Stage 2 baseline benchmark sweep:

```bash
scripts/sweep_baseline_traffic.py --preset stage2
```

This regenerates Stage 2 traces under `traces/generated/stage2/`, per-run CSVs
under `results/csv/runs/stage2/`, plots under `results/plots/`, and the tracked
summary `results/csv/baseline_summary.csv`.

Run the adaptive directed tests:

```bash
scripts/run_adaptive_sim.sh
```

Run the Stage 3 adaptive trace replay and threshold sweep:

```bash
scripts/sweep_adaptive_stage3.py
```

Stage 3 replay uses the Stage 2 generated traces. If those traces are missing in
a fresh clone, run the Stage 2 sweep first. The Stage 3 sweep regenerates
per-run adaptive results under `results/csv/runs/stage3/` and the tracked
summary `results/csv/adaptive_stage3_summary.csv`.

Generated traces, logs, waveforms, simulator binaries, and per-run result files
are ignored by Git because they are reproducible from these scripts. The compact
summary CSVs and analysis documents are tracked.

## Key Documents

- `docs/architecture_plan.md`: approved staged project plan.
- `docs/baseline_spec.md`: implemented Stage 1 baseline specification.
- `docs/benchmark_methodology.md`: Stage 2 trace and metric definitions.
- `docs/baseline_benchmark_analysis.md`: measured Stage 2 baseline behavior.
- `docs/adaptive_aer_spec.md`: implemented Stage 3 adaptive RTL specification.
- `docs/stage3_adaptive_analysis.md`: measured Stage 3 adaptive replay results.

## Main RTL

```text
rtl/common/
rtl/baseline/
rtl/adaptive/
```

The current baseline top is:

```text
rtl/baseline/aer_baseline_top.sv
```

The current adaptive top is:

```text
rtl/adaptive/aer_adaptive_top.sv
```

## Main Testbench

```text
tb/tests/tb_baseline_directed.sv
tb/tests/tb_adaptive_directed.sv
```
