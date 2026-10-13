# RTL Verification Plan

Reference chain:
- Codex Exp05 bit-accurate Python model (ray codes; world addresses once the ray→angle contract is frozen);
- the Exp03 real-stream decoder (stimulus);
- a cycle-agnostic **transaction scoreboard** (expected per-cell totals);
- the RTL.

The simulator follows the Stage 1 flow (Icarus Verilog + file-driven traces + Python checkers).

## Status counters (`wm_status`)

| Counter | Meaning |
|---|---|
| `cnt_words_in`, `cnt_events_in` | Accepted native words / events (popcount of valid masks) |
| `cnt_drop_invalid` | Events with invalid coordinates (expected 0 on real data after decode) |
| `cnt_events_issued` | Events issued to lanes |
| `cnt_events_mapped` | Events leaving `wm_addr_gen` |
| `cnt_out_of_range` | Events removed by a vertical drop policy (0 with clamp) |
| `cnt_records`, `cnt_records_merged`, `cnt_events_in_merged` | Records emitted; records with `n_events ≥ 2`; events they carry |
| `cnt_hcache_hit`, `cnt_hcache_xhit`, `cnt_node_reads` | Reuse effectiveness |
| `cnt_bank_rmw[4]`, `cnt_bank_bypass[4]` | RMW per bank; RAW bypass uses |
| `cnt_bank_dual_enq[4]` | Same-bank pairs (case C) |
| `cnt_router_stall`, `cnt_adv_stall`, `cnt_grid_wait`, `cnt_fifo_full` | Stall cycles by cause |
| `fifo_max_occ_words`, `fifo_max_occ_events`, `bq_max_occ[4]` | High-water marks |
| `cnt_sat[4]` | Cell saturations per bank |
| `cnt_stale_grid_events` | `LATEST` policy only |
| `frames_in`, `frames_out`, `max_frame_lag_cycles` | Frame backlog / deadline indicator |

## Global invariants (assertions, checked every cycle in simulation)

```
cnt_events_in == cnt_events_issued + cnt_drop_invalid + events_in_fifo + events_in_unpack_hold
cnt_events_issued == cnt_events_mapped + events_in_lanes + events_in_skid
cnt_events_mapped == cnt_out_of_range + events_in_open_record + Σ n_events(records emitted)
Σ n_events(records emitted) == Σ n_events(records retired by banks) + records_in_queues/pipes (weighted)
At quiescence (drained):  cnt_events_in == Σ over memory of cell counts (if no saturation) + cnt_drop_invalid + cnt_out_of_range
Ideally: cnt_drop_invalid == 0, cnt_out_of_range == 0, no upstream drops.
```

Local assertions:
- valid/ready stability: payload stable while `valid && !ready`;
- no `valid` → `ready` combinational dependence (lint/structural);
- an event never reads a grid buffer that is not ACTIVE or DRAINING with a matching epoch;
- no node write to an ACTIVE/DRAINING buffer;
- hcache hit data == recomputed data (shadow check in simulation: compute both and compare);
- per bank: at most one RMW issue per cycle; the bypass picks the youngest match;
- merger emits ≤ 2 records/cycle; `MERGE_EN = 0` ⇒ `n_events = 1`.

## Levels

| Level | Scope | Stimulus | Pass criterion |
|---|---|---|---|
| **L1 Unit** | `wm_lerp` (exhaustive over offset 0..31 × random/edge deltas), `wm_input_fifo`, `wm_word_unpacker` (all 2^16 masks for order and cycle count), `wm_addr_gen` (all world cells → bijection), `wm_hcache`, `wm_frame_ctrl` FSM, `wm_bank_ctrl` (RD_LAT 1..3) | Directed + random | Exact match to small golden functions |
| **L2 Mapper lane** | One lane, S1..Sa | Codex `rtl_vectors.csv` (8,064 vectors, 4 poses) + `rtl_smoke_vectors.csv` | **Bit-exact `ray_q`** now. Bit-exact `world_x/world_y` once the angle contract is frozen. Native-group vectors (`map_native_group`) must match independent mapping |
| **L3 Two-lane dispatch** | Unpacker + 2 lanes + hcache | Real words from the Exp03 decoder; synthetic odd/even masks; straddling words | Every event mapped once; order kept; issue cycles == `analysis/dispatch_model.py` count for the same stream |
| **L4 E-lite merge** | Merger + router | Codex `merge_reference_cases.csv` + random groups | Per-cell delta sums exact; RMW count == Codex reference in `run` mode (request); `MERGE_EN = 0` gives 1 record/event |
| **L5 Bank/memory hazards** | Router + 4 bank ctrls + mem models | Directed: back-to-back same word (A,A,A), alternating (A,B,A,B), all four banks, same bank different words, `mem_ready` random stalls, RD_LAT 1..3, saturation | Final memory == scoreboard; no lost/duplicated update; bypass counter > 0 where expected |
| **L6 Real-traffic replay** | Full top | All three decoded recordings (frame-tagged words), grids from Codex's generator for synthetic pose tracks (Exp04 POSE-0 / POSE-ROLL) | Final map == Codex model's map for the same pose/grid set; counters reported (stalls, FIFO max, frame lag, hit rate, RMW reduction); **0 drops in stallable mode**; FIFO high-water in non-stallable mode documents the real burst requirement |
| **L7 Regression** | All above | Seeds × parameter matrix: `MERGE_EN`, `HCACHE_EN`, `HCACHE_XLANE`, `RD_LAT`, `BQ_DEPTH`, `FIFO_DEPTH_WORDS`, `GRID_POLICY`, `DISPATCH_MODE`, `ACC_MODE` | All pass; D2 build and E-lite build produce **identical final maps** (commutativity) with different RMW/activity counts |

## Key cross-check enabled by the architecture

Because accumulation is commutative and merging only regroups deltas, **D2 (`MERGE_EN = 0, HCACHE_EN = 0`) and E-lite must give bit-identical world memories for any input**. That is a cheap, strong regression check; any difference is a bug.
