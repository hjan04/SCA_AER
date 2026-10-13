# Native-Word Reuse: Hardware Structure

## What is reused (and what is not)

T32 bilinear interpolation with Codex's nested form:

```
top = lerp(v00, v10, ox)      bot = lerp(v01, v11, ox)      ray = lerp(top, bot, oy)
```

`top` and `bot` depend only on `(grid buffer, gx, gy, ox)`, which is a function of `(gsel, x, gy)` because `gx` and `ox` are bit fields of x. Every event with the same `(gsel, x, y >> 5)` therefore has **bit-identical `top`/`bot`**. Codex verified this on the 1×8 native group (zero mismatches). It is the same arithmetic identity, so it holds for any events sharing the key.

| Item | Reused? | How |
|---|---|---|
| Grid-cell identification `(gx, gy)` | yes | part of the key |
| Node addresses / fetched nodes | yes | no node read on a hit |
| Horizontal interpolations (6 lerps → `top`, `bot`) | **yes** | cached vectors |
| Vertical interpolation (3 lerps) | **no** | per event, uses its own `oy` |
| Ray→angle, quantization, world address | **no** | per event; events of one word may map to different world cells, words and banks |
| Event coordinates and polarity | never merged | each event keeps x, y, pol through the lane |

## Key generalisation beyond Exp04

- Exp04 shared work only inside a 1×8 group (key `(x, y >> 3)`): −35.9 % node reads, −23.9 % vector interpolations.
- The key `(gsel, x, y >> 5)` also covers both groups of a word when they lie in the same T32 cell row, and consecutive words of the same column within one cell row. The column-major scan makes those common.
- Measured on the three real streams, single reuse register, stream order, `analysis/dispatch_model_results.csv`:

| Recording | Key changes / event | H-lerp work saved | Node reads / event (vs 4) | Node-read reduction |
|---|---|---|---|---|
| sept15 | 0.290 | 71.0 % | 0.78 | 80.6 % |
| sept22a | 0.313 | 68.7 % | 0.85 | 78.8 % |
| sept22b | 0.297 | 70.3 % | 0.79 | 80.2 % |

The node-read figure assumes a "slide-down" refinement: when the key changes only by `gy + 1` in the same column, the old bottom nodes become the new top, so only 2 nodes are read. **V1 does not implement the slide** (always 4 nodes on a miss). The V1 node reads per event are therefore `4 × key-change rate ≈ 1.16–1.25`, a ~69–71 % reduction.

## Structure: `wm_hcache`

- **2 entries**, shared by both lanes. Entry *k* is written only by lane *k* (deterministic replacement; no LRU).
- Entry fields: `key = {gsel, x[9:0], gy[4:0]}` (16 bits), `kvalid`, `data = {top, bot}` (6 × `RAY_W`†).
- **S1:** each lane compares its key against both entries' `key/kvalid`. Hit on either entry: `hit = 1`, `hit_idx`. Miss: issue the node read and install `key` into its own entry immediately (key at S1).
- **S3:** a miss computes `top`/`bot` and writes `data` of its own entry; a hit reads `data[hit_idx]`.
- Correctness argument: the pipeline is in order and fixed-latency, and both installation (data write) and use (data read) happen at S3. A follower that hit at S1 behind a leader always reaches S3 at least one `adv` cycle after the leader wrote the data. Any later miss that overwrites the entry reaches S3 after the follower. Under a global stall everything freezes together, so the argument holds unchanged.
- Same-bundle duplicate: if lane 0 and lane 1 miss on the same key in the same cycle, then by default (`HCACHE_XLANE = 1`) lane 1 compares its key with lane 0's key at S1. On a match it marks `xhit` and, at S3, takes lane 0's freshly computed `top`/`bot` through a 2:1 mux instead of using its own lerps. With `HCACHE_XLANE = 0`, both lanes compute (identical results, energy only).
- **Caveat on the measured numbers:** the table above came from a sequential single-register model. The hardware matches it only with `HCACHE_XLANE = 1`, and even then not exactly, because entry ownership is per lane. RTL simulation on real traces must report the actual hit rate (`cnt_hcache_hit`). Treat 69–71 % as an upper-bound estimate.
- Invalidation: when a grid buffer is released for reload, `kvalid` is cleared for entries whose `gsel` matches (`frame_epoch_protocol.md`). Data is not touched; in-flight followers have already passed S2.
- Lifetime: **until the key changes or the buffer is released.** No time-based expiry, no cross-frame reuse with a reloaded buffer.

## Why the hardware still has two H-lerp units

The dispatch model shows a single shared H-lerp unit forces 0.78 issue efficiency (worst frame 98.7 % of budget), because 44–46 % of words straddle a T32 row. The reuse therefore buys **energy and node-read bandwidth, not area**: hits operand-isolate the 6 lerps and skip the grid read. In the synthesis comparison, D2 (`HCACHE_EN = 0`) and E-lite have the same H-lerp datapath area plus E-lite's ~0.2 kbit cache. The benefit must be shown with **activity-based power** on real traces, not with area.

## Parameters

`HCACHE_EN` (0 = D2 behaviour: always fetch and recompute), `HCACHE_ENTRIES` (2; 1 = single shared register for an ablation).
