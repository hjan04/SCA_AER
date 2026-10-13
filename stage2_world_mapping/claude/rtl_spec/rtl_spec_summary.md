# RTL Microarchitecture Specification: Summary

Frozen architecture implemented here:
- Warp-Grid T32;
- 2 lanes;
- native-word reuse;
- E-lite merge at threshold 2;
- 4 interleaved banks;
- FIFO 128 (unproven);
- external per-frame pose.

No RTL is written. Measured inputs: Exp03 (real traffic), Codex Exp04 (screen) and the Exp05 draft (fixed point), plus `analysis/dispatch_model_results.csv` (new: real-stream dispatch and reuse counts).

## Module hierarchy

```
world_mapper_top
├── wm_input_fifo            native-word FIFO (FIFO_DEPTH_WORDS = 128 initial)
├── wm_frame_ctrl            frame-id ↔ grid buffer binding, buffer FSM, reference drain
├── wm_grid_store            2 buffers × 4 parity sub-banks × 2 lane read ports; load/commit port
├── wm_word_unpacker         holding register + 2 priority encoders → lock-step bundle (≤ 2 events)
├── wm_hcache                2-entry shared horizontal-vector cache (+ cross-lane same-bundle forward)
├── wm_mapper_lane [0..1]
│   ├── wm_hlerp             6 × wm_lerp  (operand-isolated on hit)
│   ├── wm_vlerp             3 × wm_lerp
│   ├── wm_ray2angle         ray → (az, el)   [contract WAITING_FOR_CODEX_EXP05]
│   ├── wm_world_quant       wrap / clamp → world_x, world_y
│   └── wm_addr_gen          tile, cell, bank (XOR_NEG), word_addr
├── wm_out_skid              2-entry skid, registered ready → global adv
├── wm_elite_merger          1 open record, ≤ 2 records/cycle (MERGE_EN = 0 ⇒ D2)
├── wm_bank_router           2 → 4, dual-enqueue bank queues (BQ_DEPTH = 4), atomic accept
├── wm_bank_ctrl [0..3]      in-order RMW, write-history RAW bypass, saturating add, init sweep
├── wm_status                counters + status flags
└── (sim only) wm_mem_model [0..3]   1R1W behavioural banks, RD_LAT, mem_ready
shared: wm_pkg (types, params)   leaf: wm_lerp (Codex-owned arithmetic)
```

## Answers to the requested topics

1. **Boundary:** native-word input to memory RMW is inside. `.dvs` decoding, pose estimation, grid generation (V1), memory macros and visualisation are outside (`system_boundary.md`).
2. **Hierarchy:** above.
3. **Two-lane scheduling:**
   - lock-step bundles of ≤ 2 events from one word;
   - a word stays held for `ceil(n/2)` cycles;
   - single global `adv`.
   - Real streams: issue efficiency 0.89–0.90; worst frame 90.3 % of the 100 MHz budget; 0 frames over budget.
4. **Native-word reuse:**
   - cache `top`/`bot` horizontal vectors keyed by `(gsel, x, y >> 5)`, a generalisation of Exp04's 1×8 key;
   - 2 entries, lane-owned replacement, data at S3, lifetime until the key changes or the buffer is released.
   - Upper-bound estimate on real streams: −69–71 % H-lerps, −69–71 % node reads without slide (−79–81 % with slide).
   - Area is not reduced (two H-lerp units remain, because 44–46 % of words straddle a T32 row); energy is.
