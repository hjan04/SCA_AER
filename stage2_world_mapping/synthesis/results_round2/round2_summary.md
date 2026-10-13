# Stage 2 Genus Round 2 summary

## Scope and result

This was the approved single-variable timing experiment: one CE-enabled pipeline boundary after `wm_lerp` and before `wm_ray2angle`, with metadata latency advanced from 52 to 53 enabled edges. II remains 1. Only `rtl/numeric/wm_mapper_lane.sv` and `rtl/control/wm_ctrl_pkg.sv` changed as synthesizable RTL; the numeric latency testbench changed to check 53 edges and valid alignment cycle by cycle. Hashes and pre-edit copies are in [rtl_change_manifest.md](rtl_change_manifest.md).

The `synthesis/genus_wm.tcl` compatibility fix was preserved. All Genus runs used MODE1, the `PVT_0P9V_125C` operating condition, and empty `wm_grid_store` and `wm_world_mem_model_RD_LAT1` modules as memory black boxes. No RTL change beyond the approved boundary was made.

## Functional and implementation checks

- Numeric regression: **PASS**. All four benches passed with bit-identical numeric outputs; the mapper lane checked 8,064 vectors at 53 enabled edges. isqrt, CORDIC, and ray2angle/world-quant checked 33,231, 66,462, and 33,231 vectors.
- System regression: **21/21 PASS** using the unchanged test matrix and Cadence Xcelium 23.09. This includes random CE stalls, metadata alignment, final memory equality, event conservation, grid swap, bank hazards, and the real traffic subset. The details are in [functional_regression.md](functional_regression.md).
- Verilator lint: no new width, latch, signedness, or undriven warnings versus the pre-change RTL snapshot. The same three pre-existing WIDTH warnings remain; `-Wall` returns nonzero because warnings are fatal.
- Genus structural checks: all runs exited normally and reported no unresolved references. E-lite retains both mapper lanes, the merger, router, and four bank controllers. Grid and world memories remain black-box instances; they are not inferred as registers. The input FIFO remains its intended register-based FIFO implementation.

## PPA results

Areas are Genus cell/net/total area units. Power is preliminary vectorless power from the default PDB frame, not activity-driven power. See [ppa_summary.csv](ppa_summary.csv) and each run directory for the source reports.

| Round / architecture | Period | Cell area | Net area | Total area | Seq / comb / leaf | WNS | TNS | Violating paths | Vectorless power |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Round 1 D2 | 10.000 ns | 472,094.406 | 174,891.068 | 646,985.474 | 23,313 / 116,113 / 139,426 | -2.1419 ns | -132,438.9 ps | 92 | 36.406 mW |
| Round 2 D2 | 10.000 ns | 447,464.934 | 168,887.663 | 616,352.597 | 23,413 / 109,418 / 132,831 | 0.0000 ns | 0 ps | 0 | 33.336 mW |
| Round 1 E-lite | 10.000 ns | 517,957.974 | 190,361.452 | 708,319.426 | 26,799 / 124,423 / 151,222 | -2.1458 ns | -126,057.3 ps | 92 | 39.570 mW |
| Round 2 E-lite | 10.000 ns | 493,230.690 | 184,654.824 | 677,885.514 | 26,919 / 118,438 / 145,357 | 0.0000 ns | 0 ps | 0 | 36.807 mW |
| Round 2 E-lite | 6.667 ns | 589,899.384 | 213,514.771 | 803,414.155 | 26,919 / 148,255 / 175,174 | -2.3526 ns | -229,087.9 ps | 141 | 68.415 mW |

At 100 MHz, both Round 2 architectures meet the Genus criterion (`WNS >= 0`, TNS 0, no violating paths). E-lite has **10.23% more cell area** and **9.98% more total area** than D2 in this Round 2 pair. The corresponding Round 1 total-area overhead was 9.48% (cell-area overhead 9.71%).

Compared with Round 1, the Round 2 mapped cell area decreased by 5.22% for D2 and 4.77% for E-lite; total area decreased by 4.73% and 4.30%, respectively. Sequential instances increased by 100 in D2 and 120 in E-lite, as expected for the added registers. Combinational instances fell by 6,695 and 5,985. Thus the measured net area change is favorable, but the aggregate reduction cannot be attributed solely to the pipeline boundary: Genus remapping/optimization changed the combinational implementation. Treat the sequential-count delta as the direct structural register cost and the full area deltas as measured flow results.

