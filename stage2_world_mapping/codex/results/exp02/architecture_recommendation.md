# Exp02 architecture recommendation

## Answers

**A. Full LUT or PWL/interpolation for V1?** Keep C0a full-column LUT as the yaw-only reference; do not treat it as a general mapper. For yaw-only implementation, compare PWL-16-Q2.16 and 8/16-pixel interpolated LUTs: at fx=800 px they store 576 bits / 976 bits and have mean errors of 0.0619° / 0.0014° respectively. C0b is an accuracy bound, not a compact mapper: at 960x720 it stores 33,177,600 bits (3.96 MiB) as Q1.15 rays.

**B. Does the grid justify pitch/roll complexity?** The grid gives lower measured 3-axis error than PWL-16-Q2.16 (T16: 0.00101° mean, 16.4 KiB; T32: 0.00396°, 4.36 KiB) and removes per-event pose-matrix work. Its 12 ray-component reads and interpolation still cost bandwidth and arithmetic. It is justified when precision and avoiding per-event rotation math matter; the data do not establish that it is worth that cost under a 0.1° target, which PWL-16-Q2.16 already meets.

**C. What goes to fixed-point/RTL next?** Advance Warp-Grid-T32 as the general-pose candidate and PWL-16-Q2.16 as the compact accuracy comparator. For yaw-only, retain the interpolated LUT as a comparator. Defer a final choice until memory bandwidth, pose update rate, and real-data traffic constraints are available.

## Measured nominal bests (fx=fy=800 px)

- Lowest yaw-only mean angular error: Golden, 0.000000° (max 0.000000°).
- Compact yaw-only comparison: Column-LUT-Interp-16px uses 976 bits at 0.001389° mean error; PWL-16-Q2.16 uses 576 bits at 0.061860° mean error. C0b has lower non-reference error (0.000673°) but stores 33,177,600 bits.
- Lowest non-reference 3-axis mean angular error: Warp-Grid-T8, 0.000552° (max 0.001575°).
- Lowest unweighted per-event operation count among candidates whose mean error stays below the 0.25° engineering threshold for all tested focal configs and motion families: C0b-2D-Ray-LUT (worst mean 0.000683°).

The 0.1°, 0.25°, and 0.5° thresholds are engineering screening values, not competition requirements.

## Pareto view

No candidate dominates accuracy, memory, per-event operations, and 3-axis scalability simultaneously. C0b has the lowest unweighted operation proxy among the candidates meeting the 0.25° screening target, but requires 3.96 MiB of per-pixel ray storage. PWL-16-Q2.16 needs 576 coefficient bits and stays below 0.1° mean error, while its general-pose path includes angle reconstruction operations. Warp-Grid-T32 uses 4.36 KiB per pose interval and lowers the 3-axis error substantially, with node generation amortized per pose. Global Linear minimizes coefficient storage but has larger approximation error. These are software operation proxies, not PPA. See the CSVs and scatter plots for all rows.

## Limitations and Claude hypothesis cross-check

Synthetic tests support testing whether a full per-pixel table is avoidable and whether PWL/grid offer useful tradeoffs. This software study does not establish RTL timing, power, or area and does not test a hardware CORDIC. It cannot compare real-data traffic or pose update rate. No Claude numbers are used as ground truth.
