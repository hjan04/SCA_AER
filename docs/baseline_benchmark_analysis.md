# Baseline Benchmark Analysis

This document is generated from actual Stage 2 RTL benchmark CSV results.

## Saturation Rule

Maximum sustainable input rate is defined as the highest uniform offered load with event_loss_rate <= 1% and throughput_full_run >= 95% of offered load.

## Measured Saturation Point

The measured baseline saturation point under the rule is approximately `0.2987` events/cycle.

At the next tested uniform point, approximately `0.40 events/cycle`, the output service rate saturates near `0.333 events/cycle` and event loss rises sharply.

## Uniform Rate Sweep

| Variant | Offered rate | Throughput full run | Event loss rate | Average latency | Output utilization |
|---|---:|---:|---:|---:|---:|
| rate0.01 | 0.0089 | 0.0089 | 0.0000 | 2.04 | 0.0089 |
| rate0.05 | 0.0503 | 0.0502 | 0.0000 | 2.18 | 0.0502 |
| rate0.10 | 0.0997 | 0.0996 | 0.0000 | 2.38 | 0.0996 |
| rate0.20 | 0.2010 | 0.2007 | 0.0010 | 3.52 | 0.2007 |
| rate0.30 | 0.2987 | 0.2951 | 0.0094 | 9.18 | 0.2951 |
| rate0.40 | 0.4045 | 0.3327 | 0.1537 | 116.12 | 0.3327 |
| rate0.60 | 0.6005 | 0.3332 | 0.4074 | 305.69 | 0.3332 |
| rate0.80 | 0.8002 | 0.3332 | 0.5459 | 405.62 | 0.3332 |
| rate1.00 | 1.0000 | 0.3333 | 0.6325 | 468.39 | 0.3333 |
| rate2.00 | 2.0000 | 0.3333 | 0.8117 | 589.80 | 0.3333 |

## Poisson-Like Traffic

| Lambda variant | Offered rate | Throughput full run | Event loss rate | Average latency | Output utilization |
|---|---:|---:|---:|---:|---:|
| lambda0.05 | 0.0503 | 0.0503 | 0.0000 | 2.21 | 0.0503 |
| lambda0.10 | 0.1004 | 0.1003 | 0.0006 | 2.61 | 0.1003 |
| lambda0.20 | 0.2011 | 0.2005 | 0.0030 | 4.10 | 0.2005 |
| lambda0.40 | 0.3930 | 0.3331 | 0.1346 | 105.48 | 0.3331 |
| lambda0.80 | 0.7975 | 0.3332 | 0.5434 | 400.83 | 0.3332 |
| lambda1.20 | 1.1906 | 0.3332 | 0.6900 | 507.84 | 0.3332 |

## Hotspot Traffic

| Hotspot variant | Offered rate | Throughput full run | Event loss rate | Average latency | Output utilization |
|---|---:|---:|---:|---:|---:|
| 4x4_p80_rate0.05 | 0.0507 | 0.0505 | 0.0039 | 2.20 | 0.0505 |
| 4x4_p80_rate0.10 | 0.1013 | 0.1006 | 0.0067 | 2.40 | 0.1006 |
| 4x4_p80_rate0.20 | 0.1955 | 0.1920 | 0.0170 | 3.29 | 0.1920 |
| 4x4_p80_rate0.40 | 0.4077 | 0.3287 | 0.1910 | 14.53 | 0.3287 |
| 4x4_p80_rate0.80 | 0.7993 | 0.3332 | 0.5796 | 46.03 | 0.3332 |

## Representative High-Load Behavior

- uniform: offered `2.0000`, throughput `0.3333`, loss `0.8118`, avg latency `588.61`, output utilization `0.3333`.
- hotspot: offered `0.8030`, throughput `0.3331`, loss `0.5806`, avg latency `46.30`, output utilization `0.3331`.
- burst: offered `0.2064`, throughput `0.0814`, loss `0.6056`, avg latency `366.27`, output utilization `0.0814`.

