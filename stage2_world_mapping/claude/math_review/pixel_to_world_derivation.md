# Pixel → World Derivation (hardware-oriented)

Scope: geometry only. It produces formulas, the operation counts they imply, and the error mechanisms. Numbers quoted come from the tiny sanity scripts in `math_review/sanity/`. They assume an ideal pinhole and an *assumed* half-FOV, because **fx is not known** (see `problem_definition_review.md` D3).

## 0. Conventions (proposal; must be fixed in `shared/` before RTL)

- Pixel: integer `x ∈ [0, 959]` (right), `y ∈ [0, 719]` (down). Pixel centre at `x + 0.5`, or ignore the half-pixel and absorb it into cx.
- Camera frame C: `+X` right, `+Y` down, `+Z` forward (optical axis). This is the OpenCV convention, chosen so image axes map directly.
- World frame W: the camera frame at t = 0, i.e., the rotation-stage reference pose. With `+Y` down, *elevation is positive downward*. Flip the sign in readout if desired.
- Rotation: `d_W = R(t) · d_C`, where `R(t)` maps camera to world.
- Euler convention (proposal): `R = R_y(ψ) · R_x(θ) · R_z(φ)`. Yaw ψ is about world Y (vertical, pan), pitch θ is about X (tilt), roll φ is about Z (optical axis), applied intrinsic Z→X→Y. Reason: pan is the dominant motion in the data, so it should be the outermost rotation. Then yaw is a pure azimuth offset in a yaw-centred map (§4).
- Angles: use **binary angle measurement (BAM)**. One full turn is `2^N` codes. Wrap-around is then free two's-complement overflow, with no compare/subtract.

> Codex's golden model may use a different convention. Whatever is chosen, it must be **one** convention in `shared/interfaces/` before any fixed-point comparison. A sign or order mismatch looks exactly like a "mapping error".

## 1. Pinhole: pixel → camera ray

```
u = (x − cx) / fx          v = (y − cy) / fy
d_C = (u, v, 1)            (unnormalized ray; normalization is not needed)
```

- Cost: 2 subtractions plus 2 multiplications by the constants `1/fx`, `1/fy`. With `fx = fy` this is one constant. If a world-angle unit of "1 centre pixel" is used (§6), the multiply disappears entirely: `u·fx = x − cx`.
- Unknowns: `cx, cy, fx, fy`, and lens distortion. Distortion, if modeled, is a 2D static warp `(x, y) → (u, v)`. It belongs in a per-pixel or per-grid table, not in runtime arithmetic.

## 2. Rotation: camera ray → world ray

```
d_W = R · d_C = u·r0 + v·r1 + r2        (r_i = columns of R)
```

- General case: 6 multiplications + 6 additions per event (the `·1` column is free).
- **R changes once per frame, not per event.** DELTA timestamps are per frame (≈ 1 ms). Within a frame, every event uses the same R, unless intra-frame row-time interpolation is used. So R itself (trig of three angles, 27 multiplications) is a **per-frame** cost, roughly 10⁵ cycles at 100 MHz per frame, i.e. negligible.
- Further, `d_W` is *affine in (u, v)*. In raster order, stepping x by 1 adds `r0/fx`. Raster scanning could therefore compute `d_W` with **adders only** (DDA). This only holds if events arrive in raster order (§ input format), so it must be verified on real data.

## 3. World ray → world coordinates (the nonlinear part)

This is where the representation matters (`architecture_candidates/candidate_architectures.md`).

| Representation | Coordinates | Nonlinear ops per event |
|---|---|---|
| Equirectangular (sphere) | `az = atan2(X, Z)`, `el = atan2(Y, √(X²+Z²))` | 2 atan2 + 1 sqrt (or 2 CORDIC vectoring passes: the first yields ρ = √(X²+Z²) for free) |
| Cylindrical | `az = atan2(X, Z)`, `h = Y / √(X²+Z²)` | 1 atan2 + 1 divide (CORDIC vectoring gives ρ, then 1 divide) |
| Cube map | face = argmax\|component\|, `(a, b) = (other/major, other/major)` | 1 reciprocal + 2 multiplications, plus compare logic |
| Planar (one tangent plane) | `(a, b) = (X/Z, Y/Z)` | 1 reciprocal + 2 multiplications; diverges as Z → 0 |

CORDIC note: one vectoring-mode CORDIC on `(Z, X)` returns `atan2(X, Z)` *and* `K·√(X²+Z²)`. A second vectoring CORDIC on `(ρ, Y)` returns the elevation. So the full equirectangular conversion is **two chained vectoring CORDICs**, about 2×(N_iter) shift-add stages, with no multiplier at all.

## 4. Special cases

### 4.1 Yaw-only (rotation about vertical Y), exact

With `R = R_y(ψ)`:

