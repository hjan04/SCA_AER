# Proposed RTL Block Decomposition (no RTL implemented)

This decomposition is for the recommended warp-grid mapper (`recommended_v1.md`). Block names are proposals. Widths marked "study" must come from Exp 02, not from this document.

```
                ┌───────────────── per-frame domain (slow) ─────────────────┐
pose_i ───────► │ frame_ctx  ──► warp_node_gen ──► warp_node_buf (ring of   │
frame_start_i   │ (pose regs,    (V1: yaw table  │  2–3 node rows, double   │
                │  double-buf)    V2: CORDIC)    │  buffered per frame)     │
                └────────────────────────────────┼──────────────────────────┘
                                                 │ node tile (4 nodes + grads)
pkt_i ─► mapper_input_if ─► event_warp_interp ◄──┘
        (sparse/dense,      (bilinear, 6 small mult)
         frame tag)                 │
                                    ▼
                            world_quantizer ─► world_addr_gen ─► [update_merge (final)] ─► wm_ctrl ◄──► wm_model (sim) / SRAM macro
                            (round, BAM,        (col,row →         (block patch            (RMW pipe,
                             band check)         bank/word/cell)    accumulator)            forwarding,
                                                                                            sat-add, epoch)
                                                                                    stats_counters ◄── all
```

## Blocks

| Block | Inputs | Outputs | Notes |
|---|---|---|---|
| `mapper_input_if` | `pkt_valid, pkt_ready, pkt_type, x, y, p` (sparse); `bx, by, valid_mask, pol_mask` (dense, final only); `frame_id` | Internal event/block stream with frame tag | Valid/ready. Dense path optional by parameter. Rejects packets whose frame's nodes are not ready (backpressure, never drop) |
| `frame_ctx` | `frame_start, pose (yaw, pitch, roll) or R`, `pose_valid` | Active/next pose registers | Double-buffered: frame k+1 nodes are generated while frame k events are consumed |
| `warp_node_gen` | Pose, config (`cx, cy, fx` or node table), grid row index | Node `(az_BAM, h or el)` for each grid point; optional gradients | V1: `az = ψ + α[gx]`, `h = (gy−cy)·c[gx]` from a small register table (W/T + 1 entries). V2: CORDIC rotation + 2 vectoring passes, iterative or lightly pipelined. Must finish a node row before the raster reaches it |
| `warp_node_buf` | Node stream | 4 corner nodes (+ per-tile gradients) for tile `(x>>t, y>>t)` | Raster mode: ring of 2–3 rows. Non-raster mode: full grid (parameter). Flags a "node not ready" stall |
| `event_warp_interp` | `fx_frac = x & (T−1)`, `fy_frac`, tile nodes | `az_fine`, `v_fine` with guard bits | `n00 + gx·fx + gy·fy + gxy·fx·fy`, using wrap-aware differences for azimuth (BAM subtraction) |
| `world_quantizer` | Fine coordinates | `(col, row)`, `in_band` | Round to nearest; BAM top-bit slice for column; clip/flag rows outside the band (counted, not silently dropped) |
| `world_addr_gen` | `(col, row)` | `bank, word_addr, cell_offset` | V1: linear address. Final: tile word + 2×2 parity bank |
| `update_merge` (final) | Mapped events of one block | ≤ 4 tile-word update records | Merges same-cell increments. Requires commutative semantics |
| `wm_ctrl` | Update records | SRAM read/write ports | RMW pipeline (read L cycles, modify, write); in-flight address CAM of depth L for forwarding; saturating add; epoch tag check/update; lazy decay (final) |
| `wm_model` | — | — | Behavioral SRAM, parameterized latency/ports/word width. **Simulation only**; cost is estimated separately |
| `stats_counters` | Events from all blocks | Counters | Events in/out, out-of-band, forwarding hits, stalls, saturations, merges, words written |

## Pipeline boundaries (initial proposal)

| Stage | Block | Register boundary rationale |
|---|---|---|
| S0 | `mapper_input_if` | Decouple handshake |
| S1 | node fetch | Buffer read |
| S2 | interp multiplies | Small multipliers |
| S3 | interp sum + round | Adder tree |
| S4 | addr gen | Bit slicing + bank select |
| S5..S5+L | `wm_ctrl` RMW | Memory latency L (model parameter) |

Target: II = 1 per event (mapper). Memory decides the sustained rate.

## Fixed-point formats needing study (Exp 02)

| Signal | Proposal to test | Driver |
|---|---|---|
| `x, y` | 10 b unsigned | Sensor |
| `x − cx` | 11 b signed (+1 fraction bit if cx is a half pixel) | Centre |
| Node azimuth | BAM, `log2(N_cols) + 3–4` guard bits (e.g., 16 b for 4096 cols) | Rounding error < 1/16 cell |
| Node h / el | `log2(N_rows) + 3–4` bits | Same |
| Gradients | signed, ~12–14 b | Exp 02 |
| Interp fractions | `log2 T` bits (5 for T = 32) | Exact |
| Column table α, c (V1) | 14 b / 12 b | `approximation_analysis.md` §2.4 |
| CORDIC internal (V2) | ~20 b + log2(iterations) guard bits | Exp 02 |
| Cell | 4 b (2 + 2) | Exp 06 |
| Epoch tag | 6–8 b | Clear/decay policy |

## Parameterization

`IMG_W, IMG_H, T, NCOLS_LOG2, NROWS, BAND_OFFSET, CELL_W, CELL_SEM, MEM_LAT, MEM_PORTS, N_BANKS, TILE_K, RASTER_NODES, DENSE_EN, NODEGEN = {YAW_TABLE, CORDIC}`.

## Backpressure behaviour

- `pkt_ready` is deasserted when (a) the node row needed for the incoming event is not yet generated (frame start, or a raster jump), or (b) the `wm_ctrl` input queue is full.
- No event is ever dropped except by an explicit, counted policy (out-of-band, invalid pose, optional overload mode).
- Frame boundary: `frame_ctx` swaps pose buffers only when the last event of the previous frame has passed `event_warp_interp`. A frame tag on every event makes this checkable.

## Memory interface (model)

`rd_en, rd_addr → rd_data after MEM_LAT`; `wr_en, wr_addr, wr_data`. The memory is dual-port (1R1W) by assumption in V1, stated in the report. A single-port variant halves sustained RMW rate. Word width = `CELL_W` (V1) or `TILE_K² · CELL_W + EPOCH_W` (final).

## Verification against the software golden model

1. **Three-level reference chain:**
   - Codex float golden (geometry truth);
   - a **bit-accurate fixed-point model** of exactly this datapath (node generation, interpolation, rounding, address, cell update), written in Python against the shared contract. This is a new model that Codex or the team must own;
   - the RTL.
2. RTL vs fixed-point model: **bit-exact** final map and per-event address trace on identical event and pose files. Commutative cell semantics make the final map order-independent, so the block path and the per-event path must produce *identical* maps.
3. Fixed-point model vs float golden: error statistics within the Exp 02 budget (≤ 0.25 cell).
4. Directed tests:
   - zero rotation (identity);
   - ψ = 90°/180°/270°;
   - wrap crossing;
   - back-to-back same address (forwarding);
   - saturation;
   - frame boundary with a stalled memory;
   - out-of-band rows;
   - node-not-ready stall;
   - epoch rollover.
5. Real-trace replay: parsed DELTA events plus an estimated pose file. Compare against the fixed-point model only (no truth).
6. Reuse the Stage 1 trace-driver + Icarus flow, and the Genus scripts as synthesis templates. Memory is excluded from synthesis and estimated separately.
