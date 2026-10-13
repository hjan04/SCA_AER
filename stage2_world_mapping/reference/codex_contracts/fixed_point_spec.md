# Exp05 fixed-point specification — proposed RTL interface

> Historical pre-integration specification. The later RTL and numeric/system regressions implement the address path; expanded Golden-boundary results are documented in `../../evidence/final/FINAL_VERIFICATION.md`. The design is frozen as implemented, not as a claim of exact matching on every possible input.

## Scope and reference chain

The selected V1 architecture remains Warp-Grid T32. This specification covers the per-event interpolation datapath after a pose-specific grid has been prepared. It does not reopen mapper selection, estimate pose, or claim real-data geometric accuracy. All numeric sweeps use synthetic camera focal lengths and synthetic poses.

The model chain is Model G (floating geometric truth) → Exp02 floating T32 → this integer T32 model → future RTL. The integer model exactly specifies grid-node quantization, signed multiply/shift interpolation, output saturation, and software world-address conversion. **The last atan2 and world-bin quantizer are not yet bit-accurate RTL semantics**; Claude's angle/address implementation must be specified and matched before address-level RTL equivalence can be claimed.

## Camera and address conventions

- Sensor: 960 × 720. Pixel `(0,0)` is the upper-left; valid coordinates are `x=0..959`, `y=0..719`.
- Minimum pixel widths: unsigned 10 bits for each coordinate. Invalid coordinates are rejected at the mapper input and flagged by the caller; they are not clamped into a valid pixel.
- Grid spacing: 32 pixels. `grid_ix=x[9:5]` (valid 0..29), `grid_iy=y[9:5]` (valid 0..22); offsets are `x[4:0]`, `y[4:0]`. Grid dimensions are 31 × 24 nodes, including the upper/right interpolation guard nodes.
- Euler convention used by the offline node generator: column-vector `Rz(roll) * Ry(yaw) * Rx(pitch)`.
- The world map is 256 × 128. Horizontal coordinate wraps; vertical coordinate clamps. Software reference conversion is `az=atan2(ray_x,ray_z)`, `el=atan2(ray_y,hypot(ray_x,ray_z))`, `world_x=floor((az+π)/(2π)*256) mod 256`, `world_y=clamp(floor((π/2-el)/π*128),0,127)`, and `world_addr=world_y*256+world_x`.
- The mapper's interpolated coordinates are a 3D direction vector, not fractional world-map x/y. No metric 3D reconstruction is represented. Memory-cell quantization occurs after direction-to-angle conversion.

## Recommended formats

`Q1.F` means signed two's-complement with one sign/integer bit and `F` fractional bits; range is `[-1, 1-2^-F]`. Node values are rounded to nearest, ties to even, then saturated. A geometric component equal to +1 maps to the maximum positive code.

| Signal | Signed | Total | Integer | Fraction | Valid range / behavior |
|---|---:|---:|---:|---:|---|
| `pixel_x` | no | 10 | 10 | 0 | 0..959; reject ≥960 |
| `pixel_y` | no | 10 | 10 | 0 | 0..719; reject ≥720 |
| `grid_ix` | no | 5 | 5 | 0 | 0..29 |
| `grid_iy` | no | 5 | 5 | 0 | 0..22 |
| `local_x_offset` | no | 5 | 5 | 0 | 0..31; exact fraction is offset/32 |
| `local_y_offset` | no | 5 | 5 | 0 | 0..31; exact fraction is offset/32 |
| `grid_node_x/y/z` | yes | 16 | 1 | 15 | Q1.15, saturating node load |
| `node_delta` | yes | 17 | 2 | 15 | difference of two Q1.15 codes; exact, no saturation |
| `delta × offset` | yes | 22 | 7 | 15 | signed 17-bit delta × unsigned 5-bit offset |
| `rounded_lerp` accumulator | yes | 17 | 2 | 15 | base plus shifted product; retain guard, then saturate to 16-bit node/output range |
| `ray_out_x/y/z` | yes | 16 | 1 | 15 | Q1.15; saturation after vertical stage |
| `world_x` | no | 8 | 8 | 0 | 0..255, modulo wrap |
| `world_y` | no | 7 | 7 | 0 | 0..127, clamp |
| `world_addr` | no | 15 | 15 | 0 | 0..32767 |

The two local fractions do not need division or stored fractional registers. The five-bit offsets are the exact numerators of `/32`. The output ray retains Q1.15; a separate output-fraction sweep is included in `output_fraction_sweep.csv`. Raising output F above 15 only zero-extends a Q1.15 result and cannot restore lost interpolation precision.

## Selected interpolation arithmetic

For each of the three ray components, first interpolate each horizontal edge, then interpolate vertically:

```text
lerp(a,b,o) = sat_Q1.15(a + RNE((b-a)*o / 32))
top          = lerp(v00,v10,local_x_offset)
bottom       = lerp(v01,v11,local_x_offset)
ray_out      = lerp(top,bottom,local_y_offset)
```

