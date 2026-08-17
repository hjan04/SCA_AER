# Stage 3 Adaptive AER Analysis

## Regression Results

Actual simulations were run with Icarus Verilog.

```text
BASELINE DIRECTED TESTS: PASS
ADAPTIVE DIRECTED TESTS: PASS
```

Adaptive directed verification covered sparse operation, dense threshold
selection, multiple dense blocks, delayed ACK stability, dense snapshot behavior,
same-cycle dense ACK plus new event on the same pixel, mixed sparse/dense
traffic, polarity masks, and full 4x4 blocks.

## Stage 2 Trace Subset Replayed

The adaptive benchmark replayed existing Stage 2 trace files:

```text
uniform_rate0.10_rate0p100_seed1_ack0.trace
uniform_rate0.30_rate0p300_seed1_ack0.trace
uniform_rate0.80_rate0p800_seed1_ack0.trace
hotspot_4x4_p80_rate0.40_rate0p400_seed1_ack0.trace
burst_burst_rate2.0_dur500_rate0p010_seed1_ack0.trace
locality_region4x4_rate0.20_rate0p200_seed1_ack0.trace
```

The combined adaptive result CSV is:

```text
results/csv/adaptive_stage3_summary.csv
```

This file contains 30 adaptive benchmark rows: six trace cases swept across
thresholds 3, 4, 5, 6, and 8.

## Default Threshold 5 Results

For 16x16 pixels, 4x4 blocks, and `DENSE_ENTER_THRESHOLD = 5`:

| Traffic | Generated | Transmitted | Capture Loss | Sparse Packets | Dense Packets | Avg Dense Occupancy | Logical Bits/Event |
|---|---:|---:|---:|---:|---:|---:|---:|
| uniform 0.10 | 487 | 487 | 0 | 487 | 0 | 0.00 | 10.00 |
| uniform 0.30 | 1484 | 1468 | 16 | 1468 | 0 | 0.00 | 10.00 |
| uniform 0.80 | 4010 | 3495 | 515 | 1261 | 445 | 5.02 | 8.32 |
| hotspot 4x4 p80 rate0.40 | 2030 | 1653 | 377 | 1643 | 2 | 5.00 | 9.98 |
| burst rate2.0 dur500 | 1032 | 868 | 164 | 84 | 145 | 5.41 | 7.15 |
| locality 4x4 rate0.20 | 988 | 961 | 27 | 961 | 0 | 0.00 | 10.00 |

Low-load and near-saturation uniform traces remained sparse, matching the
baseline event semantics. Dense activation occurred in the high uniform and
burst traces where pending block occupancy had time to build.

The hotspot trace produced only two dense packets at threshold 5. Its loss is
mostly repeated same-pixel capture loss inside the hotspot before block
occupancy reaches the dense threshold. This is an important limitation of keeping
the exact same one-event-per-pixel capture storage as the baseline.

## Baseline vs Adaptive Replay Observations

These are logical Stage 3 observations only. The physical output bandwidth is
not normalized yet.

| Traffic | Baseline Tx | Adaptive Tx | Baseline Loss | Adaptive Loss | Baseline Avg Lat | Adaptive Avg Lat |
|---|---:|---:|---:|---:|---:|---:|
| uniform 0.10 | 487 | 487 | 0 | 0 | 2.37 | 2.37 |
| uniform 0.30 | 1468 | 1468 | 16 | 16 | 9.56 | 9.56 |
| uniform 0.80 | 1804 | 3495 | 2206 | 515 | 406.14 | 48.80 |
| hotspot 4x4 p80 rate0.40 | 1647 | 1653 | 383 | 377 | 14.82 | 14.51 |
| burst rate2.0 dur500 | 407 | 868 | 625 | 164 | 366.27 | 26.51 |
| locality 4x4 rate0.20 | 961 | 961 | 27 | 27 | 3.18 | 3.18 |

The high uniform and burst traces show the expected architectural behavior:
dense packets reduce the number of logical handshakes needed to drain pending
events. The low, near-saturation, and moderate locality traces match the
baseline because no dense block forms at threshold 5.

## Threshold Sweep

### Uniform 0.80

