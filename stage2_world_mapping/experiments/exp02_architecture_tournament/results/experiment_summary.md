# Experiment 02 summary

All accuracy values are synthetic. The focal pixel values are synthetic configurations, not inferred from the discussed 6 mm focal length.

## Vertical-mapping review

Exp01 Models L and A compute elevation using `atan2(Y, hypot(X,1))`, where `X=(u-cx)/fx` and `Y=(v-cy)/fy`. This is the exact local elevation of the full pinhole ray and depends on both x and y; it is not a row-only approximation. Yaw about camera Y preserves this elevation, so the yaw-only path remains geometrically exact vertically. Exp01 included synthetic nonzero elevations, but did not test pitch/roll. Model L's horizontal angle was exact up to LUT quantization; Model A's horizontal angle was approximate.
With pitch/roll, azimuth/elevation cannot be corrected by adding yaw alone. The full ray must be rotated, or an orientation-specific warp approximated. Exp02 marks column-only architectures invalid for pitch/roll.

## Test space

- Sensor/map: 960x720 to 256x128; principal point (480,360).
- Synthetic fx=fy configurations: 600.0, 800.0, 1000.0 px; Euler convention: RzRyRx.
- yaw_only: 9 deterministic structured/random poses, each with 37 corner/edge/interior/random pixel probes.
- yaw_pitch: 23 deterministic structured/random poses, each with 37 corner/edge/interior/random pixel probes.
- three_axis: 35 deterministic structured/random poses, each with 37 corner/edge/interior/random pixel probes.

## Accuracy at nominal fx=fy=800 px

Errors are great-circle degrees against continuous Model G; world-bin distance wraps horizontally. PWL columns separate floating approximation from fixed-coefficient delta. Bin-center error measures final world-map quantization.

