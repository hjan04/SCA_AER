# Real-Data Validation Strategy

Raw files are read-only. Work from exported copies (HDF5 via DVS Viewer **Export**, or SDK parsing) outside the raw directory.

## 1. What data exists

| Recording | Status | Content (per Q&A) |
|---|---|---|
| `2026-09-15-14-27-41-DELTA.dvs` (108 MB) | Local: `~/DELTA_SDK-1.0.0/Linux/x64/RawDataSave/` | About 2 s horizontal sweep, left → right in one plane; a moving fan and some moving objects |
| Sept 22 recording 1 | Team plan says secured; **not in repo** | Camera on a rod, orbiting the rod (off-axis); vertical rods at about 0.5 m |
| Sept 22 recording 2 | Same | Rod on a larger turntable: two axes, larger radius |
| Promised: binned (2×2/4×4) data, rotation-axis info, re-measured distances | Pending | — |

## 2. Pose without ground truth

Options, in order of rigor:

1. **Organizer-provided axis info and constraints** (single axis, plane) restrict the pose to 1 DoF (yaw) for the Sept 15 data.
2. **Estimate yaw(t) from the data**, offline in software (it is not part of the measured hardware):
   - (a) frame-to-frame column-histogram shift → Δx/frame → Δψ = Δx/fx near the centre;
   - (b) contrast maximization over a constant ω per window (maximize map sharpness);
   - (c) rod tracking: vertical rods are straight features whose image x gives the bearing.
3. Estimate fx jointly: one full revolution, if present, must close (360° ↔ total Δψ). Rod angular separations must match the setup photo geometry once distances are confirmed.

**What can be claimed:** "With yaw estimated by method X, the mapper produces a map whose revisit shift is Y cells and whose rod lines have residual Z." **What cannot be claimed:** absolute world-coordinate accuracy, or "the mapper is accurate to N pixels on real data". Such claims conflate mapper error with pose, fx, and parallax error.

## 3. Evidence plan per recording

| Evidence | Sept 15 (yaw sweep) | Sept 22 #1 (orbit) | Sept 22 #2 (two-axis) |
|---|---|---|---|
| Stabilized map visual (raw accumulation vs mapped) | Primary demo | Yes | Yes |
| Rod straightness / verticality | If rods visible | **Primary** | Primary |
| Revisit repeatability | If the sweep revisits | If the orbit exceeds the FOV | Yes |
| Feature (rod) azimuth spread vs image position | — | **Measures parallax (D1)** | Yes |
| Moving-object residual (fan) | Yes (qualitative attention map) | — | — |
| Traffic statistics for the hardware (Exp 03) | **Yes** | Yes | Yes |
| Hot-pixel census | Yes | Yes | Yes |

## 4. Known capture constraints usable as weak truth

- Rotation about one axis in a plane (Sept 15).
- Frames at about 1 ms spacing (1000 FPS; playback showed 1291 FPS. **Check the actual timestamps**).
- Rods are vertical (organizer: "you can tell sky from ground").
- Rod distances 47.5 / 48.5 / 50.5 / 55 (units and reference point unconfirmed; the organizer said the numbers needed rechecking).

## 5. Scientific honesty checklist for the report

- [ ] Every real-data figure states its pose source and fx source.
- [ ] Mapper exactness is shown on synthetic data with known pose. Real data shows consistency only.
- [ ] Parallax from the off-axis rig is quantified, or explicitly scoped out.
- [ ] Hot pixels and the moving fan are discussed, not hidden by cropping.
- [ ] The hardware boundary is stated: the `.dvs` decoder and pose estimation are outside it (unless implemented).
