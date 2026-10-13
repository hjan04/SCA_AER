# Stage 1 final Model2 / hysteresis evidence

## Architecture

Stage 1 addresses traffic-adaptive AER communication. The final implementation is the sparse/dense adaptive link with Model2 hysteresis, preserved from recovery source commit `1fbcb59` (`origin/model2-hysteresis`). It amortizes packet/header cost when multiple events occupy a dense spatial block. Stage 2 separately amortizes world-memory updates using locality.

The RTL defaults were verified directly in `rtl/adaptive/aer_adaptive_link_top.sv`, `rtl/adaptive/aer_adaptive_top.sv`, `rtl/adaptive/aer_block_occupancy.sv`, and `rtl/adaptive/aer_mode_controller.sv`:

- Dense entry threshold: **3** events in a block.
- Exit boundary: occupancy at or below **1** (hold is true above 1).
- `HOLD_CYCLES`: **4** consecutive cycles without the hold condition before leaving dense mode.

The controller supports immediate packet selection on the entry cycle and resets its exit counter when occupancy rises above the exit boundary. `tb/tests/tb_mode_hysteresis_directed.sv` exercises entry, low-occupancy persistence, transient recovery, counter reset and exit after the fourth low cycle.

## Evidence chain

1. Baseline behavior: `rtl/baseline/`, `tb/tests/tb_baseline*`, and `scripts/sweep_baseline_traffic.py`.
2. Adaptive sparse/dense architecture: `rtl/adaptive/aer_sparse_packetizer.sv`, `aer_dense_packetizer.sv`, `aer_block_occupancy.sv`, `aer_dense_block_selector.sv`; Stage 3/4 tests and summaries.
3. Model2 hysteresis: four Model2 RTL files listed above, plus the directed hysteresis test and adaptive directed regressions.
4. Traffic sweep: `scripts/sweep_stage4_model2.py`; summary `results/csv/stage4_model2_summary.csv` and provenance `stage4_model2_manifest.txt`.
5. Break-even sweep: `scripts/sweep_stage4_breakeven.py`; `results/csv/stage4_breakeven_summary.csv` compares baseline and adaptive at uniform offered rates 0.70, 0.85, 0.90 and 0.95 on a 16-bit link.
6. Genus PPA: scripts `genus_adaptive_link_model2.tcl`, `_9p4.tcl`, `_9p7.tcl`; primary reports in `results/adaptive_link_model2*/`. Baseline 10 ns reports are in `results/baseline_link/`.
7. Activity power: matched baseline/Model2 VCD-driven TCL scripts and per-case reports in `results/*_power_*`; compact comparison in `results/csv/stage4_model2_activity_power_summary.csv`.

## Activity-based power comparisons

These values come from Genus `report_power` after reading workload VCD activity into the mapped adaptive/baseline link design. The CSV also records delivered events, loss, throughput, latency and energy per delivered event. Because baseline and Model2 can deliver different event counts at high load, comparisons describe the specified workload runs; they are not equal-throughput claims.

| Workload | Baseline power | Model2 power | Delivered events (baseline / Model2) | Source |
|---|---:|---:|---:|---|
| Uniform 0.1 | 0.186781 mW | 0.176253 mW | 487 / 487 | `results/csv/stage4_model2_activity_power_summary.csv`; `results/*_power_uniform0p1/report_power.rpt` |
| Uniform 0.8 | 0.412392 mW | 0.259101 mW | 2,604 / 3,761 of 4,010 | same CSV; `results/*_power_uniform0p8/report_power.rpt` |
| Hotspot 4×4, p80, offered 0.8 | 0.367159 mW | 0.267633 mW | 2,506 / 3,075 | same CSV; `results/*_power_hotspot0p8/report_power.rpt` |
| Burst rate 2, duration 500 | 0.223244 mW | 0.170081 mW | 459 / 866 | same CSV; `results/*_power_burst2_dur500/report_power.rpt` |

This is activity-based pre-layout logic/link power from VCD-driven Genus analysis. It is **not** post-CTS, whole-chip, or board power. Do not present it as measured silicon energy.

## PPA and timing

At a 10 ns clock, baseline cell area is 9,502.470 and Model2 is 15,759.702. Reported WNS is +0.2 ps and +0.3 ps, respectively. Genus reports identify the slow library and `PVT_0P9V_125C`; these are synthesized link-top results, not physical signoff.

Model2 closes at the **tested 9.4 ns synthesis point** with 0 ps slack and at 9.7 ns with +0.3 ps slack. 9.4 ns corresponds nominally to about 106.4 MHz, but this is a tested point, not an exact continuous Fmax search.

## Implementation-output caveat

The `genus_adaptive_link_model2_implout.tcl` experiment reconstructs implementation-output constraints from a document and explicitly describes them as best-effort. No matching complete final result set was identified. It is not promoted as primary evidence. The standard synthesis scripts and reports above are the primary PPA evidence.

## Recommendation and limitations

The Stage 4 analysis recommends threshold 3 as the primary candidate based on its measured traffic subset; the Model2 hysteresis implementation then uses entry 3, exit boundary 1 and four-cycle hold. Preserve the tested workload/configuration with every claim. Model2 is not proof of universal optimality, unconstrained real-time behavior, post-layout power, or all-sensor traffic performance.

## Local validation

The final recovery RTL passed `scripts/run_adaptive_sim.sh` (12 directed adaptive cases), `scripts/run_link_sim.sh` (serializer, baseline-link and adaptive-link directed suites), and the standalone `tb_mode_hysteresis_directed` Icarus test. The directed hysteresis test passed entry, hold, transient recovery and exit behavior. No Genus run was repeated during integration; the reports cited above are the recovered synthesis evidence.
