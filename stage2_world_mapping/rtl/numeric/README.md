# Stage 2 V1 numeric RTL

These modules implement the frozen Exp05/Exp05b numerical path. `wm_pkg.sv` is the shared interface package; treat it as frozen after initial integration. Grid storage, node selection, event unpacking, FIFO, merger, banks, and memory are outside this numeric subtree.

## Modules

| Module | Function | Latency / initiation interval |
|---|---|---|
| `wm_lerp` | Combinational scalar nested-difference T32 interpolation with signed RNE ties-to-even after x and y axes; final signed-Q1.15 saturation | 0 registered stages; combinational |
| `wm_isqrt` | Exact unsigned restoring square root, 56-bit radicand to 28-bit floor root | 28 enabled edges / II=1 |
| `wm_cordic_vectoring` | Fixed-point `atan2(y,x)` vectoring with Exp05b BAM32 constants and quadrant handling | 24 enabled edges / II=1 |
| `wm_ray2angle` | Azimuth CORDIC plus integer `sqrt(x²+z²)` and elevation CORDIC, with aligned valid | 52 enabled edges / II=1 |
| `wm_world_quant` | BAM32 floor quantization to wrapped/clamped world cell and row-major address | Combinational |
| `wm_mapper_lane` | Three scalar interpolators followed by ray-to-angle and world quantization | 53 enabled edges / II=1 (includes CE-enabled interpolation-output register) |

The complete production mapper lane latency is **53 enabled edges**. The ray-to-angle subpipeline remains 52 edges; the lane's registered interpolation outputs add one edge. The complete numeric regression and final synthesis were run; see `verification/numeric/results_integration/` and `synthesis/results_round2/`.

Every sequential module has active-high synchronous reset, `valid_in`/`valid_out`, and a global `ce`. When `ce=0`, all pipeline state and valid bits hold. There is no ready/valid backpressure network. An upstream controller must hold inputs while globally stalled.

## Numeric contract

- Grid nodes and interpolated rays are signed 16-bit Q1.15, packed as `{x,y,z}` in `wm_pkg::ray3_t`.
- The lane receives `node00`, `node10`, `node01`, `node11` and unsigned five-bit `x_offset`/`y_offset`. Offsets encode exact numerators of `/32`; node fetch and grid-cell selection are external.
- Each scalar lerp uses 17-bit signed differences, 22-bit signed products, nearest-even magnitude/remainder rounding after each axis, and final signed 16-bit saturation. The `/32` is implemented with shifts and tie handling, not a divider.
- Ray-to-angle scales Q1.15 input codes by `2^12`. The radial integer square-root radicand is `(ray_x²+ray_z²)<<24`. The square root is floor-exact.
- CORDIC state is signed 32-bit x/y and signed BAM32 z. Arithmetic right shifts match Python signed `>>>`; x/y/z updates wrap to 32 bits. Constants and iteration ordering are copied from `codex/model/ray_address.py`.
- World x is `((az+2^31) mod 2^32) >> 24`. World y is `floor((2^30-el)/2^24)` with ±π/2 endpoint clamp. Address is `{world_y,world_x}`.
- The lane consumes already generated pose-specific grid nodes. Euler pose, camera calibration, grid writes, and grid epoch handling are not in the event datapath.

## Verification

From `stage2_world_mapping/` run:

```sh
python3 verification/numeric/run_numeric_tests.py
```

The Python harness reconstructs the Exp05 grid-node inputs from the reference model, converts the checked-in Exp05b address vectors into standalone CORDIC and square-root vectors, and runs self-checking Icarus Verilog testbenches. `--build-dir PATH` retains generated hex files and simulator executables for inspection.

The current checked datasets contain 8,064 interpolation/lane cases and 33,231 Q1.15 ray cases. The harness also checks 66,462 standalone CORDIC inputs and 33,231 square-root inputs. Exact BAM angle and world-address matching is required.

Latest Icarus run passed all 8,064 interpolation vectors (including 16 Exp05 smoke vectors), all 33,231 ray/address vectors (including 45 Exp05b smoke vectors), 66,462 standalone CORDIC inputs, and 33,231 square-root inputs. The lane and ray paths were exercised with periodic global `ce` stalls as well as continuous valid traffic.

## Known limits

- The interpolation is combinational ahead of the pipelined square-root/CORDIC path; no internal ready/valid elastic stages are provided.
- The lane has no pixel-coordinate input and cannot reject `x>=960`/`y>=720`; upstream grid selection must supply valid node addresses and offsets.
- The test vectors establish exact results on the full Exp05/05b checked sets, not a formal proof over all node and ray bit combinations.
- The 100 MHz, two-lane throughput target is architectural. This code has not been synthesized or timed.
