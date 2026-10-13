# Exp05b ray-to-address contract

> This is the historical interface contract. Final evidence supersedes its original traffic-rate and Golden-matching claims: measured Sept. 22 maximum frame-level rate is 110.070 M events/s (162.75 M/s is nominalized), and CORDIC has 124 mismatches on the expanded 44,291-ray Golden set. See `../../evidence/final/FINAL_VERIFICATION.md` and `../../evidence/final/PEAK_FRAME_RTL.md`.

Status: proposed frozen V1 software/RTL interface. This contract covers only the interpolated ray to world address path. Inputs are signed 16-bit Q1.15 ray components. All integer operations below have explicit widths and rounding.

## Selected method

Use two 24-stage, fully pipelined fixed-point CORDIC vectoring blocks per event lane, followed by integer world-bin conversion:

1. `az = atan2(ray_x, ray_z)` using CORDIC vectoring.
2. `r_xz = isqrt(ray_x² + ray_z²)` using an unsigned integer square root.
3. `el = atan2(ray_y, r_xz)` using a second CORDIC vectoring block.
4. Convert the signed BAM32 outputs directly to world bins using the shifts below.

`isqrt(n)` is the exact floor square root. There is no floating-point operation or runtime division in this selected path. The ray is nonzero; a zero ray is invalid and must raise/flag an input error. Every component must be in `[-32768,32767]`.

A compact ratio LUT (257 entries) achieved 91.8329% exact address matches on the test set and requires a ratio/reciprocal front end. The direct-bin threshold candidate matched all tested bins without angles or square root, but its current parallel form has 62 constants/comparisons, including products up to 79 bits. It is retained as an alternative, not selected: CORDIC has a regular staged structure, produces explicit angles consistent with Claude's current interface, and BAM32 / 24 iterations matched all tested bins.

## CORDIC arithmetic

| Signal | Encoding / width | Rule |
|---|---|---|
| ray components | signed Q1.15, 16-bit two's complement | Integer codes are the exact inputs. |
| CORDIC x/y input | signed 32-bit integer | Sign-extend the component, then arithmetic left shift by 12 (`code * 4096`). |
| CORDIC x/y state | signed 32-bit integer | Two's-complement wrap after each x/y update; arithmetic right shift (`>>>`) for each iteration. The selected input range and CORDIC gain stay within range. |
| CORDIC z state | signed 32-bit BAM | Full turn is `2^32`; `+pi` wraps to `-pi`. Wrap after each z update. |
| atan table | 24 signed BAM32 constants | `round_nearest_even(atan(2^-i)/(2*pi) * 2^32)`, `i=0..23`; the exact integer constants are checked into `model/ray_address.py`. |
| iterations | 24 | Fully pipelined; one result per cycle per unit after pipeline fill. |
| CORDIC state rounding | none between stages | Arithmetic shifts truncate toward negative infinity, as signed RTL `>>>`. No final angle rounding beyond the table and finite iterations. |
| horizontal radius | unsigned 56-bit radicand; unsigned 28-bit root | `isqrt((x_code² + z_code²) << 24)`, equivalent to floor of the norm after the common 12-bit guard shift. |

Before vectoring, if `x < 0`, negate x/y and seed z with `+2^31` for original `y > 0`, otherwise `-2^31`; this is the standard half-turn pre-rotation. Handle axes explicitly: `x=0` returns signed quarter-turn according to y; `y=0,x>0` returns zero; `y=0,x<0` returns `-2^31`. The angle accumulator is signed-wrap modulo `2^32` at every update. For azimuth vectoring, CORDIC arguments are `(y,x)=(ray_x,ray_z)`; for elevation, `(y,x)=(ray_y,r_xz)`.

The fixed-point software API is `model.ray_address.ray_q15_to_world_address(x,y,z, iterations=24, angle_bits=32)`. The selected configuration is fixed to 24 and 32 in RTL; parameters are exposed in Python only for the recorded sweeps. It returns debug angle codes and the address fields.

## Native-group interpolation reuse boundary

