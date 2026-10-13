# Next Steps

Deadline: Oct 30 (submission + presentation). Today: Oct 6.

## Evidence that must exist BEFORE RTL starts

1. **Shared conventions** in `shared/interfaces/`: frames, Euler order, signs, BAM width, event/pose file contract. *(Team decision. Neither agent should write this alone.)*
2. **Exp 02 result:** chosen per-event method (S/T), word widths, representation, each with measured error ≤ 0.25 cell on synthetic exact-pose data, across the assumed fx range.
3. **Exp 03 result:** real events/s and events/frame, raster-order check, group occupancy histogram. This decides the memory ports/banks and whether the block path (E) is built.
4. **Memory model decision:** map size, cell semantics, ports/latency, and a cited area/power estimation method.
5. **Pose strategy for real data:** which estimation method is used for the demo, and that it stays outside the hardware boundary.
6. **Parallax decision (Exp 04):** model a nominal depth, or scope it out with a quantified statement.

## Proposed sequence

| Window | Work | Owner (suggested) |
|---|---|---|
| Oct 6–8 | Codex Exp 01 review against `questions_for_codex_results.md`; fix shared conventions; parse `.dvs` → HDF5 | Team / Codex |
| Oct 8–11 | Exp 02 (approximation sweep) + Exp 03 (traffic) + Exp 04 (parallax) | Codex (execution), Claude (review) |
| Oct 11–12 | Integration decision: V1 per-event path + node generator variant; E go/no-go | Team in `integration/decisions/` |
| Oct 12–18 | Bit-accurate fixed-point model + V1 RTL (yaw node table, interp, quantizer, addr gen, wm_ctrl with forwarding) + directed tests | — |
| Oct 18–23 | V2 node generator (CORDIC) **or** E block path, not both, unless ahead of schedule. Genus logic PPA. Memory estimate | — |
| Oct 23–27 | Real-data demo maps, metrics, ablations (per-event vs block path on equal traces) | — |
| Oct 27–30 | Report, presentation, buffer | — |

## Decision gates

- **Gate 1 (after Exp 02):** if yaw-only node table + interpolation meets the budget, V1 = D with the yaw node generator. If even this is too costly (unlikely), fall back to C with a column PWL.
- **Gate 2 (after Exp 03):**
  - Build E if median block occupancy ≥ break-even (to be computed per tile size).
  - Otherwise spend the V2 effort on the CORDIC node generator and parallax.
- **Gate 3 (Oct 23):** freeze features. Remaining time goes to evidence and the report.

## Explicitly not recommended for this round

- Per-pixel 2D LUT.
- Per-event pipelined CORDIC as the main path.
- Precision-adaptive mapping.
- Instantiating the 16×16 Model2 RTL as a sensor front-end.
- On-chip pose estimation (unless all of the above is done).
