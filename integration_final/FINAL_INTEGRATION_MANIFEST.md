# Final local integration manifest

## Sources

- Stage 1 authoritative source: `/home/hj/SCA_AER_model2_recovery`, detached source commit `1fbcb59` (`Add complete synthesis timing PPA and activity evidence`). Promoted reviewed Model2 files and selected verification, scripts and compact reports only.
- Stage 2 authoritative source: `stage2_integration_local/`. Canonical final RTL/evidence was overlaid by category into `stage2_world_mapping/`; historical Exp01–05b and Claude/Codex records were retained from the original tree.
- Round 3 direct-bin remains exploratory under `stage2_world_mapping/rtl/experimental/`; production retains CORDIC.

## Final RTL hashes (SHA-256)

Stage 1 promoted Model2 RTL:

| Path | SHA-256 |
|---|---|
| `rtl/adaptive/aer_adaptive_link_top.sv` | `4095f359bbf2459f5e844647382dc6e6a513ee627fc9e6683c6ed3947caada48` |
| `rtl/adaptive/aer_adaptive_top.sv` | `8c7e71bc613d02d4dce95b5ec73fbaba60f779fb79557c5a7e89f371b31c03b1` |
| `rtl/adaptive/aer_block_occupancy.sv` | `cd064599f16eb9ee4f39f01d13e5a925add19950a3bd57660b7e7d18dfa11e4b` |
| `rtl/adaptive/aer_mode_controller.sv` | `3439b4aa3219eb505aca6643c0a5a41c4cdd15c6e74ef42fff4f1e6ca0ff93b1` |

Stage 2 final production RTL:

| Path | SHA-256 |
|---|---|
| `stage2_world_mapping/rtl/numeric/wm_mapper_lane.sv` | `5499e67f0ff34a6578a35cc99d7b75dc5e5038a9aa8ea0ea54777d640fba6a75` |
| `stage2_world_mapping/rtl/control/wm_ctrl_pkg.sv` | `3296e87c8c83dad524895e92992a1511658d31505eb1c774723d08f036c17cfc` |
| `stage2_world_mapping/rtl/top/wm_world_mapper_top.sv` | `8d3f009b7af1b65308fe3243cb01f260a8aea3d7afde6782543faffc6e5e4e76` |
| `stage2_world_mapping/rtl/experimental/wm_direct_bin.sv` | `ef8c79e2db9e2e7982eaaa732da9fd77bb5466c4dcf861fcd7c057e7e4344653` |

The complete Stage 2 RTL hash inventory is `stage2_world_mapping/evidence/final/FROZEN_RTL_SHA256SUMS.txt`. `wm_mapper_lane.sv` includes the CE-enabled interpolation-output register; `wm_ctrl_pkg.sv` defines `LANE_LAT = RAY2ANGLE_LATENCY + 1`; complete mapper latency is 53 enabled edges.

## Validation executed

- Stage 1: `scripts/run_adaptive_sim.sh` — 12 directed adaptive cases PASS.
- Stage 1: `scripts/run_link_sim.sh` — serializer, baseline physical-link and adaptive physical-link directed suites PASS.
- Stage 1: Icarus compile/run of `tb_mode_hysteresis_directed` — PASS.
- Stage 2 numeric: `python3 verification/numeric/run_numeric_tests.py --build-dir /tmp/wm_numeric_build` — PASS: 8,064 mapper vectors (53 edges), 33,231 isqrt, 66,462 CORDIC, 33,231 ray/address; all tests passed.
- Stage 2 system: `python3 verification/system/run_system_tests.py --build-dir /tmp/wm_system_build` — `SYSTEM REGRESSION: 21/21 passed`.
- Complete lane latency is 53 enabled edges. Stage 1/Stage 2 Genus was not rerun during integration.

## Synthesis evidence

- Stage 1: standard baseline 10 ns reports at `results/baseline_link/`; Model2 10 ns at `results/adaptive_link_model2/`; tested Model2 9.4 ns and 9.7 ns reports at corresponding directories; activity-power reports and workload scripts are under `results/*_power_*` and `scripts/genus_*_power_*.tcl`. Implout constraint reconstruction is not promoted as primary evidence.
- Stage 2: compact Round 1/2/3 reports and summaries are under `stage2_world_mapping/synthesis/results_round{1,2,3}/`. Round 2 MODE1 100 MHz is the selected baseline. MODE1 excludes grid and world memories.

## Excluded from canonical tracked content

Raw `.dvs` recordings, full decoded Exp03 caches (`claude/verification_plan/exp03_cache/`), VCD/SAIF traces, simulator/build runtime directories, Xcelium/PBS/super-threading runtime outputs, full server snapshot trees and server tar archives remain local or ignored. The small selected fixture `stage2_world_mapping/reference/real_traffic/sept22b_f900_f901.npz` and compact evidence are retained. No backup/source tree was deleted.

## Known limitations

- Stage 2 activity-based power is unresolved; accepted power is vectorless pre-layout logic power only. MODE1 excludes grid/world memories and there is no post-CTS clock-tree power.
- Measured Sept. 22 maximum frame-level rate is 110.070 M events/s. Historical 162.75 M/s is nominalized from 125,806 events / 773 µs median interval, not a measured peak.
- Frames 789–791 (253,145 events) passed without drops or accumulating backlog under measured frame intervals and a uniform-within-frame native-word arrival model; physical sensor microburst timing is unknown.
- No trusted real pose ground truth; inferred roll is not ground truth. Sept. 15 recording unavailable in final recovered evidence. Four-bit counters saturate heavily; `CNT_W=4` and `FIFO_DEPTH=128` are configurable V1 engineering defaults.
- Stage 1 activity-power results are VCD-driven, pre-layout link-logic estimates, not post-CTS or whole-chip power. Tested 9.4 ns synthesis closure is a tested point, not an exact continuous Fmax search.

## Repository state

- Branch: `stage2/claude-architecture`
- HEAD at integration start: `5d271a4f02d6250732df8b87c1a345ebdc4b4af6`
- No staging, commit or push was performed.
- Recovery worktree, `stage2_integration_local/`, `stage2_server_final/` and its tar archive remain untouched as backups.
