# Mapper Architecture Candidates

All estimates are **structural** (operator counts, storage bits, pipeline shape). No PPA numbers are claimed. Synthesis is required before any area/power/Fmax statement.

Common assumptions:
- Input event `(x[9:0], y[9:0], p, frame_id)`.
- Per-frame orientation sample.
- Clock ~100 MHz (Stage 1 evidence).
- Memory = assumed synchronous SRAM (see `world_memory_architectures.md`).
- "1 ev/clk" means an initiation interval of 1 in the mapper. Memory may still stall.

---

## A. Full fixed-point geometric pipeline (per-event exact)

```
event → (x−cx, y−cy)·(1/f) → R·d (6 mult, 6 add) → CORDIC vectoring ×2 → BAM slice → address → update
                                ↑ R from per-frame angle → trig (CORDIC rotation, per frame)
```

| Item | Estimate |
|---|---|
| Multipliers | 6 (≈ 16×16) for R·d, +2 if 1/f is not folded |
| Adders | 6 (rotation) + ~2×16×3 (two pipelined CORDICs) ≈ 100 |
| ROM | CORDIC atan constants (~16×16 bits ×2) |
| Pipeline depth | ~3 (rotation) + ~32 (CORDIC) + ~2 ≈ 37 stages |
| Throughput | 1 ev/clk if fully pipelined |
| Memory accesses | 1 RMW per event |
| Error source | CORDIC iterations, word lengths; otherwise exact |
| Scalability | Any rotation, any representation (cube map: replace CORDIC with recip) |
| RTL difficulty | Medium–high (long datapath, careful fixed point) |

Role: **hardware reference** for accuracy, and the "naive" baseline that later candidates must beat in area/energy at equal error.

## B. CORDIC-based mapper (iterative / time-multiplexed)

Same math as A, but one CORDIC stage is reused for ~32 cycles per event.

- Area is low (one stage + control).
- Throughput is ~1/32 ev/clk (≈ 3 M ev/s at 100 MHz).
- Verdict: too slow as the per-event path if real event rates are tens of M ev/s (to be measured from DELTA data). **Ideal as the per-frame node generator for D/E.**

## C. Full-column LUT / PWL yaw mapper (yaw-only, optional roll)

```
event → d = |x−cx|, sign → {α, c} = PWL/LUT(d) → az = ψ_BAM + sign·α ; h = (y−cy)·c → slice → address → update
```

| Item | Estimate |
|---|---|
| Multipliers | 1 (h) + 2 small (PWL slopes, 12×6) or 0 (pure LUT) |
| Adders | ~4 |
| Storage | PWL: ~0.4 kbit coefficients. Exact column LUT: 13–27 kbit |
| Pipeline depth | 3–4 |
| Throughput | 1 ev/clk |
| Memory accesses | 1 RMW per event |
| Error source | PWL segments (≤ 0.3 px at 8 seg/half, θh = 30°, sanity); **pitch/roll ignored** |
| Scalability | Yaw only. Roll adds an in-plane rotation (4 mult) in front. Pitch is not supported. |
| RTL difficulty | **Low** |

Role: **V1 mapper.** It is the smallest correct design for the organizer's single-axis recordings. The roll front-end is optional.

## D. Per-frame warp-grid mapper (coarse-to-fine hierarchical)

The mapping `(x, y) → (az, el)` is smooth and changes only per frame. So sample it exactly on a coarse grid once per frame, then interpolate per event.

```
             per frame (slow, shared)                     per event (fast)
pose ─► R ─► node generator (iterative CORDIC B) ─► node line buffer ─► tile select (x>>t, y>>t)
                    (T=32: 31×24 nodes)                (2 node rows if raster)        │
                                                                                      ▼
                                          event ─► frac (x&(T−1), y&(T−1)) ─► bilinear interp ─► round ─► address ─► update
```

| Item | Estimate |
|---|---|
| Per-event multipliers | Bilinear with precomputed per-tile gradients: `v = n00 + gx·fx + gy·fy + gxy·fx·fy` → 3 small mult (5-bit frac × ~18-bit) per coordinate, 6 total. Triangle (affine) variant: 4 total |
| Per-event adders | ~6–8 |
| Per-frame work | ~744 nodes (T = 32) × ~32 CORDIC cycles ≈ 24 k cycles, about 24 % of a 1 ms frame at 100 MHz with one iterative CORDIC. Fine; or use 2 units |
| Node storage | Full grid: 744 × 2 × ~20 b ≈ 30 kbit (too many flops). **Raster streaming:** 2–3 node rows ≈ 31 × 3 × 40 b ≈ 3.7 kbit |
| Pipeline depth | ~4–5 per event |
| Throughput | 1 ev/clk |
| Memory accesses | 1 RMW per event (improved in E) |
| Error source | Interpolation ∝ T²: ≤ 0.23 cell at T = 32, θh = 30° (sanity); node precision; pole breakdown |
| Scalability | **Full 3-axis.** Also absorbs distortion, nominal-depth parallax, and per-row time interpolation with **no per-event change** |
| RTL difficulty | Medium. Node/event synchronization at frame boundaries needs double-buffered node rows |

