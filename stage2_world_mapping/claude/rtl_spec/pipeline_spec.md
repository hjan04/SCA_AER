# Pipeline Specification

Measured inputs used here come from `analysis/dispatch_model_results.csv`: real decoded streams, a 100 MHz assumption, and **no memory stalls modelled**. They are cycle counts, not timing results.

## 1. Handshake model

- **Fixed-latency, lock-step lanes with one global advance enable `adv`.** Every mapper pipeline register in both lanes loads when `adv = 1`; empty slots travel as `valid = 0` bubbles.
- `adv` comes from `wm_out_skid`. The skid has 2 entries and a **registered** `ready`, so the stall reaching ~2 × (5 + L_ANG) pipeline registers is a flop output, not a combinational path from the merger/banks.
- Downstream of the skid, the merger, router and bank controllers use ordinary valid/ready.
- Upstream, `wm_word_unpacker` issues a bundle only when `adv && fifo_head_valid && grid_ok`.
- **Elasticity:** the mapper is *not* elastic per stage. Elasticity exists only at the input FIFO, the skid, the merger output regs, and the per-bank queues. This avoids per-stage handshakes on wide 3×16-bit vectors.
- **One lane never stalls alone.** A bank conflict back-pressures the *bundle*. Bundles are 2 events, so a lone-lane stall would buy at most one event and would break in-order delivery, which the hcache and the run-merger rely on.

## 2. Dispatch (`wm_word_unpacker`)

- Pops the FIFO head into a holding register: `rem_mask[15:0] = {gb_mask, ga_mask}` plus fields.
- Each cycle with `adv`: two priority encoders find the lowest and second-lowest set bits of `rem_mask` (stream order: group A LSB→MSB, then group B). They become lane 0 and lane 1. Those bits are cleared.
- The word stays in the holding register **across cycles** until `rem_mask == 0`, then the next word is popped in the same cycle (no bubble between words).
- Words with n events take `ceil(n/2)` cycles. An odd n leaves lane 1 idle in the last cycle.
- Invalid coordinates (`8·group + k ≥ 720`, or `x ≥ 960`) are masked off at pop and counted. They never reach a lane.
- Group tags: when the issued event comes from a new group (A→B switch, or a new word), the rolling 2-bit `grp_tag` increments. `first_of_grp` / `last_of_grp` are set from the masks.
- **No unpack FIFO.** The holding register *is* the single-entry unpack buffer.

Measured dispatch efficiency on real streams (`DISPATCH_MODE = WORD_LOCAL`):

| Recording | Events/word | Issue efficiency | Worst frame cycles | Worst-frame utilisation of 77,300-cycle budget | Frames over budget |
|---|---|---|---|---|---|
| sept15 | 3.45 | 0.900 | 47,841 | 61.9 % | 0 |
| sept22a | 3.28 | 0.894 | 44,644 | 57.8 % | 0 |
| sept22b | 3.40 | 0.896 | 69,798 | **90.3 %** | 0 |

