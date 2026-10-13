# Codex Numeric RTL: Actual Interface Used by the Control Integration

> **Historical provenance note:** the original interface extraction below predates the final local integration. Current production RTL is in this repository and has a 53-enabled-edge complete mapper lane (52-edge `wm_ray2angle` plus the CE-enabled interpolation-output register). Current hashes are listed in `evidence/final/FROZEN_RTL_SHA256SUMS.txt`; the old hashes and external worktree path below are historical provenance only.

These notes were extracted by reading the frozen files, not from a prompt description:
- `rtl/include/wm_pkg.sv`
- `rtl/numeric/{wm_lerp,wm_isqrt,wm_cordic_vectoring,wm_ray2angle,wm_world_quant,wm_mapper_lane}.sv`
- `rtl/numeric/README.md`
- `verification/numeric/{tb_mapper_lane.sv,run_numeric_tests.py}`
- Exp05b `grid_load_contract.md`, `ray_to_address_contract.md`, `world_memory_format.md`

## Location and provenance

The numeric RTL exists **only in Codex's worktree**, uncommitted:
`/tmp/sca_aer_codex_modeling2/stage2_world_mapping/rtl/` (branch `stage2/codex-modeling`, base 5d271a4).

The control RTL references it in place (`--numeric-rtl` in `verification/system/run_system_tests.py`). Nothing was copied or modified. SHA-256 of the files integrated and verified:

```
05cae9c3fe1afb4afadfc3bde851002b01c5c435aeee6a2d1f5c0908240c78b5  rtl/include/wm_pkg.sv
cd7ca2e7ddff0d0d60fbfdccf1c88b70e9265f0eacbd496f8e701d755c9e98d2  rtl/numeric/wm_cordic_vectoring.sv
a9fa32ed932697383e3689573418052e9c0d865cfb1a470af49f4101322e11b7  rtl/numeric/wm_isqrt.sv
ec731b38bb9c1d389411c6c40cc182328b8b4068314b92420ab70bc7bd0040ae  rtl/numeric/wm_lerp.sv
4052df5ad64c99043a8f6336deb238c5eacaf5d5f72ce04e021661501f08dd3f  rtl/numeric/wm_mapper_lane.sv
700e8231a3f862add72f918c14f831c6faa18141d09bab35a6a9f7e51541646e  rtl/numeric/wm_ray2angle.sv
8b097f8634d4a2ce6eb71ac0c6e1f74846bbb149f74a6f75db6f5017a5ee7fb0  rtl/numeric/wm_world_quant.sv
```

## `wm_mapper_lane` (instantiated twice)

| Port | Dir | Width / type | Notes |
|---|---|---|---|
| `clk` | in | 1 | |
| `rst` | in | 1 | **active-high, synchronous** |
| `ce` | in | 1 | Global enable. When 0 **all** pipeline state and valid bits hold |
| `valid_in` | in | 1 | |
| `node00, node10, node01, node11` | in | `wm_pkg::ray3_t` = packed `{x,y,z}`, 3 × signed 16-bit Q1.15 (z = LSBs) | (gx,gy), (gx+1,gy), (gx,gy+1), (gx+1,gy+1) |
| `x_offset, y_offset` | in | 5 bits each | `x[4:0]`, `y[4:0]` (exact /32 numerators) |
| `valid_out` | out | 1 | Registered (`valid_pipe` of the CORDIC); aligned with outputs |
| `world_x` / `world_y` / `world_addr` | out | 8 / 7 / 15 | `world_addr = {world_y, world_x}`; combinational from registered BAM32 angles |

- Structure: 3 × combinational `wm_lerp` → `wm_ray2angle` (28-stage `wm_isqrt` + aligned delay → two 24-stage `wm_cordic_vectoring`) → combinational `wm_world_quant`.
- **Current complete lane latency: 53 enabled edges; II = 1.** `wm_ray2angle` contributes 52 edges; the lane's CE-enabled interpolation-output register contributes one. No internal ready/valid. The upstream must hold lane inputs while `ce = 0`.
- Simulation guards inside the lane: `$fatal` if `valid_in = 1` with X nodes/offsets, or a zero interpolated ray. Bubbles (`valid_in = 0`) are free. The control keeps known node values in the L registers at all times (reset to 0, then real nodes).
- The lane does **not** reject invalid pixels. The control unpacker removes events with x ≥ 960 or y ≥ 720 before dispatch and counts them.
- Horizontal interpolation results (`top`/`bottom`) are internal to `wm_lerp`: 18-bit, unsaturated, not ported. **Sharing them across events is not possible without changing Codex's modules.** See `DEFERRED_OPTIMIZATIONS.md`.

## Grid contract (Exp05b)

- 31 × 24 = 744 nodes, `node_idx = gy·31 + gx`, gy-major. Each node is `{ray_x, ray_y, ray_z}` signed Q1.15, 48 bits.
- Loaded in increasing `node_idx` into the inactive buffer; atomic commit.
- Verified: `verification/system/gen_system_vectors.py` regenerates Codex's `grid_test_image.csv` pose with Codex's own `make_fixed_t32_grid` and finds **744/744 nodes and indices identical**. The RTL grid store is then exercised end-to-end by the per-event address checks.

## World / memory contract (Exp05b, `wm_pkg`)

- `tile_x = wx[7:2]`, `tile_y = wy[6:2]`, `cell = 4·wy[1:0] + wx[1:0]`.
- `bank = tile_x[1:0] XOR ((−tile_y) mod 4)`; word = `{tile_y, tile_x[5:2]}` (9 bits, 512 words/bank).
- Per cell: 4-bit ON + 4-bit OFF saturating counters (max 15). One tile word = 128 bits.

## Control-side conventions not fixed by `wm_pkg` (no shared change required)

| Item | Control choice | Why it is not a shared-package change |
|---|---|---|
| Bit order inside a 128-bit tile word | cell c at bits `[8c+7:8c]` = `{ON[3:0], OFF[3:0]}` | `wm_pkg` defines only widths. Memory is control-owned. Golden files use the same layout |
| Polarity → plane | `pol = 1` → ON, `pol = 0` → OFF | Sensor polarity semantics are unknown (Exp03). The mapping is a control convention |
| Native-word transaction | `wm_ctrl_pkg::nword_t` (52 bits) | Control-side interface |
| Reset | active-high synchronous everywhere | Matches the numeric RTL |

**No `REQUIRED_SHARED_CHANGE.md` was needed.**
