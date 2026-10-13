# Post-Experiment-03 Recommendation

Supersedes nothing. `recommended_v1.md` is kept as the pre-Exp03 record. Evidence: `verification_plan/exp03_summary.md` and `verification_plan/exp03_results/`. All locality numbers are image-space measurements on the three real recordings. World-space effects are not yet measured, because there is no pose.

## Before vs after

**BEFORE EXP03 (hypothesis):** Architecture E (block-amortized transform + tiled/banked world update) *may* reduce memory traffic. Its value was explicitly conditional on real block occupancy (decision-matrix assumption 3).

**AFTER EXP03 (measured):**
- Real traffic **does** contain enough within-frame spatial locality to amortize the coordinate transform:
  - 82–83 % of events share a 4×4 block, and 95–96 % share an 8×8 block, in the same 0.773 ms frame;
  - transform amortization is 2.6× (4×4), 6× (8×8), and 3.3× per native sensor word.
- The memory-update reduction it buys is **modest at 4×4** (conservative 0.81 of per-event RMWs) and **substantial only at 8×8+** (conservative 0.46, ideal 0.16), and only counts accesses, not bits.
- The measured event rate (47–55 M ev/s mean, ~100 M ev/s at p95 frames, 163 M ev/s peak) exceeds what a single 1-event/cycle, 1-RMW/event pipeline sustains at ~100 MHz. **Pure per-event D at one lane is not sufficient for real traffic.** Either grouping (E) or replication (D × N lanes + banks) is mandatory.
- Classification of E: **B: promising, needs RTL cost check.**

## New facts that change earlier recommendations

1. **Sept 22 motion is roll-like** (concentric event rings around ≈ (470–520, 390–410)), not yaw. Inferred, not ground truth. The yaw-only V1 (Candidate C) can only serve the Sept 15 data. **The mapper must support roll from V1**, either as an in-plane rotation before the yaw table or directly via the warp grid D. This strengthens D.
2. **The stream is column-major** (x strictly non-decreasing per frame). Warp-grid nodes must be buffered as **columns** (~2 × (720/T + 1) nodes), not rows. 2-D block assembly needs a B-column strip buffer.
3. **The sensor already performs Model2-like grouping** (1×8 column groups, two per 32-bit word). Model2 re-packetization is redundant. Model2's *occupancy-threshold break-even* is directly useful.
4. **Noise:** about 25 % of events are spatially isolated. Hot pixels are negligible. A neighbour-support noise filter is a cheaper, larger lever on memory traffic and map quality than a hot-pixel mask. It is optional, and must be weighed against losing true sparse events.

## Recommendations

| Topic | Recommendation | Basis |
|---|---|---|
| **Mapper granularity** | Consume **one sensor word per cycle** (one column, up to two 8-pixel groups). Compute one warp interpolation per group anchor and derive the ≤ 8 pixels by a per-column Jacobian step along y (shift-add). | 3.3–3.45 events/word for free, no reordering buffer; worst-case need ≈ 48 M words/s, which fits 1 word/clk at 100 MHz with ~2× margin. *Exactness of the y-step must be checked against Codex Exp02 error budgets.* |
| **Block amortization (E)** | Keep E alive in a *reduced* form ("E-lite"): word-level transform sharing (above), plus an **optional 8×8 merge stage** behind the mapper, enabled per block only above an occupancy threshold (Stage 1 break-even idea). Decide by RTL cost check against **D × 2 lanes + 4 banks**. | 8×8 is the measured knee. 4×4 merging saves only ~20 % of accesses conservatively. Thresholding avoids the always-grouped penalty |
| **Block size** | Transform: native 1×8 group / sensor word. Memory merge (if built): **8×8 image block → world tile word**. Do not build 4×4 block assembly alone | §4–§7 of the summary |
| **Memory banking** | Interleave along the scan's fast axis: per-event path banks by low bits of the *row-like* world coordinate (image analogue: y mod 4 had 15–16 % consecutive conflicts vs 98 % for x parity). Tiled block path: 2×2 tile-parity banks (conflict-free for footprints ≤ 1 tile). **Re-measure in world space with pose** before freezing | Banking table §11 |
| **Accumulator semantics** | **Option B: separate saturating ON/OFF counts, 2–3 bits each** (V1: 2+2 bits). Option A (one unsigned count) is the memory-saving fallback. **Reject Option C** (signed) as sole content | Polarity is balanced overall but spatially segregated, and roll revisits a region from changing directions, so signed sums would cancel structure. Repeats are mostly same-polarity, so saturation is the main overflow mode. All three options are commutative, so merge/reorder stays bit-exact verifiable |
| **Throughput target** | Design for **≥ 100 M pixel events/s sustained** (p95 frame) with frame-level buffering for peaks to 163 M ev/s, or document a counted overload policy | §2 of the summary |
| **Noise** | V1: no filter (keep the measurement honest). V2 option: 3×3 same-frame neighbour-support filter, evaluated for map quality vs dropped real events | §3B |

## What is needed from Codex Exp02 before RTL

1. **Roll accuracy:** error of the warp grid (T = 16/32/64) and of the yaw table + in-plane rotation under roll up to ±180° about an off-centre axis. The Sept 22 data needs this.
2. **Per-group Jacobian step error:** max world-address error when the 8 pixels of a column group are derived from one anchor + a linear y-step, vs per-pixel exact mapping, at world scales s = 1, 1/2.
3. **World-footprint statistics:** for 1×8 groups and 8×8 blocks under roll/yaw, how many world tile words (k) do they touch for tile sizes 4×4 and 8×8? This converts §7's image-space proxy into a real RMW reduction.
4. **Cross-frame world collision rate** (same world cell hit in consecutive frames) under realistic angular speed. This decides whether a small world-space write-combining cache beats per-frame merging.
5. **Fixed-point widths** satisfying ≤ 0.25 cell error for the chosen granularity.

## What should not happen next

- Do not build 2-D 4×4 block assembly in front of the mapper (low payoff, strip-buffer cost).
- Do not instantiate Model2 RTL as a front-end.
- Do not quote multi-frame image-space merge ratios (0.02–0.2) as achievable memory savings.
- Do not quote image-space banking conflict rates as world-memory conflict rates.
