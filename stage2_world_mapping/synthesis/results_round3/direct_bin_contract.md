# Exp05b direct-bin contract recovered for Round 3

## Source and observable behavior

Recovered verbatim from `codex/model/ray_address.py`: `ray_q15_to_world_address_direct`, `_octant_bin`, `TAN_Q32`, and `TAN2_Q32`. The source vector data is `codex/results/exp05b/rtl_address_vectors.csv` (33,231 rows), which records Exp05b expected BAM32-derived bins and Golden bins. This document does not replace that executable source.

Input is three signed two's-complement 16-bit Q1.15 codes `x,y,z`; zero vector is invalid. Outputs are `world_x[7:0]`, `world_y[6:0]`, and row-major `world_addr[14:0] = {world_y,world_x}`.

## Horizontal classification

Let `a=abs(x)`, `b=abs(z)`. `abs` is a 16-bit unsigned magnitude capable of representing 32768. For a non-axis ray, classify acute angle in its octant. `_octant_bin(a,b)` returns `(theta, exact)` where `theta=floor(atan2(a,b)/(pi/128))`:

- if `a==0`: `(0,true)`; if `b==0`: `(64,true)`; if `a==b`: `(32,true)`.
- Otherwise `lo=min(a,b)`, `hi=max(a,b)`, and `j` is the count of the 31 thresholds for which `(lo << 32) >= hi * TAN_Q32[k]`, `k=0..30`.
- Return `j` if `a<b`; otherwise return `63-j`. The non-special case sets `exact=false`.

`TAN_Q32` is the exact ordered sequence of 31 unsigned 32-bit integers from `ray_address.py`, rounded nearest-even offline from `tan((k+1)*pi/128)*2^32`. The RTL uses the checked-in integer sequence, not runtime trig.

Quadrant-to-x mapping, in source ordering:

- `x>=0,z>=0`: `wx=128+theta`.
- `x>=0,z<0`: `wx=256-(theta if exact else theta+1)`.
- `x<0,z<0`: `wx=theta`.
- `x<0,z>=0`: `wx=128-(theta if exact else theta+1)`.

If `x==0 && z==0`, set `wx=128` (azimuth is vertical). Finally `wx %= 256`. Thus azimuth wraps horizontally; the negative-z axis at `x=0` is x=0 under the nonvertical branch, positive-z axis is x=128.

## Vertical classification

Let `r2=x*x+z*z` and `ya=abs(y)`, exact integer arithmetic. Axes: `ya==0` gives `(alpha,exact)=(0,true)`; `r2==0` gives `(64,true)`. Otherwise set `y2=ya*ya`:

- If `y2 < r2`, `small2=y2`, `large2=r2`, and `alpha` is the count of `k=0..30` for which `(small2 << 32) >= large2*TAN2_Q32[k]`.
- If `y2 > r2`, use `small2=r2`, `large2=y2`; count the same comparisons as `delta`; then `alpha=63-delta`.
- If `y2==r2`, `alpha=32`.
- `exact` is true only when `y2==r2` in this non-axis case.

`TAN2_Q32` is the exact ordered sequence of 31 unsigned 32-bit integers in `ray_address.py`, rounded nearest-even offline from `tan((k+1)*pi/128)^2 * 2^32`. Horizontal products require at most 48 unsigned bits (`lo<=32768`, threshold <2^32); vertical left and right sides require at most 62 unsigned bits (`small2,large2<=2^31`, threshold <2^32). The implementation therefore does not need 79-bit products.

For `y>=0`, `wy=64-alpha` when exact, else `63-alpha`. For `y<0`, `wy=64+alpha`. Clamp to `[0,127]`. This retains the software floor/bin-edge behavior, including its threshold-equality rule (`>=`) and its explicit exact cases.

## Simplifications and limits

The direct classifier avoids BAM32 generation and integer square root. Squared ratios eliminate the vertical square root. Sign handling is performed once, magnitudes and `r2/y2` are shared by all comparisons, and the 31 ordered threshold predicates form a monotonic prefix. The threshold count is therefore a population/count encoding of that prefix; there is no need for a 62-way priority encoder. The proposed RTL splits the 31 comparisons into two registered groups and sums their counts in a later stage, preserving II=1 while avoiding one long unpipelined compare/encode stage.

A balanced binary search would reduce comparison count but introduces a serial threshold-dependent lookup/multiply path, so it is not assumed cheaper. No such unmeasured approximation is used here. Classification compares constants in parallel, with shared input products. All constants, comparison ordering, and special cases are those of the recovered Python source.

Exp05b's 33,231 vectors are empirical evidence, not a proof over all nonzero Q1.15 triples. Boundary tests are required and recorded separately. This contract targets direct-bin software outputs and the exp05b expected/Golden addresses; it does not generate debug angles.