| Motion | Candidate | Mean deg | Median deg | P95 deg | Max deg | Mean bins | Max bins |
|---|---|---:|---:|---:|---:|---:|---:|
| yaw_only | Golden | 0.00000 | 0.00000 | 0.00000 | 0.00000 | 0.0000 | 0.00 |
| yaw_only | C0a-Full-Column-LUT | 0.00164 | 0.00153 | 0.00320 | 0.00328 | 0.0030 | 1.00 |
| yaw_only | C0b-2D-Ray-LUT | 0.00067 | 0.00070 | 0.00103 | 0.00105 | 0.0000 | 0.00 |
| yaw_only | Global-Linear-float | 0.58393 | 0.58501 | 1.19004 | 1.19004 | 0.4114 | 1.00 |
| yaw_only | Global-Linear-Q2.16 | 0.55591 | 0.50767 | 1.14600 | 1.14600 | 0.3904 | 1.00 |
| yaw_only | PWL-2-float | 0.13861 | 0.12227 | 0.38866 | 0.39004 | 0.0931 | 1.00 |
| yaw_only | PWL-2-Q2.16 | 0.12662 | 0.07811 | 0.38353 | 0.38454 | 0.0781 | 1.00 |
| yaw_only | PWL-4-float | 0.04093 | 0.03448 | 0.10094 | 0.10149 | 0.0240 | 1.00 |
| yaw_only | PWL-4-Q2.16 | 0.07835 | 0.04912 | 0.17526 | 0.17571 | 0.0601 | 1.00 |
| yaw_only | PWL-8-float | 0.00896 | 0.00484 | 0.02559 | 0.02567 | 0.0030 | 1.00 |
| yaw_only | PWL-8-Q2.16 | 0.06795 | 0.08743 | 0.11372 | 0.11656 | 0.0480 | 1.00 |
| yaw_only | PWL-16-float | 0.00241 | 0.00099 | 0.00623 | 0.00632 | 0.0000 | 0.00 |
| yaw_only | PWL-16-Q2.16 | 0.06186 | 0.07342 | 0.09850 | 0.10113 | 0.0330 | 1.00 |
| yaw_only | Column-LUT-Interp-1px | 0.00164 | 0.00153 | 0.00320 | 0.00328 | 0.0030 | 1.00 |
| yaw_only | Column-LUT-Interp-2px | 0.00152 | 0.00145 | 0.00328 | 0.00331 | 0.0030 | 1.00 |
| yaw_only | Column-LUT-Interp-4px | 0.00116 | 0.00072 | 0.00328 | 0.00331 | 0.0030 | 1.00 |
| yaw_only | Column-LUT-Interp-8px | 0.00134 | 0.00099 | 0.00328 | 0.00331 | 0.0030 | 1.00 |
| yaw_only | Column-LUT-Interp-16px | 0.00139 | 0.00116 | 0.00328 | 0.00331 | 0.0030 | 1.00 |
| yaw_only | Column-LUT-Interp-32px | 0.00343 | 0.00264 | 0.00829 | 0.00834 | 0.0030 | 1.00 |
| yaw_only | Column-LUT-Interp-64px | 0.01279 | 0.01272 | 0.02986 | 0.03027 | 0.0060 | 1.00 |
| yaw_only | Warp-Grid-T8 | 0.00053 | 0.00050 | 0.00100 | 0.00131 | 0.0000 | 0.00 |
| yaw_only | Warp-Grid-T16 | 0.00099 | 0.00085 | 0.00205 | 0.00249 | 0.0000 | 0.00 |
| yaw_only | Warp-Grid-T32 | 0.00398 | 0.00471 | 0.00697 | 0.00771 | 0.0000 | 0.00 |
| yaw_only | Warp-Grid-T64 | 0.01537 | 0.01565 | 0.02926 | 0.02981 | 0.0030 | 1.00 |
| yaw_pitch | Golden | 0.00000 | 0.00000 | 0.00000 | 0.00000 | 0.0000 | 0.00 |
| yaw_pitch | C0b-2D-Ray-LUT | 0.00067 | 0.00070 | 0.00103 | 0.00105 | 0.0000 | 0.00 |
| yaw_pitch | Global-Linear-float | 0.58393 | 0.58501 | 1.19004 | 1.19004 | 0.4425 | 1.41 |
| yaw_pitch | Global-Linear-Q2.16 | 0.55591 | 0.50767 | 1.14600 | 1.14600 | 0.4333 | 1.41 |
| yaw_pitch | PWL-2-float | 0.13861 | 0.12227 | 0.38866 | 0.39004 | 0.1145 | 1.41 |
| yaw_pitch | PWL-2-Q2.16 | 0.12662 | 0.07811 | 0.38353 | 0.38454 | 0.1051 | 1.41 |
| yaw_pitch | PWL-4-float | 0.04093 | 0.03448 | 0.10094 | 0.10149 | 0.0329 | 1.00 |
| yaw_pitch | PWL-4-Q2.16 | 0.07835 | 0.04912 | 0.17526 | 0.17571 | 0.0599 | 1.00 |
| yaw_pitch | PWL-8-float | 0.00896 | 0.00484 | 0.02559 | 0.02567 | 0.0071 | 1.00 |
| yaw_pitch | PWL-8-Q2.16 | 0.06795 | 0.08743 | 0.11372 | 0.11656 | 0.0529 | 1.00 |
| yaw_pitch | PWL-16-float | 0.00241 | 0.00099 | 0.00623 | 0.00632 | 0.0012 | 1.00 |
| yaw_pitch | PWL-16-Q2.16 | 0.06186 | 0.07342 | 0.09850 | 0.10113 | 0.0494 | 1.00 |
| yaw_pitch | Warp-Grid-T8 | 0.00054 | 0.00053 | 0.00097 | 0.00120 | 0.0000 | 0.00 |
| yaw_pitch | Warp-Grid-T16 | 0.00102 | 0.00095 | 0.00195 | 0.00249 | 0.0000 | 0.00 |
| yaw_pitch | Warp-Grid-T32 | 0.00396 | 0.00459 | 0.00710 | 0.00777 | 0.0012 | 1.00 |
| yaw_pitch | Warp-Grid-T64 | 0.01536 | 0.01592 | 0.02927 | 0.03006 | 0.0294 | 1.00 |
| three_axis | Golden | 0.00000 | 0.00000 | 0.00000 | 0.00000 | 0.0000 | 0.00 |
| three_axis | C0b-2D-Ray-LUT | 0.00067 | 0.00070 | 0.00103 | 0.00105 | 0.0000 | 0.00 |
| three_axis | Global-Linear-float | 0.58393 | 0.58501 | 1.19004 | 1.19004 | 0.4564 | 2.00 |
| three_axis | Global-Linear-Q2.16 | 0.55591 | 0.50767 | 1.14600 | 1.14600 | 0.4419 | 2.00 |
| three_axis | PWL-2-float | 0.13861 | 0.12227 | 0.38866 | 0.39004 | 0.1256 | 1.41 |
| three_axis | PWL-2-Q2.16 | 0.12662 | 0.07811 | 0.38353 | 0.38454 | 0.1145 | 1.41 |
| three_axis | PWL-4-float | 0.04093 | 0.03448 | 0.10094 | 0.10149 | 0.0335 | 1.41 |
| three_axis | PWL-4-Q2.16 | 0.07835 | 0.04912 | 0.17526 | 0.17571 | 0.0760 | 1.41 |
| three_axis | PWL-8-float | 0.00896 | 0.00484 | 0.02559 | 0.02567 | 0.0046 | 1.00 |
| three_axis | PWL-8-Q2.16 | 0.06795 | 0.08743 | 0.11372 | 0.11656 | 0.0611 | 1.41 |
| three_axis | PWL-16-float | 0.00241 | 0.00099 | 0.00623 | 0.00632 | 0.0008 | 1.00 |
| three_axis | PWL-16-Q2.16 | 0.06186 | 0.07342 | 0.09850 | 0.10113 | 0.0474 | 1.41 |
| three_axis | Warp-Grid-T8 | 0.00055 | 0.00054 | 0.00098 | 0.00158 | 0.0000 | 0.00 |
| three_axis | Warp-Grid-T16 | 0.00101 | 0.00092 | 0.00196 | 0.00249 | 0.0000 | 0.00 |
| three_axis | Warp-Grid-T32 | 0.00396 | 0.00460 | 0.00712 | 0.00790 | 0.0015 | 1.00 |
| three_axis | Warp-Grid-T64 | 0.01537 | 0.01575 | 0.02925 | 0.03009 | 0.0170 | 1.00 |

## Storage and operation proxies

See `storage_summary.csv` and `runtime_ops_summary.csv`. Storage is calculated as entries times bits per entry. Grid and per-pose matrix/node-generation costs are listed separately from event costs. Unweighted operation tallies are conceptual, not PPA.

## Accumulation

All methods received the same 125 visible observations. Concentration is max bin / total events; normalized Shannon entropy is H/log2(number of bins), with lower values more concentrated.

| Mapper | Concentration | Normalized entropy |
|---|---:|---:|
| Golden | 5.6% | 0.3209 |
| PWL-16-Q2.16 | 4.8% | 0.3421 |
| Global-Linear-Q2.16 | 3.2% | 0.4046 |
| Warp-Grid-T8 | 4.8% | 0.3369 |
| Naive | 0.8% | 0.4644 |

Golden is most concentrated in this small static-field replay; PWL-16 and Grid-T8 are close. The linear mapper and naive image-coordinate accumulation spread counts across more bins.
See `accumulation_metrics.csv` and `accumulation_comparison.png`.

## Recommendation

See `architecture_recommendation.md` for the Pareto interpretation and direct answers on LUT vs PWL, grid value under pitch/roll, and next candidate.
