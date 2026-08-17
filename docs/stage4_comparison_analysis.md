# Stage 4 Physical-Link Comparison Analysis

This document is generated from actual Stage 4 RTL simulation CSV rows.

## Regression and Run Set

- Summary CSV: `results/csv/stage4_summary.csv`
- Comparative simulation rows summarized: 84
- Primary comparison: `LINK_WIDTH = 16`, always-ready link, `DENSE_ENTER_THRESHOLD = 5`.
- Physical latency is measured from input event generation to receiver-side packet reconstruction.

## Wire-Format Costs

- Header: 8 bits, `{payload_length[5:0], packet_type[1:0]}` on the wire LSB-first.
- Baseline sparse payload: 9 bits; 17-bit frame; 32 physical bits on a 16-bit link.
- Adaptive sparse payload: 10 bits; 18-bit frame; 32 physical bits on a 16-bit link.
- Adaptive dense payload: 37 bits; 45-bit frame; 48 physical bits on a 16-bit link.

## Uniform Load Sweep

| Offered | Baseline Thr | Adaptive Thr | Baseline Loss | Adaptive Loss | Baseline Phys Bits/Event | Adaptive Phys Bits/Event | Adaptive Dense Packets |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0.0482 | 0.0482 | 0.0482 | 0.0000 | 0.0000 | 32.00 | 32.00 | 0 |
| 0.0974 | 0.0974 | 0.0974 | 0.0000 | 0.0000 | 32.00 | 32.00 | 0 |
| 0.1976 | 0.1974 | 0.1974 | 0.0000 | 0.0000 | 32.00 | 32.00 | 0 |
| 0.2968 | 0.2963 | 0.2963 | 0.0007 | 0.0007 | 32.00 | 32.00 | 0 |
| 0.4004 | 0.3992 | 0.3992 | 0.0020 | 0.0020 | 32.00 | 32.00 | 0 |
| 0.5944 | 0.4995 | 0.5434 | 0.1413 | 0.0781 | 32.00 | 29.41 | 63 |
| 0.8020 | 0.4997 | 0.6961 | 0.3506 | 0.1214 | 32.00 | 22.97 | 282 |
| 1.0000 | 0.4997 | 0.8676 | 0.4744 | 0.1220 | 32.00 | 18.43 | 527 |
| 2.0000 | 0.4997 | 1.6731 | 0.7308 | 0.1541 | 32.00 | 9.56 | 1515 |

## Saturation Result

- Baseline normalized saturation: 0.4004 events/cycle (highest uniform offered load with loss <= 1% and throughput >= 95% of offered load).
- Adaptive normalized saturation: 0.4004 events/cycle under the same rule.
- Relative saturation change: 0.00%.

## Hotspot and Burst Behavior

| Traffic | Baseline Loss | Adaptive Loss | Baseline Avg Lat | Adaptive Avg Lat | Adaptive Dense Packets |
| --- | --- | --- | --- | --- | --- |
| burst stage4_burst_rate2.0_dur500 | 0.5552 | 0.1434 | 228.42 | 27.90 | 141 |
| burst stage4_burst_rate4.0_dur200 | 0.5769 | 0.2718 | 224.57 | 29.34 | 70 |
| hotspot stage4_4x4_p80_rate0.20 | 0.0020 | 0.0020 | 4.34 | 4.34 | 0 |
| hotspot stage4_4x4_p80_rate0.40 | 0.0286 | 0.0286 | 5.53 | 5.53 | 0 |
| hotspot stage4_4x4_p80_rate0.80 | 0.3719 | 0.3644 | 21.28 | 20.40 | 9 |

## Threshold Sweep

| Threshold | Avg Throughput | Avg Loss | Avg Latency | Avg Phys Bits/Event | Dense Packets | Avg Dense Occ |
| --- | --- | --- | --- | --- | --- | --- |
| 3 | 0.3796 | 0.0595 | 15.31 | 24.00 | 998 | 3.36 |
| 4 | 0.3744 | 0.0616 | 17.31 | 24.17 | 622 | 4.31 |
| 5 | 0.3658 | 0.0746 | 21.13 | 24.54 | 423 | 5.21 |
| 6 | 0.3561 | 0.0932 | 26.23 | 25.10 | 296 | 6.08 |
| 8 | 0.3384 | 0.1250 | 38.29 | 26.08 | 151 | 8.04 |

