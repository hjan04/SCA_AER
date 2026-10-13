# World Representation: Is Equirectangular the Right Hardware Choice?

Codex starts from an equirectangular directional map. That is a sound *reference* choice. This document asks whether it is the best *hardware* choice.

Notation: event costs are per event. "Per frame" costs amortize over all events of a 1 ms frame. Derivations are in `math_review/pixel_to_world_derivation.md`.

## 1. Candidates

### R1. Equirectangular (az, el), full sphere

- **Address generation:** `az = atan2(X, Z)`, `el = atan2(Y, ρ)`. Two nonlinear ops in general; yaw-only still needs an atan for el. Column = top bits of BAM azimuth, so wrap is free.
- **Distortion:** horizontal over-sampling `1/cos(el)` toward the poles; singular at the poles.
- **Metadata:** none (implicit addressing).
- **Memory utilization:** good near the horizon. Wasted near the poles if the map spans ±90°. If the rig never pitches far, store only an elevation band, e.g. ±45°.
- **Yaw / pitch:** yaw is a pure column shift (free). Pitch needs full geometry.
- **Full rotation:** yes, except near the poles, where warp-grid interpolation also breaks.
- **Sparse events:** fine. Each event addresses one cell.
- **RTL complexity:** medium (two nonlinear functions, or a warp grid).

### R2. Cylindrical (az, h = tan el)

- **Address generation:** yaw-only is **exact with one 1D table pair plus one multiply** (`h = (y−cy)·c(x)`). General rotation needs `atan2` + one divide.
- **Distortion:** h stretches as tan(el). Unusable beyond about ±60°, and h diverges at ±90°.
- **Metadata:** none.
- **Memory utilization:** excellent for a yaw-dominant rig with limited tilt. The height can match the sensor's vertical extent plus a pitch margin.
- **Yaw / pitch:** yaw is free. Small pitch is fine. Large pitch is not.
- **Full rotation:** no.
- **Sparse events / RTL:** simplest of all for yaw-only.

### R3. Planar tiled map (one or several tangent planes)

- **Address generation:** `(X/Z, Y/Z)`, one reciprocal + 2 mult. Exactly a homography per frame, which is projective-linear in (x, y): numerator and denominator can be stepped incrementally.
- **Distortion:** grows as tan of the angle from the plane normal. Diverges at 90°. A single plane cannot represent a ±180° sweep.
- **Metadata:** plane id if several planes.
- **Memory utilization:** good inside ±40° of the plane normal, terrible beyond.
- **Full rotation:** only as a set of planes, i.e., a **cube map** (R5).
- **Verdict:** a single plane is a good *local* representation (e.g., a "current view" buffer), but not a world map.

### R4. Direct ray / angle-bin representation (no image-like map)

- Store `(az, el)` bins in a hash/sparse structure rather than a dense 2D array.
- **Address generation:** same geometry as R1, plus hashing.
- **Metadata:** tags per entry.
- **Memory utilization:** good if the scene is sparse in *directions*. Edge maps are sparse per frame, but over a full sweep, edges cover a large fraction of the band.
- **RTL complexity:** high (tags, collisions, eviction). This is a memory organization (`world_memory_architectures.md` D/E) more than a representation.

### R5. Cube map (6 faces × planar)

- **Address generation:** face = argmax over |X|, |Y|, |Z|, three compares. Then `(a, b) = (minor/major)`: 1 reciprocal + 2 multiplications. **No trig at all.**
- **Distortion:** at most ≈ 3× area ratio between face centre and corner (≈ 1.7× linear). No singularities.
- **Metadata:** 3-bit face id. Seams require care (a 4×4 block can straddle two faces).
- **Memory utilization:** uniform-ish. The full sphere costs 6 face² cells.
- **Full rotation:** **yes, the only candidate here that is singularity-free.**
- **RTL complexity:** medium. The reciprocal is the hard part (LUT + Newton step, or a small divider). Seams complicate block updates.

### R6. Hybrid: cylindrical band + polar caps (or cube map only when needed)

Store the yaw band (where almost all data lands for these rigs) cylindrically and add small caps only if pitch exceeds the band. This is complex and is only justified if the real data shows large pitch.

## 2. Comparison

| | R1 Equirect | R2 Cylinder | R3 Plane | R4 Ray bins | R5 Cube |
|---|---|---|---|---|---|
| Per-event cost, yaw-only | 1 add + atan(el) | **1 add + 1 mult** | 1 recip + 2 mult | as R1 + hash | 1 recip + 2 mult |
| Per-event cost, 3-axis | 2 atan2 + sqrt (or warp grid) | atan2 + div (or warp grid) | recip + 2 mult | as R1 + hash | **recip + 2 mult, no trig** |
| Wrap handling | free (BAM) | free (BAM) | n/a | free | face logic |
| Singularities | poles | ±90° | ±90° from normal | poles | none |
| Metadata | none | none | plane id | tags | face id |
| Memory use for yaw rig | good | **best** | poor | variable | ok (top/bottom faces mostly unused) |
| Block-update locality | good | good | good | poor | seams |
| RTL difficulty | medium | **low** | low | high | medium |

## 3. Recommendation

| Version | Representation | Why |
|---|---|---|
| **V1** | **Cylindrical, yaw band** (az: 2^k columns over 360°; h: sensor height plus pitch margin) | The organizer data is yaw-dominant. Exact yaw-only mapping costs 1 multiply plus a tiny table. This gives the fastest path to a correct, demonstrable map. |
| **V2** | **Equirectangular band** (|el| ≤ ~60°) addressed through the **warp grid** | Once pitch/roll are supported, the warp grid makes per-event cost independent of representation. Equirect is then preferred for uniform angular cells and a simple readout panorama. |
| **Final** | **Equirectangular band via warp grid**, *unless* the real data or organizer spec demands near-pole views. In that case switch to a **cube map** behind the same warp-grid interface. | The warp-grid node generator hides the representation from the per-event path. Switching to a cube map changes the node generator and address slicing, not the event datapath. Keeping that switch cheap is a design goal. |

**Important nuance:** with a warp grid, the per-event datapath cost becomes almost independent of the representation. The representation choice then reduces to **memory utilization, distortion, and readout convenience**, not arithmetic. This weakens the case for a cube map (its no-trig advantage disappears) unless pole coverage is needed.

**Challenge to the default:** equirectangular is the right *golden-model* representation, because it is easiest to reason about. For V1 hardware, cylindrical is strictly cheaper for the data we actually have. **Recommend Codex's golden model support both** (they share azimuth), so Experiment 02 can compare them on identical events.
