# Model2 Integration Review: Where Should Mapping Sit?

Do not assume `Sensor → Model2 → Mapper → World Memory` is optimal. Evaluate it.

## 1. Facts that constrain the coupling

1. The real sensor (Group-AER, S5KRC1S) already does readout, grouping, compression, and per-frame timestamping **on the sensor**. Its output is a frame-tagged, raster-ordered, grouped stream (Q15/Q22, NRV CompactEvent docs).
2. Model2 RTL is a 16×16 pixel-parallel capture plus packetizer. It cannot ingest a 960×720 grouped stream without first expanding it back into pixel-parallel form, and it does not scale to that array (`problem_analysis/stage1_reuse_analysis.md` §2).
3. Model2 packets carry **no timestamp**. Mapping needs the frame time.
4. Model2 pending bits merge repeats and dense mode reorders blocks.

## 2. The questions

**Does Model2 packetization preserve all coordinate information needed?**
Spatially yes. Sparse packets carry exact (x, y). Dense packets carry block address + mask, which reconstructs exact (x, y). Temporally **no**. There is no timestamp, and repeats while pending are merged. For rotation compensation, the missing time is the critical loss.

**Should mapping happen before or after event aggregation?**
*After* the sensor's grouping, and *on* the grouped representation. Ungrouping before mapping throws away the amortization opportunity (E/G1). Mapping before grouping is impossible here because grouping happens on the sensor.

**Could aggregation destroy necessary pixel precision?**
Spatial grouping (bitmaps) does not. Binning (2×2/4×4 → one event) does, by up to half a bin. Whether that matters depends on world cell scale s: with s ≤ 1/2 (world cell ≥ 2 sensor pixels), 2×2 binning error ≤ 0.5 px is ≤ 0.25 cell. **Binning is acceptable only if matched to a coarse world map, and must be measured** (Experiment 04). Temporal aggregation (merging repeats) changes counts, not positions.

**Can mapping operate on grouped events?**
Yes. That is candidate E: one warp interpolation per group anchor, shift-add offsets for the members, and patch-merged memory writes. The linearization error over a 4-pixel span is negligible relative to warp-grid error (both scale with span²; T = 4 vs T = 32).

**Should the traffic-adaptive mode affect mapper precision?**
No (`adaptive_precision.md`). It should affect only the update path, and only via the packet type.

**Could coordinate transformation be moved earlier?**
Partially. The per-frame part (R, warp nodes) is independent of events and can run *ahead* of the frame, even at sensor readout time. The per-event part cannot move into the sensor in our scope. An "earlier" option worth stating: a sensor-side or link-side *block* transform where the link carries world-tile packets instead of pixel packets. This is a research direction only; it couples the sensor to pose.

## 3. Coupling options

| Option | Pipeline | Pros | Cons | Verdict |
|---|---|---|---|---|
| **I1. Serial** | Sensor → Model2 RTL → Mapper → WM | Literal continuity with Stage 1 | Model2 cannot ingest/scale; loses time; re-serializes grouped data | **Reject** |
| **I2. Decoupled** | Sensor stream (decoded x, y, p, frame_t) → Mapper → WM | Simplest; matches V1 | No Stage 1 continuity; per-event memory traffic | **V1** |
| **I3. Group-aware** | Sensor groups (anchor + bitmap, frame_t) → **Model2-style packet interface (sparse/dense)** → Block-amortized mapper → Tiled WM | Reuses Model2's *packet concept and break-even method*; amortizes geometry and memory; direct answer to the Q22 guidance (B14) | Higher RTL complexity; benefit depends on real block occupancy | **Final candidate (if Exp 03 positive)** |
| **I4. Model2 as link** | Sensor groups → Model2-format link (serializer) → Mapper | Shows Stage 1 link efficiency on real data | Only meaningful if a chip boundary between sensor and mapper is part of the story | Optional framing for the report |

**Recommendation:** define the mapper's input interface **in Model2's packet vocabulary**: a sparse packet `{x, y, p}` and a dense packet `{block_x, block_y, valid_mask, pol_mask}`, both extended with a **frame tag**. Then:

- I2 is the special case where every packet is sparse;
- I3 adds the dense path;
- Model2's break-even methodology carries over to choose the block size against the memory tile size.

Stage 1 continuity lives in the *interface and method*, not in instantiating the 16×16 RTL.

## 4. Open dependency

The real Group-AER group geometry: what a "group" is (a row segment of 8? a 2D block?) and how often groups hold ≥ 2 events. The block-path design must match it. If groups are 1D row segments, the dense packet should be `{row, seg, mask[G]}` rather than 4×4. **Resolve this from the `.dvs`/HDF5 data before freezing the interface.**
