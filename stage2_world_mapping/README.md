# Stage 2 — Event-to-world mapping accelerator

## Task

Map each event-camera pixel through a pose-dependent ray grid into a fixed equirectangular world map and accumulate polarity counts. The design study targets a complete, synthesizable RTL path with bit-accurate fixed-point behavior and enough system-level scheduling to evaluate memory-update contention.

## Selected architecture

- E-lite control: two mapper lanes, native-word grid-read reuse, consecutive merge, four memory banks.
- T32 world-ray grid with Q1.15 signed rays and nested round-to-nearest-even interpolation.
- Integer square root, CORDIC24 vectoring using BAM32 angles, and world quantization.
- Complete mapper latency: **53 enabled edges**, II=1. The extra CE-enabled interpolation-result register is in `rtl/numeric/wm_mapper_lane.sv`; metadata uses `LANE_LAT = RAY2ANGLE_LATENCY + 1` in `rtl/control/wm_ctrl_pkg.sv`.
- World map: 256×128 cells with horizontal wrap and vertical clamp; ON/OFF counters are 4-bit saturating by default.

Round 3 direct-bin is design-space exploration only. Production RTL and Round 2 synthesis use CORDIC; direct-bin is isolated under `rtl/experimental/` and its reports under `synthesis/results_round3/`.

## Architecture exploration and software model

The preserved experiment chain covers rotation-only mapping (Exp01), architecture tournament (Exp02), real traffic/locality analysis (Exp03), dispatch/banking analysis (Exp04), numeric RTL contract (Exp05), and address/memory contract (Exp05b). `model/` contains the compact fixed-point Python model used by the canonical verification flows. `experiments/` holds selected sources/results; original `codex/` and `claude/` folders remain as provenance/history and compatibility paths for existing scripts.

The fixed-point and memory contracts are documented in `reference/codex_contracts/`. Grid layout is gy-major, 31×24 nodes; world addressing uses the specified wrap/clamp behavior and bank mapping.

## RTL

- `rtl/include/`: shared package types.
- `rtl/numeric/`: lerp, integer square root, CORDIC, ray-to-angle, quantizer and full lane.
- `rtl/control/`: input FIFO, word unpacker, dispatch, frame/grid control, reuse, merge, bank update, counters and memory models.
- `rtl/top/`: `wm_world_mapper_top` integration top.
- `rtl/experimental/`: Round 3 direct-bin exploration, excluded from normal synthesis file lists.
- `rtl/pre_round2_backup/`: historical 52-edge source snapshot; do not use it in production file lists.

The integration sources in this tree are authoritative for the final production RTL. The source snapshot used for integration remains at repository root in `stage2_integration_local/` as a backup; server snapshots remain backups.

## Verification

Requirements: Python 3 with NumPy, Icarus Verilog (`iverilog`/`vvp`), and Verilator.

```sh
python3 verification/numeric/run_numeric_tests.py --build-dir /tmp/wm_numeric_build
python3 verification/system/run_system_tests.py --build-dir /tmp/wm_system_build
```

The numeric regression covers 8,064 mapper-lane vectors, 33,231 integer-square-root vectors, 66,462 standalone CORDIC vectors, and 33,231 ray/address vectors. The final system regression contains 21 tests, including numeric/control integration, stalls, banking, saturation, frame/grid swap and a Sept 22 traffic subset. Results are recorded under `verification/{numeric,system}/results_integration/`.

For the 40,000-event, no-reuse, `RD_LAT=3` comparison: E-lite completed in 22,248 cycles with 56 stalls, 3,207 conflicts and 0.441 RMW/event; D2 used 33,568 cycles, 11,374 stalls, 16,957 conflicts and 1.000 RMW/event. Both delivered all events, with issue efficiency 0.914 and 31,348 saturated contributions. Do not mix these with stress-test runs that inject explicit stalls.

## Synthesis

Genus scripts and MODE1 memory stubs are in `synthesis/scripts/` and `synthesis/stubs/`; reports and summaries are in `synthesis/results_round1/`, `results_round2/`, and `results_round3/`. Results were produced with the Cadence Genus 23.14 flow and the documented library/corner and 100 MHz constraints.

Round 2 MODE1 at 100 MHz reports:

| Variant | Cell area | Total area | WNS | Vectorless power |
|---|---:|---:|---:|---:|
| D2 | 447,464.934 | 616,352.597 | 0 | 33.3356 mW |
| E-lite | 493,230.690 | 677,885.514 | 0 | 36.8067 mW |

MODE1 excludes grid and world memories. These are pre-layout logic results, not total-chip PPA. Accepted Stage 2 power evidence is vectorless pre-layout logic power. Activity-based power remains unresolved because RTL-to-gate annotation coverage was insufficient.

## Real-data evidence

The restored Exp03 decoder processed both available Sept 22 recordings. The measured maximum frame-level rate using each frame’s own interval is **110.070 M events/s**. The historical ~162.75 M/s value is 125,806 events divided by the 773 µs median interval; it is nominalized, not the measured peak frame rate.

Peak-sequence RTL replay covered frames 789–791: 253,145 events, no drops and no accumulating source backlog, under measured frame intervals and a uniform-within-frame native-word arrival model. Peak RTL throughput was approximately 180 M events/s at 100 MHz. This does not establish physical sensor microburst timing or pose accuracy.

Compact summaries and provenance are under `evidence/real_data_summary/` and `evidence/final/`. Full `.dvs` files and full decoded caches remain local-only and are not required for the documented compact evidence.

## Limitations

- Activity-based power is unresolved; accepted power numbers are vectorless pre-layout logic only.
- MODE1 excludes grid/world memories; no post-CTS clock-tree power or total-chip PPA is reported.
- Physical sensor microburst timing is unknown; the continuous-frame model is uniform within each measured frame interval.
- No trusted real pose ground truth is available; inferred roll is not ground truth.
- Sept 15 recording is unavailable in the final server evidence.
- Four-bit counters saturate heavily; `CNT_W=4` and `FIFO_DEPTH=128` are configurable V1 engineering defaults, not proven optima.

## Directory structure

```text
model/                         fixed-point reference model
experiments/                   Exp01–05b curated sources and results
rtl/                           final production and experimental RTL
verification/numeric/          numeric vectors, testbenches, result summaries
verification/system/           system tests, generator, result summaries
synthesis/scripts/             Genus scripts and MODE1 stubs
synthesis/results_round1/       initial synthesis comparison
synthesis/results_round2/       selected 100 MHz timing-closed design
synthesis/results_round3/       direct-bin exploration; not production
evidence/final/                 final verification, PPA, real-data and claims
evidence/review/                final review and technical audit
evidence/real_data_summary/     compact recording statistics/provenance
tools/exp03/                    restored decoder and traffic analyzer
docs/                           architecture and repository notes
```