```
X = u·cosψ + sinψ,  Y = v,  Z = −u·sinψ + cosψ
√(X² + Z²) = √(1 + u²)                     ← independent of ψ
az = ψ + atan(u)                             ← exact, additive
el = atan( v / √(1 + u²) )
h  = v / √(1 + u²) = v · c(u),   c(u) = cos(atan u)
```

Key consequences:

1. **Azimuth separates:** `az = ψ + α(x)` with `α(x) = atan((x−cx)/fx)`, a 1D function of the column only. ψ is a per-frame BAM offset, and wrap is free.
2. **Elevation does NOT separate:** `el` depends on both u and v. The naive "el = atan(v)" (treat rows like columns) is wrong at the image corners. Sanity numbers (ideal pinhole, assumed half-FOV θh):

   | θh (assumed) | corner elevation error of naive `atan(v)` |
   |---|---|
   | 20° | ≈ 20 centre-pixels |
   | 30° | ≈ 41 centre-pixels |
   | 40° | ≈ 64 centre-pixels |

   **Any column-LUT mapper that treats y independently will have a large systematic error.** This is a concrete review item for Codex's LUT/linear models.
3. **Cylindrical makes yaw-only almost free:** `h = v · c(x)` is a *product* of a column function and the row offset. A per-column table `{α(x), c(x)}` plus **one multiplication** gives the exact yaw-only cylindrical mapping. In equirectangular, el = atan(h) would need a second nonlinear op. **For yaw-dominant data, cylindrical is strictly cheaper than equirectangular at equal accuracy.**

### 4.2 Roll (about the optical axis)

Roll is an in-plane rotation of `(u, v)`:

`u' = u·cosφ − v·sinφ,   v' = u·sinφ + v·cosφ`

