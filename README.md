# SCA AER: traffic-adaptive communication and world mapping

This repository contains two related but distinct event-camera hardware studies. Both investigate how to amortize work when events share exploitable structure.

## Stage 1 — Traffic-Adaptive AER communication

Stage 1 compares a conventional AER transmitter with sparse/dense packetization over a normalized physical link. The final adaptive direction is **Model2 with hysteresis**: dense packets are selected when a block reaches the entry threshold, and the mode is retained through short occupancy dips. The default entry threshold is 3, exit boundary is 1, and `HOLD_CYCLES` is 4.

Stage 1 amortizes **communication packet overhead as a function of event traffic and block occupancy**. It does not use the Stage 2 mapper or world-memory architecture.

Run the directed adaptive and hysteresis tests with Icarus Verilog:

```sh
scripts/run_adaptive_sim.sh
iverilog -g2012 -s tb_mode_hysteresis_directed -o /tmp/tb_hysteresis.vvp \
  rtl/adaptive/aer_mode_controller.sv tb/tests/tb_mode_hysteresis_directed.sv
vvp /tmp/tb_hysteresis.vvp
```

Run the Model2 traffic and break-even sweeps with Python 3 and Icarus Verilog:

```sh
python3 scripts/sweep_stage4_model2.py
python3 scripts/sweep_stage4_breakeven.py
```

Stage 1 Genus scripts and compact reports are in `scripts/genus_*model2*` and `results/adaptive_link_model2*/`. Activity-power comparisons are VCD-driven logic estimates for four workloads; they are not post-CTS or whole-chip power. The Model2 9.4 ns synthesis point closes with zero slack; this is a tested point, not an exact continuous Fmax search. See [Stage 1 Model2 evidence](docs/stage1_model2_evidence.md).

## Stage 2 — Event-to-world mapping accelerator

Stage 2 maps pixel events through a pose-dependent ray grid into a 256×128 world map. The selected architecture is E-lite: T32 grid, Q1.15 arithmetic, two mapper lanes, integer square root, CORDIC24/BAM32, native-word grid-read reuse, consecutive merge, and four banks. The complete mapper lane has 53 enabled edges and II=1. Stage 2 amortizes **world-memory updates as a function of spatial locality and repeated native-word/grid accesses**.

See [`stage2_world_mapping/README.md`](stage2_world_mapping/README.md) for architecture exploration, software models, RTL, tests, synthesis and real-data evidence.

## Evidence and repository layout

- `rtl/`, `tb/`, `scripts/`, `results/`, `docs/`: Stage 1 sources and compact evidence.
- `stage2_world_mapping/`: canonical Stage 2 project, with preserved development-history folders and curated final structure.
- `docs/CLAIMS_AND_EVIDENCE_INDEX.md`: headline claims, evidence paths and limitations across both stages.
- `integration_final/`: pre-integration hashes and final integration record.
- `stage2_repo_audit/`: audit and integration planning records.

Large raw recordings, full decode caches, VCD/SAIF, simulator build products and server snapshots remain local-only. The sampled two-frame Sept 22 traffic fixture used by the system test is retained under `stage2_world_mapping/reference/real_traffic/`.

## Shared principle and limits

The shared engineering principle is exploiting repeated structure to reduce amortized work. Stage 1 applies it to communication packetization; Stage 2 applies it to mapping and memory updates. They have separate inputs, architectures, verification and PPA evidence.

Neither stage demonstrates full-chip post-layout power. Stage 2 real recordings establish traffic behavior, not pose ground truth; the assumed uniform-within-frame arrival model does not recover physical sensor microbursts. See the stage-specific evidence documents for detailed limitations.
