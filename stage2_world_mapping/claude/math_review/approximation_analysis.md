# Approximation Analysis: PWL, LUT, LUT+Interpolation, CORDIC, Warp Grid

All numbers are **sanity calculations** under an ideal pinhole and an *assumed* half-FOV θh (fx unknown). They are not measurements of any design and not a substitute for Codex's quantitative experiments. Scripts: `math_review/sanity/`.

Error unit: **centre pixels** (`err_rad × fx`), i.e., the angular size of one sensor pixel at the optical axis. A world map with one cell per centre pixel needs mapper error well below 0.5 cell.

## 1. Which functions actually need approximating

From `pixel_to_world_derivation.md`:

- Yaw-only, cylindrical: `α(x) = fx·atan((x−cx)/fx)` and `c(x) = 1/√(1+((x−cx)/fx)²)`, both 1D in the column. Then `az = ψ + α`, `h = (y−cy)·c`.
- Yaw + roll: the same two functions, evaluated at a *continuous* rotated column u'.
- Full 3-axis: no 1D function suffices. Use CORDIC, or a warp grid.

Both α and c are **even/odd symmetric about cx**: `α(−d) = −α(d)`, `c(−d) = c(d)`. Only half the image needs coefficients. Cost: one absolute value plus a sign restore.

## 2. Piecewise-linear (PWL), in detail

### 2.1 Segment layout

Use `d = |x − cx| ∈ [0, 480)` with **power-of-two segment width S**:

```
seg   = d >> log2(S)          (no comparators, just bit slicing)
local = d & (S−1)
α ≈ b_seg + a_seg · local
```

### 2.2 Error vs segment count (per half image)

Max error in centre pixels. *Chord* = segments interpolate the true endpoints, so the result is continuous. *Minimax* = intercept shifted per segment, about 2× better, but small discontinuities appear at segment boundaries.

| θh (assumed) | S = 128 (4 seg) | S = 64 (8 seg) | S = 32 (15 seg) | S = 16 (30 seg) |
|---|---|---|---|---|
| **α**, 20° | 0.85 / 0.42 | 0.22 / 0.11 | 0.05 / 0.03 | 0.01 / 0.01 |
| **α**, 30° | 1.59 / 0.78 | **0.40 / 0.19** | 0.10 / 0.05 | 0.03 / 0.01 |
| **α**, 40° | 2.31 / 1.14 | 0.58 / 0.28 | 0.15 / 0.07 | 0.04 / 0.02 |
| **c·360** (h at worst row), 30° | 1.03 / 0.51 | 0.27 / 0.13 | 0.07 / 0.03 | 0.02 / 0.01 |
| **c·360**, 40° | 2.11 / 1.04 | 0.55 / 0.27 | 0.14 / 0.07 | 0.04 / 0.02 |

Observations:

- Error ∝ S², as expected for linear interpolation (`|f''|·S²/8`).
- **8 segments per half (16 total) puts both functions below about 0.3 px for θh ≤ 30°.** 15 per half gets below 0.15 px up to 40°.
- A global linear fit gives 16 px (chord) to 45 px (tangent) at 30° (`pixel_to_world_derivation.md` §4.4). Going from 1 to 8 segments is a ~40–100× error reduction for a few hundred bits of coefficients.

### 2.3 Centre vs edge behaviour

`atan''(u) = −2u/(1+u²)²` is **zero at the centre** and peaks at u = 1/√3 (30° off-axis). So:

- Centre segments are almost exactly linear. Their error is dominated by coefficient quantization, not curvature.
- Edge segments carry the error for θh ≤ 30°. For θh > 30°, the worst segment is interior, around the 30° field angle.
- A **non-uniform** layout (wide segments in the centre, narrow toward 30° field angle) could reach the same max error with fewer segments. But it needs comparators or a small priority encoder instead of bit slicing. Recommendation: **uniform power-of-two first**. Non-uniform is an optimization only if coefficient storage turns out to matter, which is unlikely (§2.4).

### 2.4 Coefficient storage and width

- Slope of α: `1/(1+u²) ∈ [cos²θh, 1]`, i.e., [0.75, 1] at 30° and [0.59, 1] at 40°. Unsigned fixed point, 1 integer bit plus F fractional bits.
- Slope quantization error times the max local offset must stay below budget: `2^−F · S < e_budget`. For S = 64 and e_budget = 0.05 px, F ≥ 11. So **≈ 12-bit slopes**.
- Intercept: range up to about `fx·θh` (≈ 435 px at 30°), plus ≥ 4 fractional guard bits. So **≈ 13–14-bit intercepts**.
- Storage for α and c, 8 segments each, half image: `2 functions × 8 × (12 + 14) ≈ 416 bits`. That is a few hundred flops or a tiny ROM. Compare with a full exact column LUT (§3) at about 13 kbit.
- **Programmability:** because fx is unknown, the coefficients should live in a small register file loaded at configuration time. Do not hard-code them as constants in synthesis. Hard-coding would make the design valid for one guessed fx.

### 2.5 Multiply vs shift-add