That costs 4 multiplications (constants per frame), or a rotation-mode CORDIC. After roll, u' is no longer an integer column, so a column LUT indexed by x no longer applies. You need `α(u')`, `c(u')` as functions of a continuous argument, i.e., PWL or interpolated LUT. With yaw+roll only, the structure is: rotate in plane → yaw-only formula.

### 4.3 Yaw + pitch (and full 3-axis)

`R_y(ψ)·R_x(θ)`: pitch mixes v into Z, so `√(X²+Z²)` now depends on v and θ. **No separable form exists.** You need the general path, §2 + §3, or an approximation that is not per-event exact (warp grid, §7).

### 4.4 Small-angle approximation

Two different "small" assumptions get confused:

- **Small rotation** (|θ|, |φ| ≪ 1) lets you linearize R about yaw. Useful only for incidental tilt (stage misalignment), not for the ±180° ranges mentioned in Q15.
- **Small field angle** (`atan u ≈ u`) is a global linear mapper. The error at the image edge is `u − atan(u)`. Sanity numbers: about 45 centre-pixels at θh = 30°. A chord fit (slope chosen to hit the edge exactly) gives about 16 px. **Neither is acceptable if the world cell ≈ one sensor pixel.** A global linear mapper is only defensible with very coarse world cells (≥ 16× pixel), or for a narrow FOV.

## 5. Angle wrapping

- Azimuth in BAM with N bits: `az_code = (ψ_code + α_code) mod 2^N`. This is free in two's complement. The world column is the top `log2(N_cols)` bits, *provided N_cols is a power of two*. **Choose N_cols = 2^k** (e.g., 4096 or 8192) so wrap and quantization are bit slicing.
- If N_cols is not a power of two (e.g., exactly 2π·fx), wrap needs a compare-subtract and quantization needs a constant multiply. Avoid this.
- Elevation does not wrap in equirectangular or cylindrical. It saturates or is clipped at the map bounds. Near ±90° the equirectangular azimuth becomes ill-conditioned (pole). The warp-grid sanity run showed the interpolation breaking down when the FOV touches the pole (pitch 60° + 40° half-FOV). Full-sphere coverage needs a cube map, or a pitch limit.

## 6. Equirectangular / cylindrical quantization

- Azimuth cell: `Δaz = 2π / N_cols`. Matching sensor centre resolution needs `N_cols ≈ 2π·fx`. For θh = 30° (fx ≈ 831 px, assumed) that is ≈ 5,220 → choose 4096 (coarser) or 8192 (finer).
- Equirectangular elevation cell `Δel`: pixels at elevation el subtend `Δaz·cos(el)` horizontally. Cells near the top/bottom are therefore over-resolved (wasted memory) by `1/cos(el)`. That is minor below |el| ≈ 30°, but 2× at 60°.
- Cylindrical "height" `h = tan(el)` is uniform in sensor-like units near the horizon and stretches toward the poles. For a yaw-dominant rig with a limited vertical range it fits naturally.
- Rounding rule: keep ≥ 2 guard bits below the cell LSB through the datapath and round once at the end. Truncation biases every event by half a cell in one direction, which appears as a systematic world shift.
- **World-unit choice:** define the angle unit as "one centre pixel" = `1/fx` rad. Then `x − cx` is already in world units at the centre, and fx appears only inside the nonlinear tables. Combined with BAM, this ties `N_cols = 2π·fx` to a power of two only if fx is chosen accordingly. Accept a small scale factor, i.e., world cell ≠ exactly one pixel.

## 7. The per-frame warp-grid formulation

Since `R` is constant per frame and the map `(x, y) → (az, el)` is smooth away from the poles, the frame's mapping can be **sampled** on a coarse grid of control points (spacing T pixels) and **interpolated** per event:

```
per frame:  for each grid node (gx, gy): compute (az, el) exactly (CORDIC, slow, shared)
per event:  bilinear interpolation of the 4 surrounding node values
```

Sanity results (bilinear, ideal pinhole, max error in world cells of `1/fx` rad, rotations up to yaw 37° / pitch 20° / roll 15°):

| θh (assumed) | T = 16 | T = 32 | T = 64 | T = 120 |
|---|---|---|---|---|
| 30° | ≤ 0.05 | ≤ 0.23 | ≤ 0.94 | ≤ 3.3 |
| 40° | ≤ 0.13 | ≤ 0.54 | ≤ 2.2 | ≤ 7.7 |

- The error scales as about T² (second derivative of the mapping), as expected.
- It breaks down only near the equirectangular pole (pitch 60° at θh = 40° in the run), which is a representation problem, not an interpolation problem.
- Grid nodes per frame at T = 32: 31 × 24 = 744. At ~1 node per cycle (pipelined CORDIC), that is < 1 % of a 1 ms frame at 100 MHz.
- The **same structure absorbs** lens distortion, a nominal-depth parallax correction (§8), and intra-frame time interpolation (per grid row), at **zero per-event cost**. Only the node generator changes.

This formulation is the basis of the recommended candidate (`candidate_architectures.md`, D/E).

## 8. Effects outside the ideal model (must be budgeted, not ignored)

| Effect | Formula | Illustration (assumed numbers, labelled) |
|---|---|---|
| Frame-time quantization under rotation | `Δθ = ω · Δt`, with `Δt ≤ 1 ms` per frame | ω = 90°/s gives 0.09° per frame ≈ 1.3 centre-px at θh = 30°. ω = 360°/s gives ≈ 5 px. Per-row time interpolation reduces this only if readout is a time-uniform raster (unverified). |
| Off-axis rotation (rig of Q22) | `ε ≈ (r/D)·sin(off-axis angle)` | r = 4 cm, D = 0.5 m, θh = 30° gives ≈ 0.04 rad ≈ 33 px at the edge. **Dominant if real.** |
| Lens distortion (cheap M12) | radial `k1·r²` … | Unknown. Can be measured from straight rods. |
| Event latency (brightness-dependent) | `Δθ = ω · latency` | Up to seconds for very dark scenes (Q22). That is a per-event bias that no mapper fixes. |

**Implication for precision targets:** the arithmetic only needs to be good to a fraction of the *largest unavoidable* error. If parallax or timing produces several pixels of error on real data, spending area on sub-0.1-pixel trig precision is unjustified. Synthetic validation should still show the mapper is exact to < 0.5 cell, so that the mapper is never the dominant term.

## 9. Operations required per implementation class

Per-event costs (excluding pixel→(u, v) subtracts and memory). "Per-frame" costs are listed separately because they are amortized over all events of a frame.

| Class | Per-event arithmetic | Per-frame | Static storage | Exactness |
|---|---|---|---|---|
| **A. Full floating point** | 6 mult + 6 add (rotation), 2 atan2 + sqrt (equirect) | R from 3 angles | none | Reference only; not a hardware target |
| **B. Yaw-only, exact** | 1 add (az = ψ + α(x)), 1 mult (h = v·c(x)) for cylinder; +1 atan for equirect el | ψ → BAM | column table α, c: 480 entries if symmetric | Exact for pure yaw; wrong under any pitch/roll |
| **C. Small-angle / global linear** | 1 add (az), 0–1 mult | ψ | none | ~16–45 px edge error at θh = 30°; only for coarse maps |
| **D. Piecewise-linear** | 1 small mult + 1 add per nonlinear function (α, c) | ψ (+ roll consts) | K segments × (slope, intercept) | Tunable (see `approximation_analysis.md`); supports continuous input (roll) |
| **E. LUT** | 0 mult (direct) or 1 mult (interpolated) | ψ | Column LUT (exact yaw) or per-pixel 2D LUT (≈ 691 k entries × 2: infeasible) | Exact at table points |
| **F. CORDIC** | ~N_iter shift-add stages × 2 (two vectoring passes), plus 6 mult for rotation (or rotation-mode CORDICs) | R | ~N_iter-entry atan constant ROM | Precision ∝ iterations; full 3-axis |
| **(G) Warp grid** | Bilinear: about 3 small mult + 3 add per coordinate (or adds only in raster) | ~744 nodes via F | 2 node rows (raster streaming) or full grid | ≤ 0.25 cell at T = 32, θh = 30° (sanity); full 3-axis except near poles |
