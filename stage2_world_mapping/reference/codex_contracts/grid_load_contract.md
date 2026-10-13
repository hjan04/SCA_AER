# T32 grid-load contract

The per-event interpolator consumes an active table of 31 × 24 = 744 node rays. Each component is signed 16-bit Q1.15 two's complement in `(ray_x, ray_y, ray_z)` order.

| Property | V1 contract |
|---|---|
| Logical node coordinates | `gx=0..30`, `gy=0..23` |
| Node index | `node_idx = gy*31 + gx`, range 0..743, carried in 10 bits |
| Node ordering | gy-major; gx increases fastest |
| Component order | signed Q1.15 `ray_x`, then `ray_y`, then `ray_z` |
| Node payload | 48 bits; component bit patterns concatenated `{ray_x[15:0],ray_y[15:0],ray_z[15:0]}` |
| Image storage | 744 × 48 = 35,712 bits per grid |
| Two-buffer storage | 71,424 bits, excluding valid/epoch/control bits |
| Load sequence | write all 744 nodes to the inactive/next buffer in increasing `node_idx` |
| Commit | swap active/next only after complete image load; commit is atomic so an event never reads mixed grid epochs |

The RTL loader should reject/flag an out-of-range node index, duplicate/missing node in a frame load, or incomplete commit. The software serializer in `model/grid_io.py` emits `(node_idx, x, y, z)` rows and the deterministic `grid_test_image.csv` contains one synthetic test grid generated with yaw +20°, pitch −10°, roll +15° under the frozen convention. That pose is a test stimulus, not competition metadata.

## Pose convention used by the software grid generator

The camera basis is right-handed with x right, y down, z forward; vectors are columns. Rotation is `R = Rz(roll) * Ry(yaw) * Rx(pitch)`. Positive yaw rotates the forward direction toward +x (positive azimuth/right). Positive pitch rotates forward toward −y (up in the image). Positive roll rotates +x toward +y (clockwise in image coordinates). Pose is an externally supplied grid-generation input; the per-event ray-to-address contract consumes only Q1.15 rays.
