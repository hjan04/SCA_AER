# Stage 2 Round 3 summary

## Decision

**Retain the Round 2 CORDIC E-lite design as the Stage 2 main baseline.** The direct-bin RTL reproduces the Exp05b software candidate exactly on its original 33,231 rays and passes 100 MHz, but misses 24 of the added Golden boundary-neighbor vectors, saves 19.2% cell area (below the ~20% screening target), and raises vectorless power by 22.6%. It is not a strong replacement candidate, so full-system integration and full E-lite synthesis were not attempted.

## Algorithm and RTL

The RTL implements `ray_q15_to_world_address_direct` from `codex/model/ray_address.py`:

- Azimuth: classify `atan2(abs(x),abs(z))` by 31 rounded Q32 tangent thresholds in each octant, count crossed boundaries, then map signs/quadrants to x with the source’s explicit axis/equality rules and horizontal modulo wrap.
- Elevation: form `r2=x²+z²`, `y2=abs(y)²`; compare the smaller/larger squared ratio against 31 rounded Q32 tangent-squared thresholds, then map sign to y and clamp to `[0,127]`.
- Output address is `{world_y,world_x}`. No angle or square root is generated.

Simplifications from the software source are shared magnitude/square terms and bounded-width products: horizontal products fit 48 meaningful bits (the RTL uses a 49-bit container for 17-bit magnitudes); vertical terms fit 63 bits. The 62 predicates are divided across a four-stage CE-enabled pipeline. A population count encodes the monotone threshold prefix, so there is no priority encoder. Latency is 4 enabled edges, II=1. Replacing the current mapper ray path would change metadata latency from 53 to 5 enabled edges; this was documented only and not integrated.

## Verification

- Original Exp05b dataset: 33,231/33,231 exact address matches, x/y mismatch counts 0/0, maximum displacement 0/0.
- Expanded unique set: 44,291 rays total, including all original rays, boundary-neighbor cases at every horizontal/vertical threshold, axes/near-zero directed cases, and 10,000 seeded random rays.
- RTL vs recovered direct-bin software oracle with randomized CE stalls: 44,291/44,291 exact; II=1.
- Expanded direct-bin software vs ideal floating Golden: 44,267/44,291 exact (99.946%), with 24 address mismatches (x=16, y=8; max displacement 1 bin). Expanded direct-bin software vs CORDIC reference: 132 address mismatches (x=104, y=28; max displacement 1 bin). This is a threshold-constant boundary limitation in the recovered algorithm, not an RTL mismatch.

## Standalone PPA

Both standalone tops receive signed Q1.15 x/y/z and produce world x/y/address. They were synthesized with Genus 23.14-s090_1, GPDK045 slow `PVT_0P9V_125C`, 10.0 ns clock, 0.2 ns uncertainty, 1.0 ns input/output delays, 0.10 ns input transition, and 0.001571432 output load. Effort and reports are identical. Vectorless power is preliminary.

| Metric | CORDIC baseline | Direct-bin |
|---|---:|---:|
| Cell area | 132,766.110 | 107,274.114 |
| Net area | 54,486.978 | 48,650.179 |
| Total area | 187,253.088 | 155,924.293 |
| Sequential / combinational instances | 6,810 / 36,088 | 414 / 33,779 |
| WNS / TNS | 0.0 ns / 0 ps | +0.3 ns / 0 ps |
| Violating paths | 0 | 0 |
| Vectorless power | 10.699 mW | 13.115 mW |
| Latency / II | 52 edges / 1 | 4 edges / 1 |

Direct-bin cell area reduction is **19.20%**; total area reduction is **16.73%**. Vectorless power changes by **+22.59%**. Area and power reports are in the two standalone result folders.

## Area and timing diagnosis

Direct-bin has only 414 sequential instances, versus 6,810 for CORDIC+isqrt. Its 33,779 combinational instances occupy 107,274.114 area. The largest mapped family is adder/full-adder logic: 12,303 cells and about 61,980 area (57.8% of direct-bin cell area), primarily the constant-product and compare cones for the parallel thresholds. This is the main area and power bottleneck. The baseline hierarchy attributes about 96,106 cell area to its two CORDICs, 19,680 to isqrt, and 95.8 to world quantization. Logic consumes 98.1% of direct-bin vectorless power; total power is higher despite fewer registers.

The direct-bin critical path is from the registered radial square to the final vertical threshold predicate (`vcmp1[30]`) in the product/compare stage. It meets 10 ns with +0.3 ns WNS and no violating paths. Baseline’s reported worst path is within the elevation CORDIC pipeline and it also meets 10 ns.

## Full-system status and recommendation

Full-system integration was not attempted because strict expanded boundary equivalence failed and the standalone power/area result is not a clear win. Consequently no full-system direct E-lite PPA exists. Round 2 remains the verified Stage 2 baseline: T32 Warp Grid, signed Q1.15 rays, two mapper lanes, 53-edge numeric path, integer sqrt, CORDIC24/BAM32, world quantization, native-word reuse, E-lite merging, and four-bank world memory.

The Round 2 frozen design remains the recommended final Stage 2 architecture. D2 vs E-lite selection was not reopened. No Stage 1 files, Round 1/2 results, or Round 2 RTL were modified. No git commands were used.
