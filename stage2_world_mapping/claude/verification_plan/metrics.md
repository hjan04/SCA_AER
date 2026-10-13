# Validation Metrics

Two classes, never mixed in one claim:
- **[GT]**: needs synthetic ground truth (known pose, known scene).
- **[NoGT]**: usable on real organizer recordings without pose or 3D truth.

Every reported number must state its pose source: *synthetic truth*, *estimated*, or *assumed constant speed*.

## 1. Geometric correctness

| Metric | Class | Definition | Use |
|---|---|---|---|
| Angular reconstruction error | GT | `∠(d_W_est, d_W_true)` per event; report mean, p95, max, in rad and in world cells | Mapper accuracy |
| World address error | GT | `|addr_hw − addr_golden|` in cells (wrap-aware); fraction of exact matches | Fixed-point vs golden; target ≥ 99.x % exact, max ≤ 1 cell |
| Error map vs pixel position | GT | Error as a function of (x, y) | Separates PWL edge error, corner (elevation-coupling) error, and pole effects |
| Bit-exact map equality | GT/NoGT | Final world memory of RTL == golden fixed-point model, same events and poses | RTL sign-off. Requires commutative cell semantics |

## 2. Map quality without ground truth

| Metric | Class | Definition | Notes |
|---|---|---|---|
| **Repeatability under revisit** | NoGT | Map region built from pass 1 vs pass 2 over the same directions: normalized cross-correlation, or the shift maximizing it | A correct mapper gives zero shift. A non-zero shift measures pose/scale/parallax error. **Strongest no-GT metric** |
| **Spatial concentration / sharpness** | NoGT | Map entropy, gradient energy, or contrast (variance of the event-count image), as in contrast-maximization literature | Higher = better aligned. Compare variants on identical events. Not an absolute accuracy |
| **Straight-edge consistency** | NoGT | Vertical rods (Q22) must map to straight, vertical lines in a cylindrical map. Measure line-fit residual and tilt | Detects fx error, roll, distortion. Rods are the organizer's own suggested reference |
| **Feature consistency** | NoGT | Track rod positions across frames in world coordinates. Std-dev of their world azimuth | Should be ~0 for static rods. Grows with parallax for near rods → measures D1 |
| **Temporal stability** | NoGT | Map change between consecutive windows in regions not currently in view | Stale/decay behaviour |
| **Coverage** | NoGT | Fraction of map cells touched; azimuth span | Sanity check of the pose trajectory |
| **Moving-object residual** | NoGT | Cells whose events do not re-register (fan, Sept 15) | Qualitative attention map (B10) |

## 3. Hardware behaviour

| Metric | Class | Definition |
|---|---|---|
| Throughput | both | Sustained events/cycle at the mapper and at memory; burst tolerance |
| Memory update rate | both | Memory RMW (or word access) per delivered event. **Key metric for candidate E** |
| Collision rate | both | Fraction of events whose target cell is already in flight (forwarding hits); same-cell merges per block |
| Bank conflict rate | both | Per-event banked path only |
| Dropped events | both | By reason: queue full, out of map band, invalid pose. Must be zero in the non-overload regime |
| Saturation count | both | Cells/updates hitting the max. Flags hot pixels |
| Latency | both | Event-in to memory-write cycles: mean, p99 |
| Energy proxy | both | Toggle-based activity → Genus power with real traces (Stage 1 method) |

## 4. Rules

- Compare variants only on **identical** event and pose streams with an identical error definition (Stage 1 fairness discipline).
- Report mapper error and pose error separately. On real data, pose error is unknown. State it as such; do not fold it into "mapper error".
- Sharpness/contrast metrics are **relative**. Never present them as absolute correctness.