The ray-to-address function itself is never shared across events. Each event retains its own interpolated Q1.15 `(x,y,z)` ray and independently runs this address function. The upstream fixed-point reference API is `FixedT32Mapper.map_event(x,y)` for an independent event and `FixedT32Mapper.map_native_group(events)` for a same-x, same-`y//8` 1×8 group. The latter computes the two horizontal `top`/`bottom` ray vectors once and performs the vertical interpolation separately for each event; the resulting per-event Q1.15 rays are bit-identical to independent interpolation. The address function is then called per ray.

Claude's RTL cache generalizes the same exact reuse identity to key `(grid_epoch, x, gy)` where `gy=y>>5`: it reuses grid-cell selection/node addresses and six horizontal component lerps (`top` and `bottom`); it does not reuse the vertical lerp, ray-to-angle, quantization, world address, event coordinates, or polarity. Events sharing the key but arriving in separate native subgroups are eligible only while the appropriate cache entry remains valid. Pose/grid epoch change invalidates the corresponding entry. Exp04 software checks recorded zero address mismatches for the sampled shared mapping; the precise RTL cache hit/bubble behavior still requires RTL verification.

## World convention and quantization

The existing floating reference uses `azimuth=atan2(x,z)` wrapped to `[-pi,pi)` and `elevation=atan2(y,hypot(x,z))`. It uses a 256 × 128 equirectangular direction map, with azimuth increasing to the right and elevation increasing upward.

With signed BAM32 codes `az` and `el`, where a full turn is `2^32` codes:

```text
world_x = ((az + 2^31) >>> 24) mod 256
world_y = clamp((2^30 - el) >>> 24, 0, 127)
world_addr = world_y * 256 + world_x
```

The shift is an arithmetic right shift, equivalent to floor division by `2^24`; there is no round-to-nearest at the bin conversion. Horizontal endpoints use half-open bins: azimuth `-pi` maps to x=0, and the limit approaching `+pi` maps to x=255; `+pi` itself wraps to `-pi` and x=0. Vertical elevation `+pi/2` maps to y=0 and `-pi/2` maps to y=127. Values outside the vertical range clamp to those endpoints. Exact interior boundaries enter the bin on their increasing-coordinate side, consistent with the existing `floor` Golden model.

The output widths are `world_x[7:0]`, `world_y[6:0]`, and `world_addr[14:0]`. The address is row-major. For non-power-of-two parameterizations, use the equivalent integer floor formula from angles and explicit modulo/clamp; the BAM shifts above are the V1 256 × 128 specialization.

## Tile, cell, bank, and bank-word address

The frozen world-memory tile is 4 × 4 cells. There are 64 tiles horizontally and 32 vertically.

```text
tile_x = world_x >> 2               # 6 bits, 0..63
tile_y = world_y >> 2               # 5 bits, 0..31
cell_x = world_x[1:0]               # 2 bits
cell_y = world_y[1:0]               # 2 bits
cell_offset = 4*cell_y + cell_x     # 4 bits, row-major 0..15
bank_id = tile_x[1:0] XOR ((-tile_y) mod 4)
bank_word_addr = {tile_y, tile_x[5:2]} # 9 bits, 0..511
```

Equivalent bank bit equations are `bank[0]=tx[0]^ty[0]` and `bank[1]=tx[1]^ty[1]^ty[0]`. `{bank_id,bank_word_addr}` uniquely identifies all 2,048 tiles. Each bank has 512 4×4 tile words.

## Lane/throughput implication

Provide two identical ray-to-address lanes, each with its own two pipelined CORDIC vectoring chains and integer square-root datapath. A 24-cycle CORDIC latency is not a 24-cycle initiation interval: a fully pipelined lane accepts one ray per cycle. Two lanes therefore have a nominal 200 Mevent/s issue capacity at the architectural 100 MHz clock. This is a throughput feasibility estimate, not a timing or synthesis result. Grid-node generation remains outside the per-event path; the active T32 Q1.15 grid is consumed by interpolation, and the ray-to-address stage consumes its interpolated Q1.15 ray.

## Evidence and limits

The original 33,231-ray test set matched the then-current software Golden. Expanded boundary-neighbor testing later found 124 CORDIC mismatches among 44,291 rays, with maximum displacement one bin. The final production choice retains CORDIC for integrated verification and timing closure, not exact matching across every expanded boundary case. See the final verification evidence linked above.
