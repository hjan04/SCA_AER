# World Memory Architecture

World Memory is likely the **dominant area and power cost and the throughput bottleneck** of the whole system. That is a hypothesis to be confirmed by event-rate measurements on DELTA data and by memory-cost estimates. The organizer counts SRAM in PPA (Q15) but provides no macro. The memory therefore needs a defined model and a cited cost source.

## 1. Size budget (examples, not a proposal of official dimensions)

`bits = N_cols × N_rows × bits_per_cell`, plus tags and overhead.

| Map (cols × rows) | Angular cell (360°/cols) | 2 b/cell | 4 b/cell | 8 b/cell |
|---|---|---|---|---|
| 1024 × 256 | 0.35° | 64 KiB | 128 KiB | 256 KiB |
| 2048 × 512 | 0.18° | 256 KiB | 512 KiB | 1 MiB |
| 4096 × 1024 | 0.088° | 1 MiB | 2 MiB | 4 MiB |
| 8192 × 2048 | 0.044° | 4 MiB | 8 MiB | 16 MiB |

For reference, a centre pixel subtends 0.069° if θh = 30° (assumed; fx unknown). **Matching sensor resolution over 360° needs ~4096–8192 columns. That is megabytes, which is unrealistic for a student SRAM estimate.** A world cell 2–4× coarser than a sensor pixel (1024–2048 columns) is the realistic range. It also relaxes the mapper error budget, and it is exactly the kind of "memory vs fidelity" decision the organizer invites (Q15: "what world size do you think is reasonable — explain").

Cost source: no GPDK045 SRAM macro exists. Options:
(a) an OpenRAM-generated macro in FreePDK45 as a proxy (different PDK, must be stated);
(b) a published 45 nm SRAM bit-cell/array density with citation;
(c) a register-file synthesized in Genus for a *small* map only (≤ a few kbit), never for the full map.

**Report logic PPA and memory PPA separately, then the total.**

## 2. Organizations

| Org | Description | Pros | Cons | Verdict |
|---|---|---|---|---|
| **A. Dense N×M array** | One cell per address, single bank | Trivial addressing, deterministic | 1 RMW per event; single port gives ≤ 0.5 ev/clk (read + write) | V1 baseline |
| **B. Banked** | B banks interleaved by low address bits | B parallel accesses if conflict-free | Bank conflicts; crossbar | Needed for > 0.5 ev/clk |
| **C. Tiled words** | One SRAM word = a k×k world tile (e.g., 4×4 cells × 4 b = 64 b) | Block updates touch few words; natural for E | Wider words; per-cell update needs a full-word RMW | **Core of the final design** |
| **D. Sparse event map** | Store only touched cells as (addr, value) | Small if the scene is sparse | Over a sweep, edges cover much of the band; worst case unbounded; needs eviction | Reject for primary map |
| **E. Tag/value cache** | Small cache of world tiles in front of a large (off-chip-modeled) map | Exploits temporal locality of slow rotation | Miss handling, write-back; the large map is still needed | Option if the map is modeled as off-chip DRAM |
| **F. Multi-resolution** | Coarse full-sphere map + fine map around current view | Matches "detail where needed" (Q15) | Two address paths, consistency | V2+ research |
| **G. Recent-event decay map** | Values decay with age | Matches "afterimage" remark (Q15); suppresses stale data | Needs time per cell or per tile | Via lazy per-tile epoch (below) |
| **H. Double buffer / window** | Two maps, swap per window | Clean temporal snapshots | 2× memory | Reject at map scale. Fine for small patch buffers |

## 3. Banking strategy for block updates (candidate E)

A 4×4 sensor block maps to a world footprint whose bounding box is roughly `4·s·√2` cells (s = world cells per sensor pixel, ≤ 1; √2 for arbitrary roll). If the world tile is k×k and the footprint fits inside k×k, the footprint touches **at most 4 tiles**, one from each parity class (tile_x mod 2, tile_y mod 2).

So **2×2 parity interleaving (4 banks) makes every block update conflict-free by construction**: at most 1 word per bank, all 4 in parallel.

- k = 4, s ≤ 0.7: fits.
- k = 8 for s = 1 with roll.
- Azimuth wrap: the tile index wraps mod (N_cols/k). Keep N_cols/k even so parity survives the wrap.

## 4. Hazards and collisions

