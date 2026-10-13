# Module Interfaces

Conventions:
- Single clock `clk`, active-low synchronous-deassert reset `rst_n`.
- All streams are **valid/ready**: a transfer happens when `valid && ready` at a rising edge.
- `valid` never depends combinationally on `ready`. `ready` may depend on `valid` only inside a module.
- Widths in `ALL_CAPS` are parameters. Ones marked † are `WAITING_FOR_CODEX_EXP05`.
- Shared types/parameters live in one package `wm_pkg` (the only file both agents edit; changes by agreement).

## 1. Core input transaction (decision: one native word per transaction)

**Choice: B, one native sensor word**, not one event.

| Reason | Evidence |
|---|---|
| Preserves the sensor's grouping (3.3–3.45 events/word), which feeds both reuse and merge | Exp03, Exp04 |
| 3.4× fewer input handshakes and FIFO entries per event | Exp03 |
| Event-per-transaction would force a re-grouping stage before the merger | Exp04 merge scope = native group |
| A single-event (XYPT) source is still expressible: one group, one-hot mask | — |

| Signal | Width | Meaning |
|---|---|---|
| `in_valid`, `in_ready` | 1, 1 | handshake |
| `in_type` | 1 | `0 = EVENTS`, `1 = FRAME_MARK` (end of frame `in_frame_id`; carries no events) |
| `in_frame_id` | `FRAME_ID_W` | frame the events belong to (modulo counter) |
| `in_x` | 10 | pixel column, 0..959 |
| `in_ga_valid` | 1 | group A present |
| `in_ga_group` | 7 | group index = y >> 3 (0..89 valid) |
| `in_ga_mask` | 8 | bit k ⇒ event at y = 8·group + k |
| `in_ga_pol` | 1 | polarity for every event of group A |
| `in_gb_valid`, `in_gb_group`, `in_gb_mask`, `in_gb_pol` | 1, 7, 8, 1 | group B, same column. **Absolute** group index: the adapter adds the sensor's `off` field |

Rules:
- Both groups belong to the same column `in_x`.
- Group B may equal group A (same 8 pixels, other polarity).
- Masks may be zero only if the corresponding `*_valid` is 0.
- A transaction carrying invalid coordinates (x ≥ 960, or `8·group+k` ≥ 720 for a set bit) is accepted. The invalid events are discarded and counted (`cnt_drop_invalid`); this mirrors Codex's "reject + flag".
- `FRAME_MARK` is optional but recommended. It flushes the merger's open record and closes per-frame counters. Without it, frame ends are inferred from `in_frame_id` changes.
- Event order inside a transaction: group A bits LSB→MSB, then group B bits LSB→MSB (matches the decoded stream order).

## 2. Grid load / commit port (from external node generator)

| Signal | Width | Meaning |
|---|---|---|
| `gw_valid`, `gw_ready` | 1, 1 | node write handshake |
| `gw_node_idx` | 10 | `gy·31 + gx`, 0..743 |
| `gw_ray` | 3 × `GRID_NODE_W`† | node ray (x, y, z) |
| `gc_valid`, `gc_ready` | 1, 1 | commit handshake |
| `gc_epoch` | `FRAME_ID_W` | frame id this grid is valid for |
| `grid_free` (out) | 1 | an inactive buffer is free for loading. Writes go to that buffer; `gw_ready = grid_free` |

## 3. Internal streams

| Stream | Producer → consumer | Payload |
|---|---|---|
| `bundle` | `wm_word_unpacker` → lanes | per lane: `ev_valid, x, y, pol, gsel(1), grp_tag(2), first_of_grp, last_of_grp`; per bundle: `frame_id`, `frame_mark` |
| `mapped` | lanes → `wm_out_skid` → `wm_elite_merger` | per lane: `ev_valid, bank, word_addr, cell, pol, grp_tag, last_of_grp, in_range`; bundle `frame_id, frame_mark` |
| `record[0..1]` | merger → router | `rec_valid, bank, word_addr, delta_vec[TILE_CELLS × DELTA_W] (per plane), n_events` |
| `bq_rec[b]` | router → `wm_bank_ctrl[b]` | one record |
| `mem_*[b]` | `wm_bank_ctrl[b]` ↔ `wm_mem_model[b]` | `rd_en, rd_addr, rd_data (after RD_LAT), wr_en, wr_addr, wr_data`, optional `mem_ready` |

