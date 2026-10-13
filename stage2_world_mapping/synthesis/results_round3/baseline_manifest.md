# Round 3 baseline preservation manifest

Round 2 E-lite CORDIC remains the frozen main design. No baseline RTL was edited for this experiment. Byte-for-byte copies are stored under `synthesis/results_round3/snapshot/rtl/`.

| RTL file | SHA-256 |
|---|---|
| `rtl/numeric/wm_ray2angle.sv` | `700e8231a3f862add72f918c14f831c6faa18141d09bab35a6a9f7e51541646e` |
| `rtl/numeric/wm_cordic_vectoring.sv` | `cd7ca2e7ddff0d0d60fbfdccf1c88b70e9265f0eacbd496f8e701d755c9e98d2` |
| `rtl/numeric/wm_isqrt.sv` | `a9fa32ed932697383e3689573418052e9c0d865cfb1a470af49f4101322e11b7` |
| `rtl/numeric/wm_world_quant.sv` | `8b097f8634d4a2ce6eb71ac0c6e1f74846bbb149f74a6f75db6f5017a5ee7fb0` |
| `rtl/numeric/wm_mapper_lane.sv` | `5499e67f0ff34a6578a35cc99d7b75dc5e5038a9aa8ea0ea54777d640fba6a75` |
| `rtl/control/wm_ctrl_pkg.sv` | `3296e87c8c83dad524895e92992a1511658d31505eb1c774723d08f036c17cfc` |
| `rtl/top/wm_world_mapper_top.sv` | `8d3f009b7af1b65308fe3243cb01f260a8aea3d7afde6782543faffc6e5e4e76` |

The hashes above describe the pre-experiment working files. Round 1 and Round 2 result directories were left untouched. The authoritative software direct-bin source is `codex/model/ray_address.py`, function `ray_q15_to_world_address_direct`, with constants `TAN_Q32` and `TAN2_Q32`.