| Issue | Where it arises | Handling |
|---|---|---|
| **Same address within one block** | Several pixels land in one world cell (common when s < 1) | Merge in the patch accumulator before the RMW: add counts, combine polarity bits. Lossless for commutative semantics |
| **Read-after-write across consecutive updates** | Pipeline reads at stage k, writes at k+L. Neighbouring events (same edge, consecutive frames) hit the same word | Forwarding/bypass from in-flight writes (compare L tags), or stall. **Never silently drop.** Verify with directed back-to-back same-address tests |
| **Bank conflicts** (per-event path, B org) | Two events per cycle to the same bank | Arbiter + small queue, or restrict to 1 ev/clk per bank |
| **Saturation** | Hot pixels, long dwell | Saturating add. Saturation count as a metric. Hot-pixel cells saturate fastest, so saturation also flags them |
| **Write conflicts at map seams** | Footprint crosses the azimuth wrap or a cube face | Split the patch; wrap is handled by modulo tile index |
| **Initialization** | Clearing MBs of SRAM takes N_words cycles | **Epoch tags per tile**, stored in the tile word: tile is valid iff tag == current epoch. Clear = increment the global epoch (O(1)). A tag mismatch on read means zero. Tag aliasing after 2^E epochs must be handled (background scrub, or a large enough E) |
| **Stale information** | Scene changes (moving fan, people) | Lazy decay (below) or windowed epochs |

## 5. What each cell stores

| Content | Bits | Order-independent? | Value | Comment |
|---|---|---|---|---|
| Binary seen | 1 | yes (OR) | Low | Saturates immediately; hot pixels and noise dominate |
| Unsigned count (saturating) | 3–8 | **yes (add)** | Medium–high | Edge strength ~ repeated hits. Combinable |
| Separate ON / OFF counts | 2×(2–4) | yes | High | Shows the polarity structure that the organizer wants to see (Q22 B10) |
| Signed polarity sum | 4–6 | yes until saturation | Medium | ON/OFF from back-and-forth sweeps can cancel. Risky as the only content |
| Last polarity | 1 | **no** | Low | Order-dependent; breaks merge/reorder and bit-exact verification |
| Timestamp / age | 8–16 | max is commutative | Medium | Per cell, timestamps are too expensive (they dominate memory). Use per tile |
| Confidence | 2–4 | depends | Speculative | Needs a defined update rule |
| Decaying value | 4–8 | **no** (decay ∘ add do not commute unless lazy-by-epoch) | Medium | Use lazy per-tile epoch decay |

**Design principle: choose commutative cell semantics.** Commutative updates make block merging, banking, reordering, and forwarding *lossless and bit-exact verifiable* against the golden model, independent of processing order. This is the deciding argument for counts over last-polarity.

## 6. Policies

### Minimal V1 policy

- Dense single-bank map (org A), cylindrical yaw band, 1024–2048 columns, **4 bits/cell**: 2-bit saturating ON count + 2-bit saturating OFF count. Make CELL_W a parameter.
- 1 RMW per event, with read-after-write forwarding. Max 0.5 ev/clk with a single port, or 1 ev/clk with an assumed dual-port (read + write) memory model, stated as an assumption.
- No timestamps, no decay. Clear by reset sequence (simulation) or epoch tag.
- Output: the map plus counters for saturations, forwarding hits, stalls, and out-of-band events.

### Ambitious policy (final candidate)

- Tiled words (org C), 4×4 or 8×8 cells per word, 2×2 parity banks (4 banks).
- Block patch accumulator: merge each Group-AER/4×4 block into a ≤ 2×2-tile footprint, then ≤ 4 parallel word RMWs.
- **Per-tile epoch tag** (6–8 bits in the tile word) for O(1) clear and **lazy decay**. When a tile is touched, `cells >>= min(current_epoch − tile_epoch, CELL_W)`, then add the new counts and set the tag. Readout applies the same rule. Decay cost is paid only on access.
- Optional small tile cache (org E/F) only if Experiment 03 shows locality worth exploiting.
- Saturation and stale-tile statistics are exported for the report.

## 7. Bandwidth framing (to be filled with measurements)

```
required RMW/s (per-event path) = events/s
available (single-port, 2 cycles/RMW) = f_clk / 2 per bank
available (tiled block path) = f_clk × banks / words_per_block   (if conflict-free)
```

The organizer said a 2 s recording is about 100 MB (Q15). Events/s depends on the Group-AER encoding density, which is not yet known. **Codex or the data-parsing step must report events per frame and events/s on the real recordings.** Until then, no throughput claim about memory is meaningful.
