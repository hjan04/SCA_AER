# Frame / Epoch / Grid Protocol

## Goals

1. An event of frame f is mapped with the grid generated for frame f's pose. No event ever reads a half-old/half-new grid.
2. A frame switch at the measured cadence (one per 773 µs, back-to-back frames) costs no pipeline drain.
3. Memory updates never depend on the frame. Once a world address exists, pose is irrelevant.

## Decision: tag-based (B), with drain only of the grid buffer

- Each event carries a **1-bit `gsel`** (which grid buffer it reads).
- The *buffer* must be drained of references before reload; the *pipeline* never drains.
- This is cheaper and safer than option A (drain the whole pipeline before every swap: L_MAP + skid + merger + bank queues per frame, ~1,300 frames/s × tens of cycles of lost issue slots, and it couples memory back-pressure to grid swaps).
- Only S0..S2 read the grid. After S2 an event carries its nodes or cached vectors, so the window that pins a buffer is ≤ 3 `adv` cycles.

## Buffer state machine (`wm_frame_ctrl`), per buffer b ∈ {0, 1}

```
FREE ──(loader writes nodes)──► LOADING ──(gc_valid, epoch=e)──► READY(e)
READY(e) ──(head word frame_id == e)──► ACTIVE(e)
ACTIVE(e) ──(other buffer becomes ACTIVE)──► DRAINING
DRAINING ──(no gsel=b event in S0..S2)──► FREE   [also clears hcache entries with gsel=b]
```

- `grid_free` (to the loader) = some buffer is FREE. Node writes go to that buffer only. `gw_ready` = 0 if none is FREE.
- Exactly one buffer may be ACTIVE. Commit tags a buffer with the frame id it serves (`gc_epoch`).
- Reference tracking: a 3-stage shift of `{valid, gsel}` mirroring S0..S2, plus the unpacker's held-word gsel. "No reference" = none of these match b. No counters are needed because the latency is fixed.

## Frame-id handling at the unpacker

For the FIFO head word with frame id f:

| Condition | `GRID_POLICY = STRICT` (V1 default) | `GRID_POLICY = LATEST` |
|---|---|---|
| ACTIVE epoch == f | issue with `gsel = active` | same |
| Other buffer READY(f) | switch: other → ACTIVE, old → DRAINING; issue | same |
| No buffer holds f | **stall** (`grid_wait_cycles++`); FIFO absorbs | issue with the current ACTIVE grid; `stale_grid_events++` |
| `FRAME_MARK` word | pass a bubble bundle carrying `frame_mark` (merger flush, counters); no grid needed | same |

- STRICT makes RTL results reproducible against the reference (each frame's grid is defined by the test vector set).
- LATEST is a real-time fallback when pose arrives late. The error it introduces is ω × (lag), which the report must state.
- **Deadlock guard:** STRICT waits forever if the loader never commits f. `grid_wait_cycles` and a `grid_timeout` status flag (threshold parameter) make that visible in simulation. The core does not skip frames on its own.

## Interaction table

| Item | Rule |
|---|---|
| Pose | Lives only in the external grid generator. The core sees nodes + epoch |
| Grid | Double buffer, atomic commit, release after reference drain |
| hcache | Key includes `gsel`. Entries with `gsel = b` are invalidated when b goes FREE (stale-data protection after reload) |
| Pending events in the lanes | Keep their `gsel`; unaffected by later swaps |
| Pending merger record | Flushed by `FRAME_MARK` or by the next incompatible event. Never merges across groups, hence never across frames |
| Pending memory updates | Frame-independent; no action |
| Frame counters | `frames_in` (FRAME_MARK at input), `frames_out` (FRAME_MARK at merger output), `max_frame_lag_cycles` between the two |

## Load-time budget

- Node load: 744 writes per frame at 1 node/cycle = 744 cycles ≈ 1 % of the 77,300-cycle frame budget. It runs in parallel with mapping (other buffer).
- Within a frame, the loader has ~76 k cycles of slack → it can be slow and serial.

## Single-buffer alternative (`GRID_BUFS = 1`, area option, not V1)

- Halves grid storage (−35.7 kbit at the draft format), which is likely the largest synthesized storage item.
- Cost: at each frame boundary, stall issue until no reference remains (≤ 3 cycles), load the grid (744 cycles at 1 node/cycle, or 186 at 4 nodes/cycle, one per parity sub-bank), then resume.
- At the worst measured frame demand (≈ 1.63 events/cycle), a 186-cycle load backs up ≈ 300 events ≈ 90 words, which fits the 128-word FIFO. A 744-cycle load does not (~1,200 events).
- It also requires the generator to have the next grid ready exactly at the boundary.
- Report as a synthesis variant only after V1 works.

## Reset and initialization

| Item | Reset state |
|---|---|
| `rst_n` | Active-low; asserted asynchronously, released synchronously. All control state below is reset; wide datapath registers (lane vectors, node storage) are **not** reset, because their `valid` bits are |
| Input FIFO | Pointers and occupancy = 0; `in_ready` = 0 until `init_done` (simpler test protocol), then by FIFO state |
| Unpacker | Holding register empty; `grp_tag` = 0 |
| Lanes, skid, merger, router queues | All `valid` = 0 |
| Grid buffers | Both FREE (no valid grid). With STRICT, nothing issues until the first commit. `gw_ready` = 1 |
| hcache | All `kvalid` = 0 |
| Bank controllers | Run the init sweep (`banked_memory.md` §7). `init_done` when all 4 finish |
| Frame tracking | No current frame; the first word's `frame_id` is adopted as is (ids are modulo `2^FRAME_ID_W`, compared for equality only) |
| Counters | 0 |
| Status flags | `init_done`, `grid_timeout`, `err_fifo_overflow_attempt` (input `valid` while `in_ready` = 0 is legal; this flag is only for a test mode where the source is declared non-stallable), `err_invariant` (simulation-only assertion mirror) |
