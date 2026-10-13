# Synthesis Plan and Final Results

The planned Genus runs were completed. The final baseline is the Round 2 MODE1 comparison at 100 MHz; see `results_round1/`, `results_round2/`, and `results_round3/` for compact reports and summaries. Round 3 direct-bin is exploratory only; production retains CORDIC.

**Synthesis top: `wm_world_mapper_top`** (`rtl/top/wm_world_mapper_top.sv`).

Scripts:
- `synthesis/genus_wm.tcl` (one run; configured by environment variables);
- `synthesis/run_genus_sweep.sh primary|explore|diagnostic|all`;
- file lists `scripts/synth_mode1.f`, `scripts/synth_mode2.f`.

Flow: Cadence Genus, GPDK045 `gsclib045` slow corner (0.9 V / 125 °C), the same library paths as the Stage 1 flow. `read_hdl -sv -define SYNTHESIS` excludes simulation-only assertions.

## 1. Configurations (fair comparison)

| | D2 | E-lite |
|---|---|---|
| `MERGE_EN` | **0** | **1** |
| Everything else | identical | identical |

Identical in both builds:
- Numeric lane (T32, Q1.15, CORDIC24 + isqrt28, 53-enabled-edge complete lane latency) ×2 lanes;
- `REUSE_EN = 1`;
- `FIFO_DEPTH = 128`, `OUTBUF_DEPTH = 4`, `BQ_DEPTH = 4`, `RD_LAT = 1`;
- 4 banks, XOR_NEG bank map, 128-bit tile words;
- clock, uncertainty (0.2 ns), I/O delay (10 % of period), input transition, output load;
- memory abstraction mode.

`MERGE_EN = 0` leaves the merger's open-record path unused, so synthesis may remove it. That removal *is* the D2 vs E-lite logic difference.

## 2. Memory boundaries

| Item | Size | MODE 1 (primary) | MODE 2 (diagnostic) |
|---|---|---|---|
| A. Arithmetic/control logic | — | synthesized | synthesized |
| B. Grid storage `wm_grid_store` | 2 × 744 × 48 = **71,424 b** used. The behavioural array is 2,048 × 48 = 98,304 b because of parity-padded indexing | **black-box stub** (`synthesis/stubs/wm_grid_store_bb.sv`) | inferred registers + 8 read muxes, which **overstates** storage (padding) |
| C. World memory `wm_world_mem_model` ×4 | 4 × 512 × 128 = **262,144 b** (256 × 128 cells × (4 ON + 4 OFF)) | **black-box stub** (`synthesis/stubs/wm_world_mem_model_bb.sv`) | inferred registers (very large; may not finish; never report as architecture PPA) |

- **Primary D2 vs E-lite comparison = MODE 1.** Memories are then reported separately: grid store as a register-file / SRAM estimate, world memory as a macro estimate.
- World-memory access counts come from RTL simulation (records/event: E-lite 0.441 vs D2 1.000 on the real subset). Energy per access must come from a **cited** memory model, stated separately.
- **First-run check:** `genus_wm.tcl` prints `BLACKBOX-CHECK` lines and writes `check_design.rpt`.
  - Confirm both stubs are black boxes.
  - Confirm `u_lane0/u_lane1` and `g_bank[*].u_ctrl` still contain cells. If the tool treated a stub's outputs as constant and pruned downstream logic, MODE 1 is invalid and the stub handling must be fixed before comparing.

## 3. Hierarchy visibility

`set_db auto_ungroup none`. Reports: `report_area -depth 6`, `report_power -depth 6`, plus per-block area for:

| Block | Instance path |
|---|---|
| numeric lanes | `u_lane0`, `u_lane1` |
| ↳ integer sqrt | `u_laneN/u_ray2angle/u_isqrt` |
| ↳ CORDICs | `u_laneN/u_ray2angle/u_azimuth`, `.../u_elevation` |
| ↳ ray2angle alignment regs | `u_laneN/u_ray2angle` (own cells) |
| ↳ lerps / quant | `u_laneN/u_lerp_*`, `u_laneN/u_world_quant` |
| metadata pipes | `u_meta0`, `u_meta1` (2 × 53 × 32 b) |
| merger | `u_merge` |
| router | `u_router` |
| bank controllers | `g_bank[0..3].u_ctrl` (queues + RMW + bypass + 16 saturating adders/plane) |
| control | `u_fifo`, `u_unpack`, `u_dispatch`, `u_reuse`, `u_frame`, `u_outbuf` |
| verification counters | `u_status` (24 × 32-bit). **Report separately and subtract** from "architecture logic"; they exist for regression evidence |

## 4. Clock plan

| Point | Period | Role |
|---|---|---|
| 100 MHz | 10.0 ns | **Primary.** Traffic architecture was evaluated at this clock (2 lanes; worst real frame needs ≈ 90 % of issue capacity) |
| 150 MHz | 6.667 ns | Exploration |
| 200 MHz | 5.0 ns | Exploration. Not expected to close without retiming (combinational lerp in front of the isqrt, 24-stage CORDIC adds, bank modify stage) |

Report slack and the critical path (start/end points) for each point. Do not assume closure.

## 5. Metrics and derived figures

Per configuration and point:
- area (total, per block, MODE 1);
- worst slack / achieved period;
- power (vectorless first; activity-based later with SAIF from a single-DUT real-traffic simulation);
- cell count.

Derived figures **must use measured RTL issue efficiency and stalls, not nominal 2 events/cycle**:

```
sustained_events_per_cycle = events / cycles      (RTL sim, same trace, same RD_LAT)
sustained_events_per_s     = f_clk(achieved) x sustained_events_per_cycle
events_per_s_per_area      = sustained_events_per_s / area_MODE1
events_per_s_per_mW        = sustained_events_per_s / power
memory_accesses_per_event  = rmw_requests / events   (feeds separate memory energy)
```

Pre-synthesis RTL references (real Sept 22b subset, 40,000 events, synthetic poses, `RD_LAT = 1`, no injected stalls):

| | cycles | stalled | events/cycle | bank conflicts | RMW/event |
|---|---|---|---|---|---|
| D2 | 33,565 | 11,373 | 1.192 | 16,957 | 1.000 |
| E-lite | 22,245 | 56 | 1.798 | 3,207 | 0.441 |

Cycle counts include the 744-cycle initial grid load and pipeline fill/drain. They are simulation measurements with a behavioural 1R1W memory, not synthesis results.

## 6. Power evidence and limits

The accepted final Stage 2 figures are vectorless pre-layout logic power (D2 33.3356 mW, E-lite 36.8067 mW). Activity-based power remains unresolved because RTL-to-gate annotation coverage was insufficient. MODE1 excludes grid and world memories; these are not total-chip power figures. No post-CTS clock-tree power is available.
