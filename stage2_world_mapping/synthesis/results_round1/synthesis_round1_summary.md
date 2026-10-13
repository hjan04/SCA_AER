# Stage 2 Genus Round 1 synthesis summary

## Run and validation

- D2 and E-lite were synthesized in MODE1 with `MERGE_EN=0` and `MERGE_EN=1`, respectively, at a 10.0 ns target, using the GPDK045 slow library and `PVT_0P9V_125C`.
- D2 results were already present in `d2_mode1_100MHz/`. E-lite completed normally on Oct 11, 2026 in 3,838 seconds; its log ends with `Normal exit.`
- The current compatibility form in `synthesis/genus_wm.tcl` is preserved: `elaborate wm_world_mapper_top -parameters [list [list MERGE_EN $MERGE_EN]]`. No RTL or Stage 1 files were changed.
- Both `check_design.rpt` files report no unresolved references. E-lite identifies exactly `wm_grid_store` and `wm_world_mem_model_RD_LAT1` as empty modules. The mapped netlist instantiates those black-box modules, and its hierarchy includes both lane instances, the E-lite merger, router, and all four bank controllers. The memories are not inferred as registers.
- D2 and E-lite both have 92 violating paths at the 10 ns target. Area and timing figures below are synthesis estimates; they are not post-placement results.

## PPA comparison

| Metric | D2 | E-lite |
|---|---:|---:|
| Cell area | 472,094.406 | 517,957.974 |
| Net area | 174,891.068 | 190,361.452 |
| Total area (cell + net) | 646,985.474 | 708,319.426 |
| Leaf instances | 139,426 | 151,222 |
| Sequential instances | 23,313 | 26,799 |
| Combinational instances | 116,113 | 124,423 |
| Worst slack | -2,141.9 ps | -2,145.8 ps |
| TNS | -132,438.9 ps | -126,057.3 ps |
| Violating paths | 92 | 92 |
| Vectorless total power | 36.406 mW | 39.571 mW |

E-lite adds 45,863.568 cell-area units (**9.71%**) and 61,333.952 total-area units (**9.48%**). Its preliminary vectorless power is 3.165 mW higher (**8.69%**). Power is vectorless, not activity-based; the MODE1 memory black boxes contribute no modeled memory power, so these figures are useful for a rough logic comparison only.

## Critical paths and timing ceiling

- **D2:** `u_reuse/l1_n10_reg[x][11]` → `u_lane1/u_lerp_x` → ray2angle radial preparation → `u_lane1/u_ray2angle/u_isqrt/rem_pipe_reg[0][0]`. Data path: 11.795 ns; slack: -2.142 ns.
- **E-lite:** `u_reuse/l1_n10_reg[z][4]` → `u_lane1/u_lerp_z` → ray2angle radial preparation → `u_lane1/u_ray2angle/u_isqrt/root_pipe_reg[0][0]`. Data path: 11.810 ns; slack: -2.146 ns.

The path table shows the E-lite path spending its early delay in the combinational `u_lerp_z` multiplier/rounding logic before reaching the isqrt input. Both designs therefore remain dominated by the same interpolation-to-ray2angle/isqrt boundary; enabling merging does not create a new critical path. From the 10 ns constraint and worst slack, the current estimated minimum period is about 12.14 ns, or **82.3 MHz**, for both. This is a pre-optimization synthesis ceiling, not a measured silicon frequency.

## Hierarchical area estimate

The following E-lite entries come from `report_area_hier.rpt`. Cell and total area are shown. Rows under a parent are included in that parent, so component rows must not be added again to the lane or ray2angle rows.

| Block | Approx. cell area | Approx. total area | Notes |
|---|---:|---:|---|
| Both mapper lanes | 353,456 | 488,984 | About 69% of design total area; includes interpolation and ray2angle |
| Six interpolation blocks | 84,072 | 108,338 | About 15% of design total area |
| Both ray2angle blocks | 269,129 | 379,938 | Includes CORDIC, isqrt, and radial preparation |
| Four CORDICs | 189,718 | 273,935 | About 38.7% of design total area |
| Two integer square roots | 40,456 | 55,583 | About 7.8% of design total area |
| Input FIFO | 72,250 | 92,425 | Large non-arithmetic block |
| Four bank controllers | 49,651 | 67,069 | About 9.5% of design total area |
| Reuse logic | 8,124 | 10,416 | |
| E-lite merger | 6,116 | 8,284 | Survives with `MERGE_EN=1` |
| Router | 128 | 174 | Router logic survives; small area |
| Status counters | 9,755 | 11,834 | About 1.7% of design total area |

CORDIC is a significant area target: its four instances account for about 39% of total area. The two isqrt blocks are smaller at about 8%. Together they are about 46.5% of total area, enough to justify evaluating the existing direct-bin alternative later for area, while recognizing it is a separate algorithm/accuracy tradeoff and does not address the current interpolation boundary by itself.

## RTL evidence and cost/benefit

| Measure | D2 | E-lite | E-lite change |
|---|---:|---:|---:|
| Cycles | 33,565 | 22,245 | 33.7% fewer |
| Stalled cycles | 11,373 | 56 | 99.5% fewer |
| Bank conflicts | 16,957 | 3,207 | 81.1% fewer |
| Software consecutive-only RMW | 7,967,090 | 4,671,282 | 41.37% fewer |
| RTL RMW/event | 1.000 | 0.441 | 55.9% fewer per event |

For the same 40,000-event trace, E-lite improves events per cycle by about 50.9% (1.798 vs 1.192). At a common clock, that is roughly 38% more events per total synthesis area after accounting for E-lite's 9.48% total-area overhead. The measured stall, conflict, and RMW reductions are substantial; **the area overhead is justified for the tested traffic**, especially where world-memory access cost matters. The vectorless power increase is modest relative to this traffic reduction, but activity-based power and memory energy are still needed for an energy conclusion.

## Round 2 recommendation (do not implement yet)

Add one enabled-cycle pipeline cut **after the three combinational `wm_lerp` outputs and before `wm_ray2angle` in `rtl/numeric/wm_mapper_lane.sv`**. Register `ray_x`, `ray_y`, `ray_z`, and `valid_in` together on `ce` (clear valid on reset), then drive `wm_ray2angle` from those registered signals. Keep initiation interval 1. Since the lane output latency becomes 53 enabled edges, set the control-side `LANE_LAT` to `RAY2ANGLE_LATENCY + 1` so both metadata pipes remain aligned. This specifically separates the deep interpolation cone from the radial square/add and first isqrt stage seen in both critical paths.

