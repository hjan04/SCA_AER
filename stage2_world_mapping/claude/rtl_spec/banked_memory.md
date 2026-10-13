# Banked World Memory: Address Generation, Routing, RMW Control

Draft world dimensions from Codex (Exp02/Exp05): 256 × 128 equirectangular cells, horizontal wrap, vertical clamp. Tile 4×4 cells per memory word (Exp04/Exp05 proxy). All are `WAITING_FOR_CODEX_EXP05`; formulas are written symbolically.

## 1. World address generation (`wm_addr_gen`)

```
world_x ∈ [0, WORLD_W)   (wraps: produced modulo WORLD_W by the quantizer; WORLD_W = 2^WORLD_X_W)
world_y ∈ [0, WORLD_H)   (clamped by the quantizer; out-of-range never reaches here unless the contract says "drop")

tx   = world_x >> log2(TILE_W)        ty   = world_y >> log2(TILE_H)
cx   = world_x & (TILE_W-1)           cy   = world_y & (TILE_H-1)
cell = cy*TILE_W + cx                 (0 .. TILE_CELLS-1, offset inside the memory word)
bank = BANK_FN(tx, ty)                (2 bits)
word_addr = { ty , tx >> 2 }          (BANK_ADDR_W = TY_W + TX_W - 2)
```

- Draft numbers: `TILES_X = 64`, `TILES_Y = 32`, 2,048 words, **512 words per bank**, word = 16 cells × `CNT_W`† (× 2 planes for ON/OFF).
- **Bijection check:** for fixed `ty` and `tx >> 2`, the four values of `tx[1:0]` go to four different banks (XOR with a constant is a permutation). So `{bank, word_addr}` is unique for every tile. This needs `TILES_X` to be a multiple of 4.
- Horizontal wrap: tiles wrap with `world_x`. Keeping `TILES_X` a power of two (≥ 4) means wrap needs no extra logic in tile/bank space.
- Vertical out of range: the clamp happens in the quantizer (Codex convention). If a "drop instead of clamp" policy is chosen later, `in_range = 0` events are counted and removed before the merger.

## 2. Bank function

**Proposed (`BANK_FN = XOR_NEG`):**

```
bank = tx[1:0] XOR ((-ty) mod 4)      i.e.  bank[0] = tx[0] ^ ty[0]
                                            bank[1] = tx[1] ^ ty[1] ^ ty[0]
```

This is exactly Exp04's `xor_mod` hash `(x XOR y*0x9E37) mod 4` (0x9E37 ≡ 3 mod 4, so `y·0x9E37 ≡ −y mod 4`), **applied to tile coordinates instead of cell coordinates**. Cost: 3 XOR gates. Parameterisation: `BANK_FN ∈ {XOR_NEG (default), XOR_PLAIN (tx^ty), LINEAR (tx mod 4)}`, for ablation.

**Why XOR and not low bits:**
- The sensor scans columns (Exp03: x non-decreasing in 100 % of in-frame pairs). Under yaw, a sensor column maps to a near-vertical world line, so consecutive events advance in `ty` with `tx` fixed. `bank = tx mod 4` would put an entire column walk in **one** bank.
- Exp04 (cell level, 2-event bundles, all finalist traces): `linear_mod` 4-bank conflict fraction **0.91**, accepted 1.09 updates/bundle; `xor_mod` 4-bank **0.57**, 1.43/bundle.
- XOR with the `ty` term rotates the bank as `ty` advances. Under roll (Sept 22), walks are diagonal, and XOR in both coordinates still spreads them.

**Open:** Exp04 measured banking on *cell* addresses, with same-word pairs counted as conflicts. With 4×4 tile words, same-word pairs are absorbed by the merger or bypass, and the bank function acts on tiles. **The tile-level conflict rate after merging is unmeasured** → request to Codex (`rtl_spec_summary.md` §D).

## 3. Router (`wm_bank_router`)

- Input: up to 2 records per cycle (`rec[0]`, `rec[1]`) from the merger output registers.
- Four bank queues (`BQ_DEPTH` records each, initial 4), each with **two enqueue ports and one dequeue port**.
- Accept rule (atomic): accept the pair iff every target queue has enough free entries (2 if both records target the same bank, else 1 each). Otherwise accept nothing this cycle.
- Atomic acceptance keeps the merger simple: no partial-accept state, records leave in pairs, and per-bank order is the stream order.
- Starvation: none. Every queue dequeues independently whenever its bank controller is ready. The router is a pure steering function with no arbitration among competing sources (there is one source).
- **Structural buffering bound:**
  - per bank `BQ_DEPTH` records (record ≈ `BANK_ADDR_W` + 16 × 4 delta bits [+64 for ON/OFF] + 4);
  - plus 2 merger output registers;
  - plus the 2-entry skid of mapped bundles;
  - plus `L_MAP` pipeline slots.
  - No other buffering exists.

