# Round 2 RTL change manifest

Only two synthesizable RTL files changed. The original copies were made before editing in `synthesis/round2_rtl_backup/` and copied into `synthesis/results_round2/rtl_backup/` after the functional regressions passed.

| RTL file | Change | Original SHA-256 | Modified SHA-256 |
|---|---|---|---|
| `rtl/numeric/wm_mapper_lane.sv` | Added CE-gated, resettable registers for the three interpolation results and valid before `wm_ray2angle`; lane latency is now 53 enabled edges, II=1. | `4052df5ad64c99043a8f6336deb238c5eacaf5d5f72ce04e021661501f08dd3f` | `5499e67f0ff34a6578a35cc99d7b75dc5e5038a9aa8ea0ea54777d640fba6a75` |
| `rtl/control/wm_ctrl_pkg.sv` | Set `LANE_LAT` to `RAY2ANGLE_LATENCY + 1` (53) for metadata alignment. | `fc1092b77d70fb0d7a00f0a9ade05e35cc8de5927c6e054d59851283f955cdc9` | `3296e87c8c83dad524895e92992a1511658d31505eb1c774723d08f036c17cfc` |

The numeric testbench `verification/numeric/tb_mapper_lane.sv` was also updated to expect 53 enabled edges and compare `valid_out` every edge against a CE-frozen reference pipeline. It is verification code, not RTL. No other synthesizable logic was edited.

