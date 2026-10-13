# Claims and evidence index

Headline claims for report preparation. Paths are repository-relative; each limitation narrows what the evidence establishes.

| Stage | Claim | Value | Evidence type | Source path | Limitation |
|---|---|---:|---|---|---|
| 1 | Model2 dense entry default | 3 events/block | RTL parameter | `rtl/adaptive/aer_adaptive_link_top.sv`, `aer_adaptive_top.sv` | Configurable default, not globally optimal. |
| 1 | Model2 exit boundary and persistence | Exit when occupancy ≤1; four consecutive low-hold cycles | RTL + directed test | `rtl/adaptive/aer_block_occupancy.sv`, `aer_mode_controller.sv`, `tb/tests/tb_mode_hysteresis_directed.sv` | Directed simulation passed locally; configurable defaults, not globally optimal. |
| 1 | Uniform 0.1 activity power | baseline 0.186781 mW; Model2 0.176253 mW | VCD-driven Genus power | `results/csv/stage4_model2_activity_power_summary.csv`, `results/{baseline_link,adaptive_link_model2}_power_uniform0p1/report_power.rpt` | Pre-layout link logic only; 487 events delivered by each. |
| 1 | Uniform 0.8 activity power | baseline 0.412392 mW; Model2 0.259101 mW | VCD-driven Genus power | same CSV; `results/*_power_uniform0p8/report_power.rpt` | Baseline delivered 2,604 vs Model2 3,761 of 4,010 offered. Not equal throughput. |
| 1 | Hotspot activity power | baseline 0.367159 mW; Model2 0.267633 mW | VCD-driven Genus power | same CSV; `results/*_power_hotspot0p8/report_power.rpt` | 4×4, p80, offered 0.8 workload only. |
| 1 | Burst activity power | baseline 0.223244 mW; Model2 0.170081 mW | VCD-driven Genus power | same CSV; `results/*_power_burst2_dur500/report_power.rpt` | Rate 2/duration 500 case only; delivered event counts differ. |
| 1 | Baseline / Model2 cell area at 10 ns | 9,502.470 / 15,759.702 | Genus area report | `results/baseline_link/report_area.rpt`, `results/adaptive_link_model2/report_area.rpt` | Link top; pre-layout synthesis area. |
| 1 | Model2 timing closure | 10 ns: +0.3 ps; tested 9.4 ns: 0 ps; 9.7 ns: +0.3 ps | Genus QoR/timing reports | `results/adaptive_link_model2*/report_{qor,timing}.rpt` | Tested points, not exact continuous Fmax or post-route timing. |
| 1 | Traffic-dependent benefit and break-even | Model2 improves throughput/loss in tested high-load cases; threshold 3 recommended for measured Stage 4 subset | RTL traffic sweep + analysis | `results/csv/stage4_model2_summary.csv`, `stage4_breakeven_summary.csv`, `docs/stage4_comparison_analysis.md` | Scripted traces, seeds and 16-bit link assumptions; not all traffic. |
| 2 | Complete mapper latency | 53 enabled edges, II=1 | RTL + numeric/system regression | `stage2_world_mapping/rtl/numeric/wm_mapper_lane.sv`, `rtl/control/wm_ctrl_pkg.sv`, `verification/numeric/results_integration/numeric_regression.txt` | CE-enabled latency; not system end-to-end latency. |
| 2 | Numeric RTL regression | PASS: 8,064 lane; 33,231 isqrt; 66,462 CORDIC; 33,231 ray/address vectors | RTL simulation | `stage2_world_mapping/verification/numeric/results_integration/` | Fixed-point contract and vectors only; does not prove pose accuracy. |
| 2 | Integrated system regression | 21/21 PASS; D2/E-lite equivalence PASS | RTL system simulation | `stage2_world_mapping/verification/system/results_integration/system_regression.txt` | Behavioral memories and modeled traffic. |
| 2 | No-reuse RD_LAT=3 40k comparison | E-lite 22,248 cycles / 56 stalls / 3,207 conflicts / 0.441 RMW/event; D2 33,568 / 11,374 / 16,957 / 1.000 | System regression | `stage2_world_mapping/verification/system/results_integration/system_regression.txt` | Separate from stress variant with explicit stalls; both delivered 40k, issue efficiency 0.914. |
| 2 | Round 2 MODE1 100 MHz logic PPA | D2 area 447,464.934, 33.3356 mW; E-lite area 493,230.690, 36.8067 mW | Genus synthesis, vectorless power | `stage2_world_mapping/synthesis/results_round2/round2_summary.md`, `evidence/final/FINAL_PPA.md` | Grid/world memories excluded; not total-chip PPA; vectorless pre-layout logic power. |
| 2 | Measured Sept 22 maximum frame-level rate | 110.070 M events/s | Decoded real-data frame intervals | `stage2_world_mapping/evidence/final/PEAK_FRAME_RTL.md`, `evidence/real_data_summary/` | Uses each measured frame interval; no physical microburst timing. |
| 2 | Historical nominalized rate | 162.75 M/s = 125,806 events / 773 µs median interval | Historical calculation, not measured frame peak | same peak-frame evidence | Must never be labeled measured peak rate. |
| 2 | Peak continuous sequence replay | Frames 789–791; 253,145 events, no drops or accumulating backlog | RTL replay under measured frame intervals and uniform-within-frame native-word arrival | `stage2_world_mapping/evidence/final/peak_sequence/`, `PEAK_FRAME_RTL.md` | Synthetic/identity architectural grid; replay arrival model cannot establish unknown physical microbursts. |
| 2 | Round 3 direct-bin decision | Exploration retained; production selects CORDIC | Synthesis and comparison evidence | `stage2_world_mapping/synthesis/results_round3/round3_summary.md`, `rtl/experimental/` | Direct-bin files are experimental, not production RTL. |

## Shared principle

Both stages amortize work when events share structure. Stage 1 groups communication according to event density; Stage 2 reuses grid reads and merges local world-memory updates according to spatial locality. They are separate architectures and their evidence must not be combined into a single performance claim.
