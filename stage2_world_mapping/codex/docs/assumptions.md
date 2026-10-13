# Experiment 01 assumptions

| Item | Classification | Value / treatment |
|---|---|---|
| Sensor resolution | Competition discussion fact | 960 x 720 |
| Focal length mention | Competition discussion fact, incomplete | 6 mm; not converted to pixels |
| `fx`, `fy` | Synthetic experiment parameters | 800 px each in the reproducible default config; freely configurable and not inferred from 6 mm |
| Principal point | Experiment convention | `(SENSOR_W/2, SENSOR_H/2)` |
| World map | User task definition | Equirectangular direction map, 256 x 128 by default |
| Pose | Experiment assumption | Known yaw; pitch=roll=0; translation=0 |
| Rotation convention | Implementation convention | `R = Rz(roll) * Ry(yaw) * Rx(pitch)`; column-vector camera rays; positive yaw rotates camera +z toward world +x |
| Synthetic feature field | Synthetic parameter | Static world directions listed in `config.json`; never called competition ground truth |
| Pixel sampling | Synthetic implementation | Project continuous position, round to nearest integer pixel, skip features outside the forward image |

No physical sensor width/height, pixel pitch, calibrated focal pixels, precise
competition pose, or precise 3D competition ground truth is asserted.