| Threshold | Transmitted | Capture Loss | Sparse Packets | Dense Packets | Avg Dense Occ. | Logical Bits/Event |
|---:|---:|---:|---:|---:|---:|---:|
| 3 | 3761 | 249 | 694 | 996 | 3.08 | 11.64 |
| 4 | 3628 | 382 | 1060 | 634 | 4.05 | 9.39 |
| 5 | 3495 | 515 | 1261 | 445 | 5.02 | 8.32 |
| 6 | 3261 | 749 | 1399 | 309 | 6.03 | 7.80 |
| 8 | 3005 | 1005 | 1535 | 183 | 8.03 | 7.36 |

### Hotspot 4x4 p80 Rate 0.40

| Threshold | Transmitted | Capture Loss | Sparse Packets | Dense Packets | Avg Dense Occ. | Logical Bits/Event |
|---:|---:|---:|---:|---:|---:|---:|
| 3 | 1798 | 232 | 1539 | 86 | 3.01 | 10.33 |
| 4 | 1683 | 347 | 1635 | 12 | 4.00 | 9.98 |
| 5 | 1653 | 377 | 1643 | 2 | 5.00 | 9.98 |
| 6 | 1647 | 383 | 1647 | 0 | 0.00 | 10.00 |
| 8 | 1647 | 383 | 1647 | 0 | 0.00 | 10.00 |

### Burst Rate 2.0 Duration 500

| Threshold | Transmitted | Capture Loss | Sparse Packets | Dense Packets | Avg Dense Occ. | Logical Bits/Event |
|---:|---:|---:|---:|---:|---:|---:|
| 3 | 880 | 152 | 47 | 170 | 4.90 | 7.68 |
| 4 | 883 | 149 | 45 | 169 | 4.96 | 7.59 |
| 5 | 868 | 164 | 84 | 145 | 5.41 | 7.15 |
| 6 | 851 | 181 | 114 | 119 | 6.19 | 6.51 |
| 8 | 770 | 262 | 192 | 72 | 8.03 | 5.95 |

### Locality Region 4x4 Rate 0.20

No dense packets were generated at any tested threshold. All thresholds produced:

```text
transmitted_events = 961
capture_loss = 27
sparse_packets = 961
dense_packets = 0
logical_bits_per_delivered_event = 10.00
```

## Threshold Interpretation

Threshold 5 remains the primary Stage 4 candidate because it matches the 4x4
bitmap break-even point from Stage 2:

```text
dense packet bits = 37
baseline sparse bits = 9
break-even = 5 events
```

Measured behavior also supports keeping threshold 5 as the default:

```text
threshold 3: best capture-loss reduction, but below analytical bit break-even
threshold 4: good burst behavior, still below baseline bit break-even
threshold 5: first threshold with clear logical bit/event benefit
threshold 6/8: lower logical bits/event but noticeably worse capture loss
```

For Stage 4, threshold 5 should be the main comparison point. Threshold 4 is
worth retaining as a sensitivity point if capture loss is prioritized over
logical bit efficiency.

## Bottleneck and Architecture Implications

The adaptive path directly targets the Stage 2 bottleneck: one event per
four-phase transaction. In high uniform and burst traces, dense packets carried
multiple events per accepted logical packet and substantially reduced backlog
latency.

The hotspot result shows a different bottleneck: repeated arrivals at already
pending pixels are lost before dense packets can form. Block bitmap service helps
only after multiple unique pixels in the block are pending at the same time. It
does not solve per-pixel overwrite loss, by design.

The current dense-priority policy is simple and effective for the measured burst
case. Under future pathological traffic with continuous dense eligibility,
isolated sparse events could wait longer; Stage 4 should measure tail latency
with physical-link normalization.

## Recommendation for Stage 4

Use the implemented 4x4 block bitmap architecture as the Stage 4 adaptive DUT.

Primary setting:

```text
BLOCK_W = 4
BLOCK_H = 4
DENSE_ENTER_THRESHOLD = 5
```

Also carry threshold 4 as an optional sensitivity run.

Stage 4 must add a common fixed-width physical output link or serializer before
making final throughput and bandwidth claims. The Stage 3 results are logical
packet results, not final equal-link results.
