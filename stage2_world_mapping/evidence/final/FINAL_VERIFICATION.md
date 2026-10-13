# Final Stage 2 verification evidence

## Frozen V1 baseline

The final architecture remains T32 warp grid, signed Q1.15 rays, two mapper lanes, 53 enabled-edge numeric latency, integer square root, CORDIC24/BAM32 ray-to-angle, 256×128 world bins, native-word grid-read reuse, consecutive E-lite merging, and four-bank world memory. No production RTL was modified for this final real-traffic measurement.

Round 2 functional evidence remains: numeric regression pass; 21/21 system tests pass; D2/E-lite memory equivalence; event conservation; random CE stalls; metadata alignment; II=1. Latency is **53 enabled edges**. Older 52-edge wording is stale. Round 2 synthesis was run and the 100 MHz E-lite MODE1 PPA remains the frozen baseline.

## Recovered real-traffic peak tests

The restored Exp03 decoder was verified against the original two-frame Sept22b archive and used on both complete recovered Sept 22 recordings. All 2,063 and 2,054 represented frame IDs are in the compact CSV, including zero-event rows. The highest event count is 125,806 at frame 513; the highest rate using that frame’s recorded interval is 110.070 M events/s at frame 790. The historical ~163 M/s value is a nominalized count divided by the median interval, not frame 513’s measured rate.

Full-speed E-lite replay passed for both peaks: rate-peak frame 790 drained 85,194 events in 47,283 post-grid cycles (180.179 M/s); event-count-peak frame 513 drained 125,806 events in 70,154 cycles (179.328 M/s). Both had zero drops and exact event conservation. Under the explicit uniform-within-frame arrival model, FIFO depths 16/32/64/128/256 all completed without drops; depth 16 is the minimum tested. The continuous frames 789–791 sequence passed with 253,145 events, zero drops, no source backlog at any frame boundary, and a 64-cycle final drain tail. Pending work stayed bounded rather than accumulating. See [PEAK_FRAME_RTL.md](PEAK_FRAME_RTL.md) and `real_data_summary/sept22_frame_stats.csv`.

The frame tests use a synthetic/identity architectural T32 grid. There is no trusted physical pose ground truth; these results establish traffic handling and contribution conservation, not geometric accuracy.

## Power and accuracy caveats

Activity-based power remains unresolved because RTL-to-gate activity annotation did not meet the coverage gate. The only accepted power values are vectorless pre-layout logic estimates: D2 33.3356 mW and E-lite 36.8067 mW. Do not derive energy/event from these values. MODE1 excludes internal power in the 71,424-bit grid and 262,144-bit world memories, and no post-CTS clock tree is modeled.

On the expanded 44,291-ray software set, CORDIC has 124 Golden-bin mismatches and direct-bin has 24; each has maximum displacement one bin. Direct-bin had about 22.6% higher standalone vectorless power and was never integrated. CORDIC remains the final baseline because it is already integrated and verified, meets 100 MHz, and replacing it is not justified; it is not retained on an accuracy-superiority claim.

The existing 40,000-event subset clips 31,348 contributions (78.37%) at the four-bit ON/OFF counter limit. Recovered frame 790 clips 56,823 / 85,194 (66.70%), frame 513 clips 95,773 / 125,806 (76.13%), and the three-frame sequence clips 218,120 / 253,145 (86.16%). `CNT_W=4` remains a configurable V1 engineering default.

## Safe throughput wording

At 100 MHz, the E-lite RTL sustained the recovered Sept 22 peak-frame sequence under the measured frame intervals and a uniform-within-frame native-word arrival model without drops. Do not generalize this to all sensor traffic or unknown physical microbursts. The historical three-recording result cannot be re-established because the Sept 15 raw recording remains unavailable.
