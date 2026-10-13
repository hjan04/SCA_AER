# Recovered Sept 22 peak-throughput measurement

## Decode and peak selection

Both recovered Sept 22 recordings were processed with the restored Exp03 parser in bounded one-million-word chunks. Decoder hashes and format validation are in [REAL_DATA_PROVENANCE.md](REAL_DATA_PROVENANCE.md); per-frame rows are in `real_data_summary/sept22_frame_stats.csv`.

Two different peaks occur in the 16:42:44 recording:

| Peak definition | Frame | Events | Native words | Recorded frame interval | Frame event rate |
|---|---:|---:|---:|---:|---:|
| Highest event count | 513 | 125,806 | 32,295 | 3,093 us | 40.674 M events/s |
| Highest rate using that frame’s recorded interval | 790 | 85,194 | 20,386 | 774 us | 110.070 M events/s |

The historical **125.8k events/frame** is reproduced by frame 513. The historical **~163 M events/s** is reproduced only as the original Exp03 analyzer’s nominalized figure: 125,806 events scaled by the median 773 us frame period gives 162.75 M/s. It is not the measured rate for frame 513, whose timestamped interval is 3,093 us. With each frame’s own recorded interval, the largest frame-level rate in the two files is 110.070 M/s at frame 790. This distinction follows the original `exp03_analyze.py`, which reports a separate `events_per_sec_per_frame_basis` metric scaled by the median period.

Average traffic over timed frame intervals is 47.404 M/s for 16:42:32 and 55.451 M/s for 16:42:44. These two recordings do not prove a peak over the unavailable Sept 15 recording.

## Peak frame full-speed E-lite RTL

The rate peak is frame 790, the maximum using the frame’s actual measured interval. The larger event-count frame 513 was also replayed at full speed so both peak definitions have a full-frame capacity measurement. Both used the frozen Round 2 E-lite RTL, a synthetic/identity architectural T32 grid (not physical pose ground truth), and source behavior that offered the next native word whenever input ready allowed. These measurements cover traffic, queueing, merging, banking, saturation, and conservation; they do not assess geometric accuracy.

The frame-790 ±1 sequence artifact is `peak_sequence/decoded_three_frames.npz` (SHA-256 `0f1b8335d7b25d6899403f91be3d285a4e98184ab22c219b05311a3c9a101688`). The separate frame-513 event artifact is `peak_frame/decoded_count_peak.npz` (SHA-256 `f0164bb6a67e7e38bd2333d4ff4d595f73fa5f9be3c4d23dd565e58818cbe3b5`). Reconstructed native-word groups, source word indexes, slots, masks, polarities, and readout order are in `peak_sequence/rtl_vectors/native_words.csv` and `peak_frame/recovered_peak_count/native_words.csv`; RTL inputs are encoded in the adjacent `words.hex` files. All final artifact hashes are in [SHA256SUMS.txt](SHA256SUMS.txt).

| Full-speed metric | Frame 790: rate peak | Frame 513: count peak |
|---|---:|---:|
| Events / native words | 85,194 / 20,386 | 125,806 / 32,295 |
| Post-grid drain interval | 47,283 cycles | 70,154 cycles |
| Status counter cycles since init | 47,527 cycles | 70,398 cycles |
| Effective events/cycle | 1.801789 | 1.793283 |
| Effective rate at 100 MHz | 180.179 M events/s | 179.328 M events/s |
| FIFO max occupancy | 128 words | 128 words |
| Mapper CE stall cycles | 172 | 290 |
| Bank conflicts | 7,687 | 12,603 |
| E-lite merges | 20,267 | 30,318 |
| RMW requests / event | 41,102 / 0.482452 | 65,033 / 0.516931 |
| Dropped events | 0 | 0 |
| Saturated contributions | 56,823 / 85,194 = 66.70% | 95,773 / 125,806 = 76.13% |
| Conservation / test result | PASS, zero errors | PASS, zero errors |

