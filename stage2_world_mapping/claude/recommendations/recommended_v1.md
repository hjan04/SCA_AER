# Recommended Architecture (current hypothesis)

Status labels used below:
- **[M]** measured, in this repo or by sanity calculation;
- **[H]** hypothesis;
- **[A]** assumption.

No Stage 2 hardware has been synthesized. All PPA statements are [H].

## 1. One-sentence recommendation

Build a **per-frame warp-grid mapper**. A slow, shared unit computes exact world coordinates at a coarse grid of pixel positions once per frame, and a tiny per-event datapath interpolates them. Start in V1 with a yaw-only node generator and a cylindrical map. Then upgrade only the node generator for 3-axis / parallax. Add Model2-style block amortization of memory updates only if real-data traffic shows it pays.

## 2. Why this and not the alternatives

| Claim | Status |
|---|---|
| Orientation changes per frame (DELTA: one timestamp per ~1 ms frame), so per-event trig is redundant work | [M] format fact (Q22, NRV docs); time quantization ω·1 ms is real and is budgeted separately |
| Per-pixel 2D LUT ≈ 16–19 Mbit, infeasible | [M] arithmetic |
| Global linear `atan(u) ≈ k·u`: about 16–45 centre-px edge error at θh = 30° | [M] sanity (assumed θh) |
| Naive separable elevation `atan(v)`: about 41 px corner error at θh = 30° | [M] sanity. **Review item for Codex's LUT/linear models** |
| Yaw-only cylindrical mapping is exactly `az = ψ + α(x)`, `h = (y−cy)·c(x)` | [M] derivation |
| PWL with 8 segments/half: ≤ 0.4 px chord (≤ 0.2 minimax) at θh = 30° | [M] sanity |
| Warp grid T = 32: ≤ 0.23 cell at θh = 30°, ≤ 0.54 at 40°, for yaw ≤ 37°/pitch ≤ 20°/roll ≤ 15° | [M] sanity |
| For yaw-only, the warp grid *is* LUT+interp with S = T, so V1 and V2 share one per-event datapath | [M] derivation (bilinear is exact along y for the cylinder; interpolates α, c along x) |
| Memory RMW bandwidth, not arithmetic, is the system bottleneck | [H]. Needs the event rate from Exp 03 |
| Block amortization (E) reduces memory traffic on real data | [H]. Needs Exp 03 occupancy histograms |
| Off-axis parallax on the Sept 22 rig may exceed all mapper errors | [H] with illustrative numbers. Needs Exp 04 |

## 3. Versions

| | V1 (target ~Oct 15–20) | V2 | Final (if evidence supports) |
|---|---|---|---|
| Motion | yaw (+ optional roll) | yaw/pitch/roll | same + nominal-depth parallax |
| Node generator | yaw-only: tiny column node table {α, c} at spacing T + ψ add | iterative CORDIC (R + 2 vectoring) | + parallax term, + per-row time |
| Per-event datapath | bilinear interp + round + BAM slice | **unchanged** | unchanged |
| Representation | cylindrical yaw band | equirect band (or cylinder if pitch small) | equirect band / cube if poles required |
| World memory | dense, 1 RMW/event, forwarding, 4 b/cell (2 b ON + 2 b OFF sat. counts) | same + epoch tags | tiled words, 2×2 parity banks, block patch merge (E), lazy decay |
| Input | decoded sparse events + frame tag (I2) | same | Model2-vocabulary sparse/dense packets + frame tag (I3) |

## 4. Safe vs configurable assumptions

**Safe for V1:**
- [A] Ideal pinhole.
- Orientation provided as a per-frame input stream.
- Rotation-only geometry.
- Synthetic data for exactness; Sept 15 data for the demo.
- Decoder and pose estimation outside the hardware boundary.
- Commutative cell semantics.
- ~100 MHz clock.

**Must stay configurable (registers/parameters, not constants):**
- `cx, cy, fx` (or the node table contents);
- the Euler convention and sign conventions (fixed in `shared/`, but the node generator isolates them);
- warp tile size T;
- map columns (power of two) and rows/band;
- cell width and semantics;
- the memory latency/port model;
- per-frame vs per-row time;
- the world scale s relative to sensor pixels.

## 5. RTL block decomposition

See `rtl_block_decomposition.md`.
