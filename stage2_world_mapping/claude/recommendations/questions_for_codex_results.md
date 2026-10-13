# Questions for Codex's Experiment 01 Results

These are review questions, not requests to change Codex's workspace. Answers decide the items in `next_steps.md`.

## Conventions and model definition

1. Which Euler convention, rotation direction (camera→world or world→camera), and image-axis signs does the golden model use? Is it the same as `math_review/pixel_to_world_derivation.md` §0? A mismatch must be resolved in `shared/` before any comparison.
2. What fx (or half-FOV) was assumed, and is it a parameter? Results at a single fx cannot be generalized, because fx is unknown.
3. How is elevation computed in the LUT and linear models? If row and column are treated separably (`el = atan(v)` or `el ∝ v`), the expected corner error is ≈ 20–64 centre-px for θh = 20–40° (sanity). Does Exp 01 show this?
4. Is the equirectangular map's column count a power of two? How is azimuth wrap handled?

## Accuracy results

5. Error distribution vs pixel position (an error map, not only mean/max): where are the worst errors, edges or corners?
6. LUT model: what table size/resolution, and is it per column or per pixel? Storage in bits?
7. Linear model: tangent or chord fit? Edge error vs the sanity prediction (≈ 45 / 16 px at θh = 30°)?
8. What fraction of events map to the *exact* golden address? What is the max error in cells? Is the world cell equal to one centre pixel or coarser?
9. Were fixed-point effects modeled, or is Exp 01 float vs float approximations?

## Synthetic data

10. Which motions were tested (yaw only? speeds?) and was intra-frame time modeled?
11. Does the synthetic generator emit frame-tagged, raster-ordered events like DELTA, or per-event timestamps?
12. Is the scene at infinity (pure rotation) or at finite depth? Can it emulate the Sept 22 off-axis orbit (radius r, depth D)?

## Data/traffic (needed for Exp 03)

13. Has any real `.dvs`/HDF5 been parsed? If so, report events/frame, events/s, the frame-timestamp spacing, whether events within a frame are in raster order, the group structure, and hot-pixel counts.

## Infrastructure

14. Can the golden model be parameterized with node spacing S (LUT+interp, from 1 to 480) and warp tile T, so Exp 02 is a single sweep?
15. Can a bit-accurate fixed-point model be added later behind the same interface, for RTL comparison?