Role: **primary V2 candidate.** Key properties:
1. The per-event hardware is tiny and representation-agnostic.
2. All geometric "intelligence" sits in a slow, shared, high-precision unit.
3. The error vs area trade-off is a single parameter T.

Risk: depends on **raster-ordered** input to keep node storage small. If the real decoded stream is not raster order within a frame, a full node frame (~30 kbit) is needed. That is still far smaller than any LUT, but it is not small in flops.

## E. Block-amortized warp mapper + tiled world update (Model2-concept integration)

D plus the Stage 1 idea: keep events grouped and do geometry and memory work **per block**.

```
Group-AER / block packets (anchor, 4×4 valid+pol masks)
   ─► warp interp for anchor only (D) ─► per-block local Jacobian (gx, gy from the same node tile)
   ─► 16 offsets: anchor + J·(dx, dy), dx,dy ∈ {0..3} → shift-add only
   ─► world-patch accumulator (merge events landing in the same cell)
   ─► tile-word RMW on 2×2-interleaved banks (≤ 4 words, conflict-free)
```

| Item | Estimate |
|---|---|
| Per-*block* multipliers | As D for the anchor (6). Offsets via shift-add (dx, dy ≤ 3) |
| Adders | ~16×2 small offset adders (or 4 cycles × 4 lanes) + merge logic |
| Storage | D's node rows + per-block patch buffer (e.g., 8×8 cells × count bits) |
| Throughput | Up to 16 events per block-cycle *if* memory permits. Bounded by bank word width |
| Memory accesses | ≤ 4 word RMWs per block (vs up to 16 cell RMWs) **when** the block's world footprint fits a tile. **Gain = f(block occupancy, world cell scale): must be measured** |
| Error source | Same as D, plus Jacobian linearization over 4 px (≈ T² error with T = 4, negligible) |
| Scalability | As D. Seams/wrap need patch splitting |
| RTL difficulty | **High.** Patch merge, bank routing, snapshot/clear semantics |

Role: **final-submission candidate**, *if* Experiment 03 shows a real reduction in memory traffic on organizer data. It is the most direct answer to the organizer's Q22 request ("reduce accumulation computation, with evidence") and the most natural continuation of Model2.

## F. Tiled local-coordinate mapper

Divide the world into tiles. Keep the "current" tiles in a small local buffer in local coordinates. Events update the buffer, which is flushed to the main memory on eviction.

- Arithmetic is the same as C/D.
- It changes the memory hierarchy: a cache in front of the World Memory. Gains depend on temporal locality, which is high in slow rotation (the same world region is revisited for many frames).
- Overlaps strongly with E (patch accumulator) and with cache-like memory (`world_memory_architectures.md` E). Keep it as a **memory-side** option, not a separate mapper.

## G. Traffic-adaptive precision mapper

`traffic estimator → mode select → {full-precision per-event | binned per-block} → memory`

Analyzed in `adaptive_precision.md`. Summary: changing *spatial precision* by load makes the map's accuracy depend on scene activity. That is hard to defend and hard to verify. **Changing update granularity (E's block path vs per-event path) is defensible; changing precision is not**, except as an explicit overload/drop policy.

## H. Better ideas found during analysis

1. **Rotation is per-frame, not per-event** (enables D). The DELTA frame timestamp makes this exact, not an approximation, at the frame granularity the sensor provides.
2. **Exact separable yaw-only cylindrical mapping** (enables C at 1 multiply). See derivation §4.1.
3. **BAM angles with power-of-two world width:** wrap and quantization become bit slicing.
4. **Raster-streaming node buffer:** exploits the sensor's top-left→bottom-right readout (Q22) to shrink D's storage by ~8×.
5. **On-chip yaw-rate estimator (optional extension):** per frame, accumulate a 1D column histogram of events (960 bins, or 240 with 4× binning). Cross-correlate it with the previous frame's histogram over ±S shifts to obtain Δx per frame ≈ fx·Δψ near the centre. This is cheap (S correlators, or a sequential search between frames) and directly addresses B4 ("rotation speed can be inferred"). It gives *relative* yaw only, with drift. Treat it as a research extension; it is not required for V1.
6. **Nominal-depth parallax correction** inside the node generator for the off-axis rig (problem_definition D1), at zero per-event cost.

---

## Summary table

| | A | B | C | D | E | G |
|---|---|---|---|---|---|---|
| Rotation support | 3-axis | 3-axis | yaw (+roll) | 3-axis | 3-axis | as base |
| Per-event mult | 6–8 | 0 (iterative) | 1–3 | 4–6 | ~6 per *block* | varies |
| Static storage | tiny | tiny | ~0.4 kbit | ~4 kbit (raster) | ~4 kbit + patch | + mode logic |
| Throughput | 1 ev/clk | ~1/32 | 1 ev/clk | 1 ev/clk | ≤16 ev/block-clk | varies |
| Mem access/event | 1 RMW | 1 RMW | 1 RMW | 1 RMW | ≤ 4/block | varies |
| Main error | iterations | iterations | PWL + ignores pitch | T² interp | as D | precision mode |
| RTL difficulty | med-high | low-med | **low** | med | **high** | med-high |

**Three strongest:** C (V1, low risk), D (general, compact), E (D plus Stage 1 continuity and a memory-traffic story). A stays as the per-event-exact reference; B is a building block of D.