At 100 MHz the preliminary vectorless power is 33.336 mW for D2 and 36.807 mW for E-lite, a 10.41% E-lite increase. Round 1 estimates were 36.406 mW and 39.570 mW. The 150 MHz E-lite estimate is 68.415 mW; power rises with the requested frequency and timing-driven cell sizing. These estimates are useful only for relative early comparison under this same flow.

## Critical paths and timing ceiling

- **D2, 100 MHz:** `u_reuse/l1_n01_reg[z][1] -> u_lane1/u_lerp_z` arithmetic cone -> `u_lane1/ray_z_reg[2]/D`.
- **E-lite, 100 MHz:** `u_reuse/l1_n11_reg[z][10] -> u_lane1/u_lerp_z` arithmetic cone -> `u_lane1/ray_z_reg[9]/D`.
- **E-lite, 150 MHz:** `u_reuse/l0_n00_reg[y][4] -> u_lane0/u_lerp_y` arithmetic cone -> `u_lane0/ray_y_reg[9]/D`.

The new stage removed the serial interpolation/radial-preparation path from the first `wm_isqrt` register. Both 100 MHz designs now meet timing. The new dominant path ends at the added interpolation output register, so interpolation itself is the limiter; the 150 MHz report confirms this rather than showing a CORDIC, isqrt, CE-fanout, bank, or merger path. At 150 MHz the worst path data delay is about 8.735 ns, with about 0.285 ns setup/uncertainty allowance; this implies a pre-optimization ceiling near **9.02 ns / 111 MHz**. Round 1's roughly 82.3 MHz ceiling improved to about 111 MHz. The Round 2 150 MHz point does **not** close.

## Hierarchical area (Round 2 E-lite, 100 MHz)

Approximate cell area from `report_area_hier.rpt`; nested entries overlap their parent lane/ray2angle totals.

| Block | Approx. cell area | Share of top cell area |
|---|---:|---:|
| Two mapper lanes, including numeric and quantization logic | 327,317 | 66.4% |
| Three interpolation blocks per lane, combined | 60,710 | 12.3% |
| Two `wm_ray2angle` blocks, combined | 264,093 | 53.6% |
| Four CORDIC blocks, combined | 190,267 | 38.6% |
| Two integer square-root blocks | 39,679 | 8.0% |
| Input FIFO (`W52_DEPTH128`) | 72,345 | 14.7% |
| Four bank controllers, combined | 49,822 | 10.1% |
| Reuse cache | 8,929 | 1.8% |
| E-lite merger | 6,116 | 1.2% |
| Router | 140 | 0.03% |
| Status counters | 9,791 | 2.0% |

The CORDICs remain a material area target at about 39% of cell area; the two isqrt blocks add about 8%. A direct-bin design is therefore worthwhile as a **Round 3 area exploration**, after preserving this timing-closed baseline. The Round 2 data does not justify replacing CORDIC for the competition build without a bit-accuracy and timing comparison; if the area budget is acceptable, the current implementation is sufficient at 100 MHz.

## System performance and E-lite decision

On the real traffic subset, the extra latency added exactly one cycle to both designs (D2 33,565 to 33,566; E-lite 22,245 to 22,246). Issue efficiency remained 0.914. E-lite retained 56 stalled cycles, 3,207 bank conflicts, 8,871 merges, and 0.441 RMW/event; D2 retained 11,374 stalls, 16,957 conflicts, no merges, and 1.000 RMW/event. This preserves E-lite's 33.7% cycle reduction, 99.5% stall reduction, 81.1% bank-conflict reduction, and 41.37% modeled RMW reduction from Round 1.

E-lite's approximately 10% Round 2 area overhead is justified by those conflict, stall, cycle, and RMW reductions. Round 2 also confirms both variants meet 100 MHz. E-lite is the selected architecture.

## Recommendation

Accept the single Round 2 pipeline change: II=1 and numerical behavior are preserved, and the 100 MHz timing target closes. Keep the modified E-lite design as the current baseline and proceed to final PPA at 100 MHz. Do not plan a 150 MHz submission target from this result; it fails by 2.353 ns. Run a separate, controlled direct-bin area exploration as Round 3 if area reduction is needed, with timing and bit identity measured against this baseline. Do not stack another speculative timing register based on the current data; the measured new path is interpolation, which should be the target if higher frequency becomes a requirement.

Note: the existing Tcl's hierarchical `report_power -depth 6` command is not recognized by this Genus build and emits a diagnostic, but the flat `report_power` command completes and writes the preliminary power reports. Genus exits normally for all Round 2 runs.
