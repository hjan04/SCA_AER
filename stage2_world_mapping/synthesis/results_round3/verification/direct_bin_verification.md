# Direct-bin verification

## Reference dataset

`codex/results/exp05b/rtl_address_vectors.csv` contains 33,231 Q1.15 rays and expected address fields. The recovered software direct-bin routine matches every `expected_world_addr`: address 33,231/33,231, x 0 mismatches, y 0 mismatches, maximum x/y displacement 0.

## Expanded set and RTL

The extended set contains 44,291 unique rays: all 33,231 Exp05b rays, threshold-neighbor rays generated for every one of the 31 horizontal and 31 vertical thresholds (with sign/quadrant variants), axes/near-zero directed cases, and 10,000 seeded random rays. Xcelium ran the synthesizable RTL against the software direct-bin outputs for every ray, with randomized CE stalls: **44,291/44,291 exact RTL matches**. II=1 was exercised; four enabled pipeline stages were observed.

The software contract itself was also checked against the floating Golden formula on the expanded set. It has **24 Golden bin mismatches** (44,267/44,291 exact, 99.946%): 16 x-only, 8 y-only, maximum displacement 1 bin on either axis. On the same expanded set it differs from the fixed-point CORDIC reference on 132 addresses (104 x, 28 y; maximum displacement 1). All original 33,231 Exp05b rays remain exact against both recorded Expected and Golden fields. The added near-boundary vectors exposed finite Q32 threshold rounding effects in the recovered direct-bin candidate; therefore the candidate does not pass strict expanded-set Golden equivalence.

The additional mismatch cases are boundary-adjacent points where the Q32 rounded tangent thresholds do not exactly reproduce the ideal floating bin edge. No approximation was hidden in the RTL: it is bit-equivalent to the recovered Exp05b direct-bin software routine.

Detailed raw vectors are in `direct_vectors.hex`; testbench and run log are `tb_direct_bin.sv` and `xrun_direct_bin.log`.