- `a_seg · local`: 12-bit × 6-bit (S = 64), a small multiplier, about 72 partial-product bits. In GPDK045 this is likely well below the cost of the memory controller. It still needs synthesis evidence.
- Shift-add alternative: restrict slopes to sums of 2–3 signed powers of two (CSD). That removes the multiplier but increases error, because the slope is no longer free. It is only worth testing if the multiplier shows up in the critical path.
- In **raster order**, `local` increments by one per column, so `α` can be stepped with one adder (DDA): `α += a_seg`. That is zero multiplications. It is only valid if events are processed in raster order *including skipped columns*, i.e., the stepping must jump by the gap `Δx·a_seg`, which is a multiply again unless gaps are small. It is not obviously better than the 12×6 multiplier. The idea is listed, not recommended.

### 2.6 Half-image coefficient reuse

Yes. α is odd and c is even about cx. One table serves both halves at a cost of an abs/negate pair. This assumes cx is exactly the image centre. If calibration gives an off-centre cx, either keep full-image tables (2× storage, still tiny) or offset the input. **Keep the full-table option configurable.** It costs about 400 more bits.

## 3. LUT options

| LUT | Entries | Width | Bits | Verdict |
|---|---|---|---|---|
| Per-pixel 2D `(x, y) → (az, el)` | 691,200 | 2 × 14 | ≈ 19 Mbit | **Infeasible.** Bigger than any sensible World Memory. It is also static, so rotation must still be applied after it. |
| Per-pixel 2D `(x, y) → ray (u, v)` | 691,200 | 2 × 12 | ≈ 16 Mbit | Same. Only useful if distortion must be exact per pixel. |
| Column table `x → {α, c}` (exact yaw) | 960 (480 symmetric) | 2 × 14 | 13–27 kbit | Feasible but large in flops. Exact for yaw-only only. |
| Coarse LUT + linear interpolation | 480/S + 1 nodes | 2 × 14 | ≈ 0.3–0.5 kbit (S = 32–64) | **Equivalent to chord PWL** (§2) with the slope computed from neighbouring nodes. It saves storing slopes but adds a subtractor. |

**Is a large per-pixel LUT necessary? No.** Even the exact 1D column LUT is not necessary. PWL or LUT+interpolation with 8–16 segments per half gets the mapping error well under one centre pixel, under the stated assumptions. The interesting question is not LUT vs PWL. It is whether *pitch/roll support* is needed (then neither 1D approach suffices; see §5).

**LUT+interpolation vs pure PWL:** functionally the same accuracy class.
- PWL stores slopes, so there is no subtractor and the slope is minimax-tunable.
- LUT+interp stores only node values, so it is continuous by construction and costs half the storage.

Pick whichever matches Codex's modeling. Recommend **LUT+interp with 2^k spacing** as the cleanest bridge between Codex "Model L" (column LUT) and "Model A" (linear). The same table at spacing 1 *is* Model L. At spacing 480 it is Model A (chord). One parameter sweeps the whole design space. Experiment 02 should run exactly this sweep.

## 4. CORDIC

- Vectoring mode on `(Z, X)` gives `atan2` and `√(X²+Z²)`. Chaining a second vectoring pass gives elevation. Each iteration is 2 add/sub + 1 angle add, about 1 bit of angle precision per iteration.
- To reach 0.1 centre-pixel at fx ≈ 830 (≈ 1.2×10⁻⁴ rad ≈ 2⁻¹³), you need about **14–16 iterations per pass**, plus guard bits on X, Z (≥ log2(iterations) extra bits).
- Fully pipelined: about 30 stages for two passes, 1 event/cycle, roughly 30 × (3 adders of ~20 bits) ≈ 90 adders plus pipeline registers. That is the **area-heavy** option per event. Iterative (1 stage, ~30 cycles/event) is cheap but gives ≈ 3 M ev/s at 100 MHz, likely far below real event rates (an event-rate measurement on the DELTA recordings is still needed).
- **Verdict:** CORDIC is justified as a *per-frame* engine (warp-grid node generator, R computation), where its low area and slow iterative form fit perfectly: ~744 nodes per frame × ~32 cycles ≈ 24 k cycles < 100 k cycles per 1 ms frame at 100 MHz. It is **not** justified as the per-event path unless 3-axis exactness per event is demanded *and* event rate is low.

## 5. Approximation class vs motion class

| Motion supported | Cheapest exact-enough per-event method |
|---|---|
| Yaw only | Column PWL/LUT+interp for {α, c} + 1 multiply + BAM add |
| Yaw + roll | In-plane rotation (4 mult with per-frame constants) + PWL on a continuous argument |
| Yaw + pitch (+ roll) | **Warp grid** (per-frame CORDIC nodes + per-event bilinear), or full per-event CORDIC |
| Including near-pole views | Warp grid over a **cube map**, or a pitch limit |
| Off-axis orbit (Q22 rig) with nominal depth | Warp grid. The parallax term is added in the node generator; per-event cost does not change |

## 6. Error budget philosophy

Mapper approximation error should be a **minor term**: target ≤ 0.25 world cell (synthetic, exact pose). The unavoidable terms dominate on real data: frame-time quantization (ω·1 ms), off-axis parallax, pose estimation error, and lens distortion. Precision beyond that budget costs area and power without visible benefit. That is the quantitative argument against both a per-pixel LUT and a full per-event CORDIC.