## 4. Conflict handling summary

| Two records in one cycle | Behaviour | Cost |
|---|---|---|
| Different banks | Parallel enqueue, parallel RMW | 0 stall |
| Same bank, same word, same group | Already one record (merger) | 0 |
| Same bank, same word, different groups | Both enqueued. The second RMW uses the RAW bypass | 0 stall; 2 RMW cycles in that bank |
| Same bank, different words | Both enqueued (dual enqueue) | 0 stall if ≥ 2 free; bank busy 2 cycles |
| Target queue lacks space | Router holds the pair → merger stalls → skid → `adv = 0` | stall until space |

## 5. Bank update controller (`wm_bank_ctrl`) and memory model

**Memory model (`wm_mem_model`, simulation only):**
- 1 read port + 1 write port per bank;
- a read issued in cycle t returns the word as of the *start* of cycle t, after `RD_LAT` cycles;
- a write issued in cycle t is visible to reads issued at t+1 or later;
- optional `mem_ready` for back-pressure injection;
- `RD_LAT` parameter: 1 by default, swept 1..3 in verification.

**RMW pipeline (in order, one record per cycle):**

```
R   : pop record from queue; issue read(word_addr)
R+1..R+RD_LAT-1 : wait (record carried in pipe regs)
M   : old = bypass_hit ? hist_data : rd_data
      for each cell c: new[c] = sat_add(old[c], delta[c])    (TILE_CELLS adders; ×2 for ON/OFF)
      issue write(word_addr, new); push (word_addr, new) into write history
```

**RAW hazard: frequent, so bypass is mandatory.**
- Exp04 found ~0.71 consecutive same-word fraction at 4×4-tile granularity before merging. Merging removes in-group repeats, but cross-group same-word records stay common.
- A record's read misses every write issued between its read and its own modify stage.
- The bank therefore keeps a **write history of the last `RD_LAT` writes** (address, data), youngest first. At M, if `word_addr` matches an entry, the youngest match replaces `rd_data`.
- Since each record writes exactly once and the pipe is in order, "the last `RD_LAT` writes" is exactly the set of possibly-missed writes, independent of stalls.
- Cost: `RD_LAT` address comparators + a `RD_LAT`:1 mux of word width.
- **Stalling instead would serialize every same-word pair by `RD_LAT` cycles.** That is rejected.
- **Optional `QUEUE_FOLD`** (default 0): at enqueue, fold a record into the queue tail if same word. This adds cross-group merging (fewer RMWs, same memory contents). It is off by default so RMW counts match the reference.

## 6. Accumulator semantics

| `ACC_MODE` | Cell layout | Update | Status |
|---|---|---|---|
| `UNSIGNED` | `CNT_W`† bits | `min(old + delta, 2^CNT_W − 1)` | **V1 default implementation** |
| `ONOFF_PACKED` | `{on: CNT_W, off: CNT_W}` in the **same** word | per plane saturating add | Architectural parameter; recommended for the final demo |
| signed (ON = +1, OFF = −1) | — | — | **Not supported.** With saturation, `sat(sat(a+d1)+d2) ≠ sat(a+d1+d2)` for mixed signs, so merging and bypass would change results. Codex's case table also shows signed merges cancelling to 0 |

Why `UNSIGNED` as the V1 default:
- It matches Codex's Exp05 reference default and vectors.
- It has the smallest word and gives the maximum merge opportunity.
- It is fully order-independent (monotone saturating add of non-negative deltas commutes), so merge, banking and bypass are bit-exact verifiable.

Why ONOFF is the recommended next step:
- Exp03 showed polarity is balanced (50–52 %) but **spatially segregated** (only 5–9 % of 4×4 blocks mixed). ON/OFF planes carry edge-direction structure that an unsigned count discards, and the organizer named ON/OFF accumulation as the visible evidence of correct mapping (Q22).
- Packing both planes in one word avoids Exp04's merge-key penalty at the cost of 2× cell bits.
- The merger/record format already carries `delta_off`, so switching modes is a parameter change, not a redesign.

## 7. Initialization

- **No single-cycle clear.** After reset each bank controller runs an **init sweep**, writing zero to every word: `WORDS_PER_BANK` cycles, 512 at the draft size.
- During the sweep `bq_ready = 0` and `init_done = 0`. The mapper may already fill the FIFO/skid. Records wait.
- An optional `clear_req` input re-runs the sweep.
- Epoch/lazy-clear tags are **not justified** at this map size: 512 cycles ≈ 0.7 % of one frame budget, once.