`RNE` is signed round-to-nearest, ties-to-even. The signed product is divided by 32 using a right shift plus explicit remainder/tie handling; do not rely on language-specific signed shift behavior. The product is not a general fixed-point multiplication: it is a signed node delta times a 5-bit integer, followed by a 5-bit shift. There are 9 scalar multiplies per event (3 components × 2 horizontal edges plus 3 vertical); no runtime divider is needed. Use a 17-bit signed delta, a 22-bit signed product, and a 17-bit signed add/guard result before the stated Q1.15 saturation.

The nested difference form is selected over weighted four-node summation because it uses bounded differences and keeps the arithmetic easy to size. Each axis is rounded before the next stage; changing to one final rounding or another bilinear form changes bit-exact results and requires a new reference version.

## Rounding and measured effect

At 16-bit Q1.15, round-to-nearest-even has lower error than truncation toward zero in the nominal 800 px, three-axis synthetic sample:

| Mode | Mean error vs Golden | p95 | Max | Mean fixed-stage deviation vs float over identical quantized nodes |
|---|---:|---:|---:|---:|
| Truncate toward zero | 0.004591° | 0.008440° | 0.010067° | 0.001777° |
| Nearest-even | 0.004346° | 0.007256° | 0.008805° | 0.000779° |

Nearest-even is recommended. It adds a small tie/remainder decision to the shift, and reduces the measured interpolation degradation by more than half in this sample. Do not substitute biased `+16; arithmetic_shift` for signed nearest-even.

The sweep's fixed-arithmetic error, isolated against float bilinear interpolation using identical quantized nodes at fx=fy=800, three-axis poses, was:

| Node format | Grid storage | Mean | p95 | Max |
|---|---:|---:|---:|---:|
| Q1.11 (12 bits) | 26,784 bits | 0.012861° | 0.024984° | 0.038259° |
| Q1.13 (14 bits) | 31,248 bits | 0.003110° | 0.006028° | 0.009300° |
| **Q1.15 (16 bits)** | **35,712 bits** | **0.000788°** | **0.001466°** | **0.002214°** |
| Q1.17 (18 bits) | 40,176 bits | 0.000194° | 0.000374° | 0.000535° |
| Q1.19 (20 bits) | 44,640 bits | 0.000051° | 0.000097° | 0.000144° |

Q1.15 is the recommended knee: it adds at most about 0.0023° in the tested same-node comparison and keeps the Exp02 storage estimate unchanged. The complete comparison to both Golden and the existing Exp02 floating T32 reference for all three focal settings and motion suites is in `bitwidth_sweep.csv` and `rounding_comparison.csv`.

## Grid update and storage boundary

The per-event mapper expects one complete 31 × 24 table with three signed Q1.15 components per node. Load/update must be atomic from the event datapath's perspective (double-buffer/swap or frame-boundary hold); partially updated nodes must not be mixed. Grid generation is a separate low-rate block or upstream software process. This specification does **not** prescribe a pose numeric format or claim that pose trigonometry runs per event. The V1 geometry convention and node quantization above define the generated table values; the pose/grid-load protocol and pose word format remain an interface decision.

Storage is `31 * 24 nodes * 3 components/node * 16 bits/component = 35,712 bits` (4,464 bytes, excluding banking/validity/ECC). For native 1×8 reuse, cache/share the two horizontal interpolated vectors (`top`, `bottom`) for events with identical x and y//8 subgroup; each event retains its own vertical interpolation. It does not share final world addresses.

## Native-word and merge semantics

Native reuse is bit-exact under the Exp04 grouping conditions: same pixel column, same native word, same 1×8 y subgroup, and T32-aligned node rows. The test groups produced zero differing Q1.15 component codes from independent mapping. A group violating the same-x/subgroup condition must use independent mapping or be split; it must not reuse a stale horizontal intermediate.

Threshold-2 merging is only within one native group. Exp04 used 4×4 world-cell tiles as a word-locality proxy; this reference models a packed 4×4 word as one word ID plus a per-cell masked payload. If two or more events in one group address the same packed word, emit one write containing independent per-cell deltas; repeated hits to the same cell are summed. Thus two different cells in one word do not alias or lose their separate values. If the storage is instead one world cell per physical SRAM word, that multi-cell merge is unavailable and must be disabled. Separate ON/OFF storage includes polarity in the physical-word key. Unsigned/signed single-plane modes use the world word alone, with event delta interpretation supplied by the accumulator mode. Lane assignment does not affect arithmetic: events from both lanes can be combined only after association with the same native group. Never merge across native groups in this reference. Event count and per-cell signed update sums are preserved; accumulator saturation/overflow remains separately configurable.

## Remaining numerical interface decision

The geometric mapper returns a continuous direction vector. Current Python references use floating `atan2`, `hypot`, floor, horizontal modulo, and vertical clamp to produce an address. RTL must choose an angle-to-address implementation (for example a LUT or another defined approximation), signed angle units, wrap endpoint convention, and exact rounding/bin-edge behavior. Until that contract exists, compare ray codes bit-for-bit and use address outputs as a software oracle only. That is the main blocker to declaring the entire output address bit-accurate.
