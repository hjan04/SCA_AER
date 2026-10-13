# Implementation notes

- Model G builds a pinhole camera ray, applies `Rz(roll) Ry(yaw) Rx(pitch)`,
  computes azimuth/elevation using `atan2`, then quantizes to an equirectangular
  map. It supports all three Euler angles; Experiment 01 varies yaw only.
- Model L precomputes one horizontal angle per integer sensor column using
  `atan((x-cx)/fx)`. Per event it reads the table, adds yaw, wraps azimuth, and
  uses geometric vertical elevation. The table build cost is reported
  separately from event costs.
- Model A uses a center slope derived from configured geometry:
  `k = atan((SENSOR_W/2)/fx)/(SENSOR_W/2)`. It approximates horizontal local
  angle by `k*(x-cx)`, then applies yaw and the same vertical geometric mapping.
- L and A assume yaw-only camera rotation (pitch and roll zero). Do not use
  them as general 3-axis mappers without extending and validating them.
- Operation counts include the configured geometric vertical-coordinate path
  used by all three models. Model L's horizontal LUT build cost is reported
  separately from runtime. Counts are source-level conceptual estimates, not gate counts,
  cycle counts, energy, area, or silicon PPA. Pose trigonometry and LUT build
  are outside per-event counts and reported as setup/precomputation.
- Angular error uses spherical great-circle distance. World-pixel error is
  Euclidean map-bin distance with horizontal wrap. Accumulation concentration
  is `max(bin_count)/sum(bin_count)`; it is a simple sharpness indicator, not a
  perceptual metric.
