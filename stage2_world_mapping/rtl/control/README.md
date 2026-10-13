# Stage 2 V1 Control / System RTL (Claude-owned)

Integrates the frozen, verified Codex numeric lanes (`wm_mapper_lane`, read-only) into the V1 architecture. Interface facts: `CODEX_INTERFACE_NOTES.md`. Deferred items: `DEFERRED_OPTIMIZATIONS.md`. System tests: `../../verification/system/`.

## Hierarchy

```
wm_world_mapper_top                 (rtl/top)
├── wm_input_fifo        u_fifo     native-word FIFO, 128 words (param)
├── wm_frame_ctrl        u_frame    grid loader, atomic commit, swap, drain/release
├── wm_word_unpacker     u_unpack   one held word -> <=2 events/cycle, invalid drop
├── wm_lane_dispatch     u_dispatch D stage: bundle + grid buffer binding (gsel)
├── wm_grid_store        u_grid     2 buffers x 4 parity sub-banks (behavioural)
├── wm_reuse_cache       u_reuse    L stage: node fetch with cell-key reuse
├── wm_mapper_lane       u_lane0/1  numeric lane, 53 enabled edges, II=1
├── wm_meta_pipe         u_meta0/1  53-stage metadata delay, same ce
├── wm_skid_buffer       u_outbuf   mapped-bundle buffer (4); full -> mapper_ce=0
├── wm_elite_merger      u_merge    consecutive-only native-group merge (MERGE_EN)
├── wm_bank_router       u_router   atomic 2-record steering into 4 bank queues
├── g_bank[0..3]
│   ├── wm_bank_update_ctrl u_ctrl  queue + RMW + RAW bypass + sat add + clear
│   └── wm_world_mem_model  u_mem   behavioural 512 x 128 b bank (sim only)
└── wm_status_counters   u_status   counters (status_t)
```

## Timing and control

- **One global enable:** `mapper_ce = !outbuf_full && !ext_stall`.
  - It advances the unpacker issue, the D and L stages, both numeric lanes and both metadata pipes together.
  - No lane is ever stalled alone.
  - The stall source is a registered occupancy compare.
- Per-event path: FIFO → unpack (issue) → **D** register → **L** register (nodes, offsets, metadata) → lane (53 enabled edges) → output buffer (captured only on `ce = 1` edges, so each lane result is consumed exactly once).
- **Metadata alignment:**
  - `wm_meta_pipe` has 53 stages and shifts only on `mapper_ce`, fed from the same L-stage registers as `valid_in`.
  - A simulation assertion requires `lane.valid_out == meta.v` every cycle.
  - The system tests check every event's carried `(x, y)` against its expected world address, in order, under random `ce` stalls.
- **In-flight capacity:** up to 2 × (2 + 53) = 110 events between issue and capture, plus 4 buffered bundles. `inflight` is tracked for the merger's end-of-stream flush.

## Grid double buffer: safe reload point

- An event touches grid memory only in the **D stage**. On the D→L enabled edge its four nodes are copied into the L-stage registers, and the numeric lane receives node **values**.
- A DRAINING buffer is therefore released on the first cycle in which no D-stage event carries its `gsel`, and the reuse-cache keys referring to it are invalidated in that cycle.
- **It does not wait for the 53-cycle numeric pipeline.**
- New-frame words are loaded only after the swap, so no event can bind to a DRAINING buffer.
- A grid becomes READY only after all 744 nodes were written in order without error. Commit is refused otherwise (tested with a 500-node partial load).

## Grid read bandwidth (logical)

- Each lane needs four nodes (one per parity sub-bank) per *miss*. With two lanes that is **2 read ports per sub-bank, 8 node reads/cycle peak**.
- The behavioural model provides exactly these ports.
- Reuse (same cell in the lane's own or the other lane's registers, or lane 1 sharing lane 0's fetch in the same bundle) served 81 % of lane node sets without a grid read on the real subset.

## Memory

- 4 banks × 512 × 128-bit tile words, cleared in **512 cycles** (one word/cycle/bank in parallel; measured).
- RMW with parameterized read latency `RD_LAT` and a youngest-match write-history bypass of depth `RD_LAT`. Verified at RD_LAT 1 and 3 with random bank holds.
- Saturating ON/OFF 4-bit counters. Lost contributions are counted (`sat_loss_on/off`) for the conservation check.

## Differences from the earlier Claude RTL spec (`claude/rtl_spec/`)

- Reset is active-high synchronous (the numeric RTL's convention), not active-low.
- Horizontal-lerp reuse is deferred (not possible without changing Codex's lane). Reuse is node-fetch/address reuse keyed by grid cell `(gsel, gx, gy)`.
- FRAME_MARK and the LATEST policy are deferred. Frames are bound by the per-word frame id (STRICT).
- The merger's idle flush fires only when the whole upstream is empty, so `ce` stalls never split a group and RMW counts match the consecutive-merge reference exactly.
- Grid store: async-read behavioural array (replaceable).