`grp_tag` is a 2-bit rolling tag that changes at every new native group. Merge compatibility needs "same group" only between neighbours in stream order, so 2 bits suffice. `DELTA_W` = ceil(log2(8+1)) = 4, because one group holds ≤ 8 events.

## 4. Per-module summary

| Module | Purpose | Key params | State | Handshake | Verification responsibility |
|---|---|---|---|---|---|
| `wm_input_fifo` | Buffer native words | `FIFO_DEPTH_WORDS`, word width | RAM/regs, ptrs, occupancy, max-occupancy | in: valid/ready; out: valid/ready | no loss, order, full/empty, counters |
| `wm_word_unpacker` | Pop head word; extract ≤ 2 events/cycle; tag groups; drop invalid coords | `DISPATCH_MODE` | 16-bit remaining-mask, held word, grp_tag | out: bundle valid, global `adv` | every set bit issued once; order; odd counts; invalid drop |
| `wm_frame_ctrl` | Bind head word's frame_id to a grid buffer; manage buffer states | `GRID_POLICY`, `FRAME_ID_W` | per buffer: `{state, epoch}`; `active`; in-flight counters | gates unpacker (`grid_ok`) | no event uses a buffer of the wrong epoch; no reload while referenced |
| `wm_grid_store` | 2 buffers × 4 parity sub-banks of nodes | `GRID_NODE_W`† | node storage | write port; 2 lane read ports (4 nodes each), sync read, latency 1 | read-after-commit, parity mapping, boundary nodes |
| `wm_hcache` | 2-entry cache of horizontal vectors (top, bottom) keyed by `(gsel, x, gy)` | `HCACHE_EN, HCACHE_ENTRIES` | per entry: key, valid; data written at S3 | none (pipeline-internal) | hit ⇒ identical ray to recompute (bit-exact) |
| `wm_mapper_lane` | S1..Sa per event | Codex widths† | pipeline regs | `adv` enable | bit-exact vs Codex vectors (ray codes; addresses once the contract is frozen) |
| ↳ `wm_lerp` | `lerp(a,b,o)` with RNE + sat (Codex leaf) | widths† | none (combinational) | — | exhaustive/random vs Codex lerp |
| ↳ `wm_ray2angle` | ray → (az, el) angle codes | `ANG_ITERS`†, `ANGLE_W`† | pipeline regs (L_ANG) | `adv` | vs Codex integer reference (to be defined) |
| ↳ `wm_world_quant` | angle → `world_x` (wrap), `world_y` (clamp) | `WORLD_*`† | — | — | wrap endpoint, clamp edges |
| `wm_addr_gen` | `world_x, world_y` → tile, cell, bank, word_addr | `TILE_*`†, `BANK_FN` | — | — | bijection: every cell has exactly one (bank, addr, cell) |
| `wm_out_skid` | Break the `ready` path between merger and the global `adv` | depth 2 | 2 bundle regs | valid/ready | no loss/duplication under random stall |
| `wm_elite_merger` | Fold same-word events of one native group | `MERGE_EN, MERGE_THRESH, MERGE_SCOPE, ACC_MODE` | 1 open record | in valid/ready; out ≤ 2 records | conservation of events, per-cell delta sums |
| `wm_bank_router` | Steer ≤ 2 records into 4 bank queues | `BQ_DEPTH` | 4 queues (2 enqueue ports, 1 dequeue) | atomic accept of both records | no loss, per-bank order, no starvation |
| `wm_bank_ctrl` | RMW per record, RAW bypass, saturating add, init sweep | `RD_LAT, CNT_W†, ACC_MODE` | RMW pipeline, write-history[RD_LAT+1] | queue pop; `mem_ready` | RAW correctness, saturation, init |
| `wm_mem_model` | Behavioural SRAM (sim only) | `RD_LAT`, depth, width | array | — | — |
| `wm_status` | Counters | widths | counters | read-only regs | invariants |
