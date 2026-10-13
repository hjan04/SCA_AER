# Stage 1 Reuse Analysis: What Model2 Gives Stage 2 and What It Must Not

Read-only audit. No Stage 1 file was modified.

## 1. What Stage 1 Model2 actually is

Sources: `docs/traffic_adaptive_hybrid_aer_v0.2.md`, `docs/adaptive_aer_spec.md`,
`docs/physical_link_spec.md`, `docs/stage4_comparison_analysis.md`,
`rtl/adaptive/*`, `rtl/common/*`, branch `model2-hysteresis`
(`rtl/adaptive/aer_mode_controller.sv`), and the final report
`1차 보고서/AER_paper_IEEE_format_submission_final.docx`.

| Aspect | Model2 (final report configuration) |
|---|---|
| Array | 16×16 = 256 sources, fully parallel `pixel_event_valid_i[255:0]` |
| Capture | 1 pending bit + 1 polarity bit per pixel (`aer_event_capture.sv`). A repeat event while pending is **merged, i.e. lost**. |
| Packets | Sparse `{type, x[3:0], y[3:0], pol}` = 10 b. Dense `{type, bx[1:0], by[1:0], valid_mask[15:0], pol_mask[15:0]}` = 37 b |
| Grouping | Fixed 4×4 blocks. Combinational popcount over all 16 blocks (`aer_block_occupancy.sv`). |
| Mode control | Hysteresis: enter dense at occupancy ≥ 3, exit when all blocks ≤ 1 for 4 cycles |
| Arbitration | Row/column round-robin (sparse), round-robin over eligible blocks (dense) |
| Transport | 8-bit header + payload, serialized on a 16-bit valid/ready link. Sparse = 2 beats, dense = 3 beats |
| Time | **No timestamp anywhere.** Event time is implicitly the receiver arrival cycle. |
| Clocking | Single synchronous clock. Pre-layout Fmax ≈ 106.4 MHz in GPDK045 slow corner. Area ≈ 22.8 k µm² (10 ns exploratory flow) |
| Measured value | Burst/high-load throughput about 3.3× baseline-link at offered 2.0. Loss at 0.8 load went from 35 % to 6 % |

Provenance warning: the current checkout `stage5-genus-ppa` (and therefore our
`stage2/claude-architecture` branch base) contains the **pre-hysteresis Model1**
mode controller. The report's Model2 lives on `model2-hysteresis`. Any future
reuse of RTL must take it from that branch, deliberately.

## 2. The scale mismatch is structural, not parametric

Model2 was designed for a 16×16 array with one wire per pixel. The Stage 2 sensor is 960×720 = 691,200 pixels.

- Per-pixel pending + polarity flops: 1.38 M flip-flops. That is not credible in a student standard-cell flow.
- The block-occupancy logic is combinational over all blocks. At 43,200 4×4 blocks it is not even a timing question; it is not buildable as written.
- The real sensor (S5KRC1S, Group-AER) **already performs readout and grouping on-chip**. It raster-scans the array once per frame (about 1 ms), emits grouped, compressed coordinates, and attaches one timestamp per frame. The Stage 2 input is therefore already a *packetized stream*, not a pixel-parallel event vector.

**Conclusion: the Model2 RTL cannot sit between this sensor and the mapper as a pixel-capture front-end.** Using it that way would also re-serialize events that the sensor already grouped, which is the opposite of the professor's Q22 guidance (B14) to reduce accumulation work.

## 3. Concepts that genuinely transfer

| Model2 concept | Stage 2 value | How it transfers |
|---|---|---|
| **Sparse address vs. dense block bitmap, chosen by occupancy** | High | A dense 4×4 bitmap shares one block address. In Stage 2 that block can also share **one geometric transform**: compute the world position of the block anchor once, then derive the 16 pixel offsets incrementally. The amortization moves from *link bits* to *arithmetic and memory accesses*. This is exactly B14. |
| **Physical-cost break-even analysis** (dense pays off at ≥ 2–3 events on a 16-bit link) | High (methodology) | The same reasoning decides when a block-level world update is cheaper than per-event updates: memory RMW count, not link beats. |
| **Hysteresis to prevent mode flapping** | Medium | Relevant only if a mode really changes datapath behaviour (e.g., per-event vs per-block memory update). Not needed if both paths run concurrently. |
| **Round-robin fairness, snapshot-then-clear semantics** | Medium | Directly applicable to a world-update combining buffer: snapshot a pending tile, clear only what was written, and never lose a same-cycle new arrival. |
| **Equal-bandwidth fairness discipline** (common serializer, same traces) | High (methodology) | Stage 2 ablations must keep the same event stream, pose stream, error definition, and memory model across variants. |
| **Activity-based power with the same traces** | High (methodology) | Reuse for mapper and memory-controller energy per event. |
| **Genus flow, Fmax sweep scripts, report discipline** (exploratory vs implementation flow) | High | Reuse the scripts as templates. Keep the honesty about "pre-layout, no I/O delay". |

## 4. What must NOT be inherited blindly

1. **Arrival time as event time.** Model2 has no timestamps. Under rotation, a time error Δt becomes an angular error ω·Δt. Mapping must use the **sensor frame timestamp** (plus optional intra-frame row offset), never a downstream arrival cycle. Any buffering between sensor and mapper must carry the frame tag.
2. **Pending-bit repeat merging.** Merging repeats is harmless for an occupancy map but wrong for a count map. The cell semantics in World Memory decide whether this loss matters (`world_memory_architectures.md`). Make the semantics explicit before re-using any capture logic.
3. **Dense-mode reordering.** Model2 drains blocks round-robin. In Stage 2, the raster order of the DELTA readout is a *resource*: it allows streaming line buffers for the per-frame warp grid (`candidate_architectures.md`, candidate D). Reordering would break that and force a full-frame warp-grid store.
4. **Fixed 4×4 grouping as dogma.** Block size should be chosen from (a) the sensor's own group size in Group-AER, (b) world cell scale, and (c) the bounding box of a rotated block in world space (§ banking). It need not be 4×4.
5. **Throughput as the headline metric.** In Stage 1 the bottleneck was the output link. In Stage 2 it is likely **World-Memory read-modify-write bandwidth** (hypothesis; Codex traces must confirm). A transport improvement that leaves memory unchanged would not help.
6. **Area of the pixel-parallel front-end.** Do not include a 16×16 Model2 instance "for continuity" unless it does real work. Judges will ask why it is there.
7. **The idea that adaptivity is automatically good.** Stage 1 adaptivity paid off because the dense packet is strictly cheaper above break-even. In Stage 2, changing *precision* by traffic would change map accuracy with load, which is a liability (`adaptive_precision.md`).

## 5. Reuse verdict

- **Reuse the idea:** occupancy-driven grouping, and amortizing a per-event cost over a block, now applied to geometry and memory.
- **Reuse the methodology:** equal-workload ablations, physical-cost break-even, activity-based PPA, provenance discipline.
- **Do not reuse the RTL as-is** as a front-end for a 960×720 Group-AER sensor.
- **Possible RTL reuse:** `rr_arbiter.sv`, the snapshot/clear pattern, the link serializer (if a link is modeled), and the Genus scripts.

The Stage 2 story can honestly say: *Stage 1 showed that grouping events amortizes transport cost. Stage 2 shows that the same grouping, kept intact through the mapper, also amortizes geometric computation and World-Memory accesses.* Whether that amortization is large is a **hypothesis until Experiment 02/03 measure it** (`verification_plan/experiment_plan.md`).
