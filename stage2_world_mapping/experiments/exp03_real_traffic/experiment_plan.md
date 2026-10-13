# Experiment Plan (Experiment 02+)

Experiment 01 belongs to Codex (rotation-only golden/LUT/linear models). This plan proposes what comes after it, **prioritized by whether the result can change an architectural decision**. Tests that cannot change a decision are listed last or dropped.

Deadline context: final submission Oct 30. RTL should start by roughly Oct 15–17 (team plan). Only P0/P1 fit before RTL.

## P0: decision-changing, run before any RTL

### Exp 02: Approximation sweep (one parameterized mapper, one table)

- **Question:** what is the cheapest per-event mapper whose error is ≤ 0.25 world cell?
- **Sweep:**
  - LUT+interp node spacing S ∈ {1 (=column LUT), 16, 32, 64, 128, 480 (=chord linear)};
  - warp-grid tile T ∈ {16, 32, 64};
  - fixed-point fraction bits;
  - fx (half-FOV θh ∈ {20°, 30°, 40°}), because fx is unknown;
  - representation ∈ {cylindrical, equirectangular}.
- **Motions:** pure yaw; yaw + roll ≤ 15°; yaw + pitch ≤ 20°.
- **Also measure:** the naive "el = atan(v)" separable model, to quantify the corner-coupling error (sanity predicts ≈ 41 px at 30°).
- **Decides:** C vs D for V1/V2; PWL segment count; T; word widths.

### Exp 03: Real-data traffic characterization (requires parsed `.dvs`)

- **Measure:** events/frame, events/s, burstiness; Group-AER group geometry and occupancy histogram; raster ordering within a frame; repeat rate per pixel per frame; hot-pixel list.
- **Then simulate (software):** per-event RMW count vs block-path word count for world scales s ∈ {1, 1/2, 1/4} and tile k ∈ {4, 8}.
- **Decides:**
  - whether E (block amortization) is worth building;
  - required memory bandwidth (single vs dual port, number of banks);
  - whether raster streaming of warp nodes is valid.

### Exp 04: Real-data parallax and pose sanity (Sept 22 rig)

- **Measure:** world-azimuth spread of rod features vs their image position, under the rotation-only model; fit `r/D` per rod.
- **Decides:** whether a nominal-depth correction (node generator) is needed, and what accuracy claim is honest on real data.

## P1: important for robustness and claims

| Exp | Scenario | Why it matters |
|---|---|---|
| 05 | **Varying yaw speed** (synthetic, ω ∈ {30, 90, 180, 360}°/s) with per-frame vs per-row time | Quantifies ω·Δt smear and whether per-row interpolation is worth it |
| 06 | **World-map resolution sweep** (cols ∈ {1024, 2048, 4096}) × cell bits {2, 4, 8} | Memory budget vs map quality; picks N×M (organizer explicitly asks for this justification) |
| 07 | **Wrap-around** (sweeps crossing az = 0/2π) and **revisit** | Checks BAM wrap, tile parity at wrap, repeatability metric |
| 08 | **Coarse binning 2×2 / 4×4** at matched world scale | Determines whether binning is an acceptable front-end reduction (organizer is undecided) |
| 09 | **Event-density bursts + high collision rate** (synthetic edges at slow ω → repeated same cell) | Forwarding/stall correctness and throughput; RMW hazard coverage |
| 10 | **Noisy/hot pixels** (real data: unfiltered) | Saturation behaviour; whether a cheap hot-pixel mask is needed |

## P2: only if time remains or a P0 result points there

| Exp | Scenario | Condition to run |
|---|---|---|
| 11 | Full roll ±180° / pitch beyond 45° / near-pole views | Only if organizer data includes them → cube-map decision |
| 12 | Edge-of-image events specifically | Already covered by the error map in Exp 02 |
| 13 | FOV/fx sweep beyond Exp 02 | Only if fx calibration remains uncertain |
| 14 | Uneven scene texture | Covered implicitly by real data; synthetic only if the sharpness metric behaves oddly |
| 15 | LUT precision sweep beyond Exp 02 | Only if the chosen widths are on the critical path |

## Dropped / not recommended

- Exhaustive 3-axis random-pose sweeps. They don't decide anything beyond Exp 02's structured motions.
- Precision-adaptive (G3/G4) experiments, unless the team decides to pursue them against the recommendation.

## Experiment contract (proposal for `shared/experiment_contracts/`, team decision)

- Event stream file: `(frame_id, x, y, p)` + optional `row_time`.
- Pose stream: `(frame_id, t, yaw, pitch, roll)` in the convention of `pixel_to_world_derivation.md` §0, plus a `pose_source` field.
- Config: `cx, cy, fx, fy`, representation, map size, cell semantics.
- Outputs: per-event addresses (GT runs), final map, counters (metrics.md §3).