## Spatial Locality Sweep

| Active region variant | Throughput full run | Event loss rate | Mean capture losses | Average latency |
|---|---:|---:|---:|---:|
| region16x16_rate0.20 | 0.2007 | 0.0010 | 1.0 | 3.52 |
| region8x8_rate0.20 | 0.1998 | 0.0056 | 5.7 | 3.47 |
| region4x4_rate0.20 | 0.1959 | 0.0249 | 25.0 | 3.29 |
| region2x2_rate0.20 | 0.1836 | 0.0862 | 86.7 | 2.78 |

## Burst And Simultaneous Traffic

Burst traffic causes worse loss than its long-window offered rate suggests because the pending bitmap fills during the short high-rate interval.

| Burst variant | Offered rate | Throughput full run | Event loss rate | Average latency | Maximum latency |
|---|---:|---:|---:|---:|---:|
| burst_rate1.0_dur200 | 0.0478 | 0.0400 | 0.1632 | 122.66 | 441 |
| burst_rate2.0_dur200 | 0.0878 | 0.0554 | 0.3690 | 254.28 | 684 |
| burst_rate4.0_dur200 | 0.1678 | 0.0646 | 0.6150 | 328.07 | 839 |
| burst_rate2.0_dur500 | 0.2064 | 0.0814 | 0.6056 | 366.27 | 1100 |

Unique simultaneous-pixel events drain without loss when there are no repeated same-pixel arrivals; latency grows with event count because service is one event per transaction.

| Simultaneous variant | Generated events | Average latency | Maximum latency |
|---|---:|---:|---:|
| count4 | 4 | 6.50 | 11 |
| count8 | 8 | 12.50 | 23 |
| count16 | 16 | 24.50 | 47 |
| count32 | 32 | 48.50 | 95 |
| count64 | 64 | 96.50 | 191 |

## ACK Delay Sensitivity

| ACK delay | throughput full run | average latency | event loss rate | output utilization |
|---:|---:|---:|---:|---:|
| 1 | 0.196489 | 7.44 | 0.003036 | 0.392978 |
| 2 | 0.192697 | 30.99 | 0.017206 | 0.578091 |
| 4 | 0.142779 | 352.59 | 0.202429 | 0.713897 |
| 8 | 0.090895 | 1031.70 | 0.400810 | 0.818056 |

## Identified Bottlenecks

- The dominant high-load limit is the four-phase one-event transaction path. In saturated minimum-delay runs, throughput converges near `0.333 events/cycle`, matching one accepted event about every three cycles in this implementation.
- The one-event-per-transaction representation causes the pending bitmap to stay occupied under high offered load. New events targeting already-pending pixels become capture loss.
- Spatial locality is a separate loss amplifier: small active regions lose more events than full-array uniform traffic at comparable offered load.
- ACK delay directly increases backpressure, latency, and capture loss.
- Arbitration correctness is not the observed failure mechanism in these runs: unique simultaneous events drain without loss, and no undrained events remain in the completed Stage 2 sweep.

## Dense Bitmap Break-Even Analysis

For `16x16`, baseline sparse packets are 9 bits: 4 x bits, 4 y bits, and 1 polarity bit. Dense packet estimate uses 1 type bit, block address, valid mask, and polarity mask.

| Block | Pixels | Dense packet bits | Break-even events | Occupancy |
|---:|---:|---:|---:|---:|
| 2x2 | 4 | 15 | 2 | 0.500 |
| 4x4 | 16 | 37 | 5 | 0.312 |
| 8x8 | 64 | 131 | 15 | 0.234 |

## Stage 3 Recommendation

Use the generated CSV and plots to choose the Stage 3 adaptive architecture. Based on encoding cost alone, 2x2 blocks become bit-efficient at 2 events per block, 4x4 blocks at 5 events, and 8x8 blocks at 15 events. A 4x4 sparse/dense block bitmap path is the best first candidate unless the measured locality data strongly favors another option.