- Stage 4 threshold recommendation: use 3 as the next primary candidate and keep threshold 5 as the conservative Stage 3 reference.
- This recommendation is based on the diagnostic subset average throughput, loss, latency, physical bits/event, and dense-packet use shown above.

## Link-Width Sensitivity

| Link Width | Architecture | Avg Throughput | Avg Loss | Avg Phys Bits/Event | Dense Packets |
| --- | --- | --- | --- | --- | --- |
| 8 | baseline_link | 0.2339 | 0.2398 | 24.00 | 0 |
| 8 | adaptive_link | 0.2583 | 0.1427 | 19.40 | 140 |
| 16 | baseline_link | 0.2704 | 0.1477 | 32.00 | 0 |
| 16 | adaptive_link | 0.2916 | 0.0448 | 26.80 | 141 |
| 32 | baseline_link | 0.2831 | 0.0938 | 32.00 | 0 |
| 32 | adaptive_link | 0.2961 | 0.0308 | 29.02 | 110 |

## Physical Dense Break-Even

- LINK_WIDTH=8: dense is strictly cheaper at occupancy >= 3.
- LINK_WIDTH=16: dense is strictly cheaper at occupancy >= 2.
- LINK_WIDTH=32: dense is strictly cheaper at occupancy >= 3.

## Sparse-Traffic Penalty

- Sparse uniform low-load physical result: baseline 32.00 bits/event, adaptive 32.00 bits/event.
- Area and power penalty are not measured in Stage 4; that belongs to Stage 5 PPA.

## Cases Where Baseline Was Better

- None under the primary 16-bit always-ready comparison using the configured significance rule.

## Cases Where Adaptive Was Better

- uniform stage4_rate0.60: adaptive thr=0.5434, loss=0.0781; baseline thr=0.4995, loss=0.1413
- uniform stage4_rate0.80: adaptive thr=0.6961, loss=0.1214; baseline thr=0.4997, loss=0.3506
- uniform stage4_rate1.00: adaptive thr=0.8676, loss=0.1220; baseline thr=0.4997, loss=0.4744
- uniform stage4_rate2.00: adaptive thr=1.6731, loss=0.1541; baseline thr=0.4997, loss=0.7308
- poisson stage4_lambda0.80: adaptive thr=0.6997, loss=0.1117; baseline thr=0.4996, loss=0.3452
- hotspot stage4_4x4_p80_rate0.80: adaptive thr=0.5060, loss=0.3644; baseline thr=0.4997, loss=0.3719
- burst stage4_burst_rate2.0_dur500: adaptive thr=0.1768, loss=0.1434; baseline thr=0.0918, loss=0.5552
- burst stage4_burst_rate4.0_dur200: adaptive thr=0.1222, loss=0.2718; baseline thr=0.0710, loss=0.5769

## Stage 4 Questions

- Q1: Under equal 16-bit bandwidth, does adaptive sustain a higher event rate? Tied under the configured saturation rule.
- Q2: Measured saturation change is 0.00%.
- Q3: The locality/hotspot rows identify the density region where dense packets activate; see the tables and dense-occupancy plot.
- Q4: Hotspot/burst loss behavior is shown in the hotspot and burst table.
- Q5: Latency regressions or improvements are shown in the uniform and hotspot/burst tables.
- Q6: Physical bits/event improvements are shown in the uniform, locality, and link-width plots.
- Q7: Sparse penalty is measured above; it is physical-bit neutral for the default 16-bit wire format in low-load sparse traffic.
- Q8: Physical dense break-even is listed above and includes header plus padding.
- Q9: Threshold 5 is functional but the Stage 4 sweep recommends threshold 3 for the next primary candidate.
- Q10: Link-width sensitivity is summarized for 8/16/32-bit links.
- Q11: Stage 5 should synthesize the legacy baseline, normalized baseline wrapper, and adaptive wrapper selected from this table.

## Limitations

- Results are RTL simulation metrics only; no Cadence Genus area, power, or Fmax data is included.
- The physical link is a simple valid/ready model, not a full pad or CDC implementation.
- The adaptive dense snapshot storage is architectural state and must be counted in Stage 5 PPA.