`DISPATCH_MODE = STREAM` (pair the odd last event with the next word's first event) reaches efficiency 1.0 and 81.4 % worst-frame utilisation. It costs a 2-word holding window and cross-word group tags. **V1: `WORD_LOCAL`** (simpler; every frame fits). `STREAM` is the first lever if the clock drops or the RTL adds stall cycles.

A single shared horizontal-lerp unit (pairs restricted to one cell row) would reach 98.7 % worst-frame utilisation, because 44–46 % of words straddle two T32 cell rows. It is therefore **rejected**: each lane keeps its own H-lerp unit, and reuse is done by the cache (`native_word_reuse.md`).

Ordering: commutative accumulation does not need global order. **In-order delivery *within* the mapper is still kept**, because the hcache data timing and the merger's run detection rely on it, and it costs nothing in a fixed-latency pipeline.

## 3. Lane pipeline

Stage list, per lane; both lanes identical. `L_ANG` = ray→angle latency, WAITING_FOR_CODEX_EXP05.

| Stage | Inputs | Work | Registered outputs | Notes |
|---|---|---|---|---|
| **S0** (unpacker out) | FIFO head | bit extraction, tags | `x, y, pol, gsel, grp_tag, flags` | `gsel` from `wm_frame_ctrl` |
| **S1 Lookup** | S0 | `gx = x[9:5]`, `gy = y[9:5]`, `ox = x[4:0]`, `oy = y[4:0]`; hcache compare `key = {gsel, x, gy}` vs 2 entries; on miss: node addresses for (gx,gy), (gx+1,gy), (gx,gy+1), (gx+1,gy+1) → 4 parity sub-banks; issue sync read; install key in this lane's entry | event fields, `hit, hit_idx, ox, oy` | No arithmetic beyond bit slicing |
| **S2 Node** | S1 | grid store returns 4 nodes (12 components) on miss | `v00, v10, v01, v11` (3 × `GRID_NODE_W`† each) or don't-care on hit | Latency-1 sync read |
| **S3 H-lerp** | S2 | miss: `top = lerp(v00,v10,ox)`, `bot = lerp(v01,v11,ox)` per component (6 lerps); write hcache entry data. Hit: read `top, bot` from entry `hit_idx` | `top, bot` (3 × `RAY_W`† each), `oy` | Lerp units operand-isolated on hit |
| **S4 V-lerp** | S3 | `ray = lerp(top, bot, oy)` (3 lerps) | `ray` (3 × `RAY_W`†) | |
| **S5 … S(4+L_ANG) Angle** | S4 | ray → `(az, el)`; proposal: two chained vectoring CORDICs: (z,x) → az, ρ; (ρ', y) → el | `az, el` (`ANGLE_W`†) | Magnitude-independent, so bilinear shrink of the ray does not matter. **Contract WAITING_FOR_CODEX_EXP05** |
| **Sq Quant** | angle | `world_x = az_bam[top WORLD_X_W bits]` (wrap free if `WORLD_W` = 2^k); `world_y = clamp(...)`; `in_range` | `world_x, world_y` | Wrap endpoint and bin-edge rule per contract |
| **Sa Addr** | Sq | `wm_addr_gen` (`banked_memory.md` §1) | `bank, word_addr, cell, pol, tags` | |

- Total mapper latency is `L_MAP = 6 + L_ANG` cycles of `adv`.
- `wm_lerp` (a difference, a `LERP_DELTA_W` × 5-bit product, signed RNE `/32`, add, saturate) is the Codex-owned leaf. If one lerp per stage misses timing, `LERP_PIPE = 1` splits S3 and S4 into multiply/add halves. This adds 2 cycles of latency and does not change the protocol.
- Valid propagation: every stage register carries `v`. Bubbles keep their slot. `adv` freezes all stages.
- Stall behaviour: the whole lane array freezes. The grid store read is idempotent (address held), and the hcache data write at S3 happens only on an `adv` cycle.

## 4. Grid store organisation

- Lattice: nodes at x = 32·gx (gx = 0..30) and y = 32·gy (gy = 0..23). That gives **31 × 24 = 744 nodes** and 30 × 23 = 690 cells.
- Row gy = 23 (y = 736) is a guard row for the partial last cell row (704..719). Column gx = 30 (x = 960) is the right guard.
- Valid event cells are `gx = 0..29`, `gy = 0..22` (matches Codex Exp05).
- **Parity sub-banks:** sub-bank `(gx & 1, gy & 1)`, local index `(gy >> 1)·16 + (gx >> 1)` (stride 16, 192 entries; odd-column sub-banks use 180 of them). Any 2×2 neighbourhood hits each sub-bank exactly once. One lane's miss therefore needs **one read per sub-bank**, and two lanes need **two read ports per sub-bank**.
- Storage per buffer: 744 × 3 × `GRID_NODE_W`† bits (35,712 at the draft Q1.15). There are two buffers (`frame_epoch_protocol.md`).
- Read bandwidth, worst case: 2 lanes × 4 nodes × 3 components per cycle. Measured average: 0.78–0.85 node reads per event *with* reuse, vs 4 without (`native_word_reuse.md`).
- RTL abstraction: `wm_grid_store` exposes per-sub-bank `rd_addr[2], rd_data[2]` (sync, latency 1) and `wr_*`. V1 implements it as flop arrays with read muxes, because there is no SRAM compiler. It can later be swapped for a 2R1W register-file macro or a latch array without changing the interface.
- **Area note:** at the draft width, two buffers are ~71 kbit of storage. That is likely the single largest synthesized item and is a real PPA cost (`synthesis_comparison_plan.md` variant G1).

## 5. Input FIFO

| Item | Decision |
|---|---|
| What it stores | **Native words** (before unpacking): `{type, frame_id, x, ga_valid, ga_group, ga_mask, ga_pol, gb_…}` ≈ 45 + `FRAME_ID_W` bits |
| Position | Between the input port and `wm_word_unpacker` |
| Shared or per-lane | **One shared FIFO.** Lanes are fed from one word, so per-lane FIFOs would split native groups |
| Depth | `FIFO_DEPTH_WORDS`, initial **128 words**. That is ≥ 128 events even if every word held one event (Exp04's 128-event figure), and ≈ 435 events at the measured 3.4 events/word. **Not proven** against real intra-frame burst timing, which is unavailable |
| Overflow | The core **never drops**: `in_ready = 0` when full. In real-time (non-stallable sensor) test mode, the testbench/adapter counts upstream drops (`cnt_upstream_drop`) |
| Counters | `fifo_occ_words`, `fifo_occ_events` (sum of popcounts), `fifo_max_occ_words`, `fifo_max_occ_events`, `fifo_full_cycles` |

## 6. Throughput walkthroughs (structural cycle counts)

Assumptions: steady state, `RD_LAT = 1`, queues not full unless stated, merger enabled.

**CASE 1: two events, different banks.**
- c0: bundle issued (lane0 → bank 0 word A, lane1 → bank 2 word B).
- `L_MAP` cycles later the merger sees two events with different word keys. It flushes/opens records and emits 2 records, or 1 + an open record.
- The router enqueues into 2 different queues in one cycle. Bank 0 and bank 2 each start an RMW the next cycle.
- **Throughput: 1 bundle/cycle, no stall.**

**CASE 2: two events, same bank, different words.**
- Same as case 1 up to the router.
- Both records go to one queue (dual enqueue, needs ≥ 2 free entries) in one cycle.
- The bank drains them in 2 consecutive cycles.
- **No stall** unless that queue has < 2 free entries. In that case the router holds the pair for 1+ cycles, the skid absorbs ≤ 2 bundles, then `adv` drops. Since bank load averages ≤ 0.5 record/cycle (§7), these stalls are transient.

**CASE 3: two events, same world cell.**
- Same native group: the merger folds both into one record (delta 2 in that cell). **One RMW.**
- Different groups (a group boundary inside the bundle, or `MERGE_EN = 0`): 2 records, same bank, same word. Both enqueue (case 2). The second record's read is issued before the first record's write; the RAW bypass (`banked_memory.md` §5) supplies the first record's result. **2 RMWs, back-to-back, no stall, correct sum.**

**CASE 4: native word with 5 events (groups A: 3, B: 2).**
- c0: events A0, A1.
- c1: A2 (lane 0), B0 (lane 1). `grp_tag` differs between lanes; B is in the same column, so a different hcache key is likely if it is in a different cell row.
- c2: B1 (lane 0), lane 1 idle.
- **3 issue cycles.** The next word is popped in c2's update, so c3 issues the next word's events.

**CASE 5: frame boundary (next grid already committed).**
- Last word of frame f issues in c0. The first word of f+1 is at the FIFO head in c1. `wm_frame_ctrl` sees `frame_id = f+1`, finds buffer B READY with `epoch = f+1`, and flips `active`.
- The c1 bundle carries `gsel = B`. Events of frame f still in S1..S2 keep reading buffer A.
- Buffer A becomes reloadable once no `gsel = A` event remains in S0..S2: **≤ 3 `adv` cycles later**.
- **0 bubbles.** If grid f+1 is not committed: with `GRID_POLICY = STRICT` the unpacker stalls (counter `grid_wait_cycles`; the FIFO absorbs). With `LATEST` it maps with buffer A and counts `stale_grid_events`.

**CASE 6: memory back-pressure.**
- Bank 3's memory model deasserts `mem_ready` for k cycles. Its RMW pipe freezes and its queue fills. When bank 3 cannot take the record(s) of the current merger output, the router stalls *all* routing (atomic accept).
- The merger output regs hold, merger `in_ready = 0`, the skid fills (2 bundles), and `adv = 0`. The unpacker stops and the FIFO absorbs input; when it is full, `in_ready = 0`.
- Other banks keep draining their queues meanwhile. Recovery is immediate when bank 3 resumes.
- **Cost: k cycles minus queue/skid slack.** No loss, no reordering within a bank.

## 7. Where the throughput limit is

- Issue rate: 2 events/cycle peak, 0.89–0.90 efficiency → worst measured frame uses 90.3 % of the frame's cycles at 100 MHz. **This is the binding limit. Margin ≈ 10 %** (≈ 19 % with `STREAM` dispatch).
- Memory: merged records ≤ events. Exp04 modelled 47–59 % RMW reduction, spread over 4 banks. Even unmerged, the worst-frame mean is ≈ 1.63 events/cycle / 4 banks ≈ 0.41 record/bank/cycle. Banks are **not** the average-rate limit. They limit only under same-bank concentration (queue depth).
- Peak 1 ms window (Exp03, frame-granular): 201 k events. That exceeds the effective issue capacity of ≈ 180 k events per ms (2 × 100 k cycles × 0.9 efficiency), so backlog must carry across a frame boundary. This is a FIFO-sizing question (§5) and is **unproven** without intra-frame timestamps.
