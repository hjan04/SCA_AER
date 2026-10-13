# Experiment 01 summary

This reproducible experiment uses synthetic stationary world directions as ground truth. It is not competition ground truth.

## Setup

- Sensor: 960x720 (competition discussion resolution).
- `fx=fy=800.0` px are chosen synthetic parameters; the mentioned 6 mm focal length was not converted.
- Map: 256x128 equirectangular direction bins.
- Pose is known; yaw varies, pitch/roll/translation are zero. Convention: `Rz(roll) * Ry(yaw) * Rx(pitch)`.
- Main accuracy sweep contains 835 visible synthetic event observations over yaw -40° to +40°.
- Accumulation contains 95 observations of 9 fixed directions over yaw 0° to +40°.

## Accuracy

`metrics.csv` reports mean, median, p95, and maximum great-circle error and mean/maximum wrapped world-bin distance over the full visible synthetic event set.

| Model | Mean angular (deg) | Median (deg) | P95 (deg) | Max (deg) | Mean world pixels | Max world pixels |
|---|---:|---:|---:|---:|---:|---:|
| G | 0.021263 | 0.022637 | 0.035762 | 0.045393 | 0.055090 | 1.000000 |
| L | 0.021263 | 0.022637 | 0.035762 | 0.045393 | 0.055090 | 1.000000 |
| A | 0.778831 | 0.868153 | 1.205923 | 1.260348 | 0.564072 | 1.000000 |

## Accumulation concentration

Concentration is exactly `maximum bin count / total event count`; higher means more counts occupy one bin, but this is only a simple sharpness indicator.

| Accumulator | Concentration |
|---|---:|
| naive | 0.021053 |
| golden | 0.431579 |
| lut | 0.431579 |
| linear | 0.326316 |

## Interpretation limits

Model G is the geometric reference for these configured pinhole assumptions. Model L and Model A implement yaw-only paths. These accuracy measurements do not establish operation under uncertain pose, calibration error, translation, real event noise, or competition recordings.
Complexity figures are source-level conceptual operation estimates, not equivalent silicon area, timing, power, or PPA.