5. **Mapper pipeline:** S1 lookup → S2 node read → S3 H-lerp → S4 V-lerp → S5.. ray→angle (`L_ANG`) → quant → addr. `L_MAP = 6 + L_ANG`. Fixed latency, in order.
6. **E-lite:** one open record. Fold consecutive same-word events of the same native group. Threshold 2 = "fold when compatible" (uniform record format makes k = 2 already profitable). `MERGE_EN = 0` gives D2.
7. **Banks:**
   - 4 banks, `bank = tx[1:0] ⊕ (−ty mod 4)` on **tile** coordinates (Exp04's xor_mod hash at tile level);
   - `word_addr = {ty, tx >> 2}`;
   - 512 words/bank at draft size.
8. **Conflicts:**
   - different banks: parallel;
   - same word, same group: merged;
   - same word, different groups: back-to-back with bypass;
   - same bank, different words: dual enqueue, served sequentially;
   - queue full: atomic router stall → skid → `adv = 0`.
9. **RAW hazards:** per-bank write history of depth `RD_LAT`, youngest-match bypass at the modify stage. Never stall for hazards; same-word sequences are common.
10. **FIFO:**
    - one shared FIFO **of native words**, before unpacking;
    - 128 words (≥ 128 events in any case, ≈ 435 at average density);
    - back-pressure, never drop;
    - occupancy in words and events.
11. **Frame/grid:**
    - double-buffered grid with a commit epoch;
    - 1-bit `gsel` per event;
    - switch with zero bubbles;
    - reload only after the S0..S2 reference drain;
    - hcache invalidated by `gsel`;
    - STRICT (stall) or LATEST (stale, counted) if the grid is late.
12. **Verification:** L1–L7 (`verification_plan.md`). Strongest cheap check: D2 and E-lite final maps must be **bit-identical**.
13. **D2 vs E-lite synthesis:** same RTL with merger/hcache generate-switched. Same mapper, formats, clock, SDC, memory abstraction. Grid store and memory reported separately (`synthesis_comparison_plan.md`).
14. **Waiting for Codex:** §D below.

## A. Implementable without a large control structure?

**Yes.** The control state is:
- FIFO pointers;
- one holding register with two priority encoders;
- a 2-buffer FSM with a 3-stage reference shift;
- 2 hcache keys;
- 1 open record;
- 4 small queues with a free-count check;
- per bank, an in-order RMW pipe with `RD_LAT` compares.

There are no CAMs beyond 2–3-entry compares, no reorder buffer and no scoreboard. That simplicity is bought by:
1. lock-step lanes;
2. commutative accumulation;
3. a per-event grid tag instead of drains.

The real complexity is in the **datapath** (9 lerps + ray→angle per lane) and the **grid storage**, not in control.

## B. Likely throughput bottleneck

**Event issue rate (2 lanes × word-local pairing efficiency ≈ 0.9).** The worst measured frame needs 69,798 issue cycles of 77,300 (90.3 %) at 100 MHz, so it fails if the achieved clock is below ≈ 90.3 MHz.

- Mitigations: STREAM dispatch (→ 81 %) or the FIFO carrying backlog across frames.
- Memory is not the average-rate limit: ≤ ~0.41 record/bank/cycle even unmerged at the worst frame. It limits only under same-bank bursts, which are absorbed by `BQ_DEPTH`.
- **The likely timing-critical paths** (Fmax, not throughput) are `wm_ray2angle`, the lerp multiply/RNE/saturate chain, and the bank modify stage (bypass mux + 16 saturating adders).

## C. Independent implementation split (no merge conflicts)

Shared and frozen first: **`wm_pkg`** (parameters, record/bundle structs) and the interface tables in `module_interfaces.md`. Changes to these only by explicit agreement.

| Codex (numeric datapath, bit-exact vs own model) | Claude (control, storage, memory system) |
|---|---|
| `wm_lerp` | `wm_input_fifo` |
| `wm_hlerp`, `wm_vlerp` | `wm_word_unpacker` |
| `wm_ray2angle` | `wm_frame_ctrl`, `wm_grid_store` |
| `wm_world_quant` | `wm_hcache`, `wm_out_skid` |
| L2 vector testbench + vector generation | `wm_elite_merger`, `wm_bank_router` |
| grid generator (SW) for test poses | `wm_bank_ctrl`, `wm_mem_model`, `wm_status` |
| | `wm_addr_gen` (bank function), `world_mapper_top`, L1/L3–L7 testbenches |

`wm_mapper_lane` is a thin wrapper. Claude wires the stages and pipeline registers; Codex provides the arithmetic leaves as combinational modules with registered boundaries defined in `pipeline_spec.md`. Separate files, no shared edits.

## D. Exactly what is needed from Codex Exp05 before RTL coding

1. **Ray→angle→address contract (blocking):**
   - algorithm (e.g. integer two-pass vectoring CORDIC or another defined approximation);
   - iteration count / LUT size;
   - angle code width and unit (BAM preferred, so wrap is bit slicing);
   - gain handling between passes;
   - exact bin-edge rounding;
   - wrap endpoint;
   - vertical clamp vs drop;
   - a bit-accurate reference implementing exactly that, plus `world_x/world_y` vectors.
2. **Freeze of datapath widths:** `GRID_NODE_W`, `LERP_DELTA_W`, `LERP_PROD_W`, `LERP_ACC_W`, `RAY_W` (draft 16/17/22/17/16, Q1.15, signed RNE after each lerp), saturation points. Confirm the nested `top/bot/vertical` order.
3. **World/memory geometry:** `WORLD_W × WORLD_H` (draft 256 × 128), `TILE_W × TILE_H` (proxy 4 × 4), `CNT_W` and the saturation value for `UNSIGNED`, and whether `ONOFF_PACKED` is required.
4. **Tile-level bank screen:** re-run Exp04's bank comparison with `BANK_FN` applied to tile coordinates *after* within-group merging (2-record bundles). Report conflict fraction and records accepted/cycle for XOR_NEG vs XOR_PLAIN vs LINEAR.
5. **Merge reference in RTL form:** add `mode="run"` (consecutive-only folding inside a native group) to `merge_group_updates`, and RMW counts per frame for D2 vs run-merge on the replayed traces.
6. **Grid table format:** node index order (`gy·31 + gx`), component order (x, y, z), the Euler convention used by the generator, and grid files per test pose for the L2/L6 testbenches.
7. **Vector sets:**
   - per-event `ray_q` (exists);
   - per-event `world_x/world_y/bank/word/cell` (after item 1);
   - native-group vectors (exists);
   - merge-case vectors with expected records (extend `merge_reference_cases.csv`).

## Files in this directory

`system_boundary.md`, `top_level_architecture.md`, `module_interfaces.md`, `pipeline_spec.md`, `native_word_reuse.md`, `e_lite_merger.md`, `banked_memory.md`, `frame_epoch_protocol.md`, `verification_plan.md`, `synthesis_comparison_plan.md`, `implementation_risks.md`, `rtl_spec_summary.md`, `analysis/dispatch_model.py`, `analysis/dispatch_model_results.csv`.