The testbench checks all accepted, issued, mapped, and applied event counts and verifies stored cell counts plus saturation loss equal accepted contributions. Logs are `peak_frame/run_logs/recovered_full_depth128.log` and `peak_frame/run_logs/recovered_full_count_depth128.log`.

## Measured-rate single-frame replay and FIFO sweep

There are no trustworthy per-event physical timestamps in the DVS ordering. The arrival schedule is therefore an explicit architectural model: 20,386 native words are uniformly offered across the measured 774 us interval (77,400 cycles at 100 MHz). Words delayed by backpressure remain in the source queue. This is not a claim about sensor microbursts.

Every tested FIFO depth completed with zero overflow, zero dropped events, and a passing conservation check:

| FIFO depth | Peak occupancy | Source words remaining at nominal boundary | Pending contributions at boundary | Drain tail after boundary |
|---:|---:|---:|---:|---:|
| 16 | 7 | 0 | 64 | 63 cycles |
| 32 | 7 | 0 | 64 | 63 cycles |
| 64 | 7 | 0 | 64 | 63 cycles |
| 128 | 7 | 0 | 64 | 63 cycles |
| 256 | 7 | 0 | 64 | 63 cycles |

At the boundary, FIFO occupancy was 1 word; 59 numeric-pipeline events, 1 mapped record contribution, and 2 memory transactions remained. There were 62 internal pending contributions and 64 total including the FIFO word. All source words had been accepted. The measured-rate replay required 77,463 post-grid cycles including its 63-cycle drain tail, and applied all 85,194 events without drops. Depth 16 is the minimum tested depth that works under this uniform arrival model. This does not establish sufficiency for unknown physical burst timing.

Detailed output is in `peak_frame/fifo_depth_sweep.csv`; simulator logs are `peak_frame/run_logs/recovered_paced_depth*.log`.

## Continuous previous / peak / next sequence

Frames 789, 790, and 791 were replayed in original native-word order on one continuously running DUT with the same identity grid and no reset between frames. Their measured intervals were 773, 774, and 773 us. Native words were uniformly offered within each frame interval. The schedule file is `peak_sequence/rtl_vectors/schedule.txt`; source records are preserved in `peak_sequence/rtl_vectors/native_words.csv` and `decoded_three_frames.npz`.

| Boundary after frame | Elapsed modeled cycles | Source words pending | FIFO words | Numeric pipeline events | Mapped-record pending | Memory transactions pending | Total pending contributions |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 789 | 77,300 | 0 | 1 | 63 | 4 | 2 | 70 |
| 790 | 154,700 | 0 | 1 | 59 | 1 | 2 | 64 |
| 791 | 232,000 | 0 | 1 | 65 | 3 | 0 | 71 |

The external source backlog remained zero at every boundary. Pipeline and memory work in flight varied slightly but did not accumulate monotonically. The full 253,145-event sequence drained 64 cycles after the final boundary, with zero drops, zero stalls, and a passing conservation check. The log is `peak_sequence/three_frame_sequence.log`; boundary metrics are also in `peak_sequence/three_frame_boundaries.csv`.

Sequence saturation was 218,120 / 253,145 contributions = 86.16%. Frame 790 saturation was 56,823 / 85,194 = 66.70%; frame 513 saturation was 95,773 / 125,806 = 76.13%. `CNT_W=4` remains a configurable V1 engineering default, not an optimal representation.

## Throughput interpretation

- Numeric mapper theoretical capacity: 2 events/cycle = 200 M events/s at 100 MHz.
- Measured full-speed E-lite RTL on frame 790: 1.801789 events/cycle = 180.179 M/s.
- Offered frame-level traffic at frame 790: 85,194 / 774 us = 110.070 M/s.
- Three-frame modeled arrival sequence: no source backlog accumulation, 64-cycle final drain tail, zero drops.

Safe statement: **At 100 MHz, the E-lite RTL sustained the recovered Sept 22 peak-frame sequence under the measured frame intervals and a uniform-within-frame native-word arrival model without drops.** This does not guarantee real-time operation for all traffic or unknown microburst timing.
