# Competition Report Outline

Principle: tell **one engineering argument**, not the experiment history. Each section answers one question and ends with the decision it supports. Experiment numbers (Exp01…, Round 1…) go into an appendix traceability table, not the main text.

**Current evidence wording:** the measured Sept. 22 maximum frame-level rate is 110.070 M events/s. The often-cited 162.75 M/s is a nominalized rate from 125,806 events divided by the 773 µs median interval, not a measured peak. The peak sequence replay covered frames 789–791 under measured frame intervals and uniform-within-frame native-word arrivals; it does not establish physical microburst timing. See `docs/CLAIMS_AND_EVIDENCE_INDEX.md`.

---

## 1. Problem and requirements (≈1 page)
- Task: event (x, y, polarity) + camera rotation → accumulate into a 256 × 128 equirectangular direction map.
- Traffic claims must follow `evidence/real_data_summary/` and `evidence/final/PEAK_FRAME_RTL.md`; do not label 162.75 M/s as a measured peak.
- Design constraints: a GPDK045 target clock; per-event cost must be independent of pose complexity.
- State up front what the system is **not**: no depth or translation, no pose estimation, and grid generation is external.

## 2. Stage 1 → Stage 2: the principle carried forward (½ page)
- Stage 1 result in two lines: adaptive dense packets amortize one handshake over grouped events, and help only when traffic is grouped. Cite Stage 1 burst and hotspot gains and the tied uniform-load saturation.
- The Stage 2 native sensor word has the same (group, bitmap) structure. Stage 2 applies the amortization to the world-memory RMW.
- Say explicitly that Stage 2 does not instantiate Model2.

## 3. Baseline and why it is insufficient (1 page)
- Per-event geometry options (Exp01): a full LUT is accurate but pose-fixed and large; a linear model is about 0.78° off (more than half a cell).
- Non-merging memory update (D2): measured to fall short of peak traffic at 100 MHz (119 M/s). Present this as the system baseline the final design is compared against.

## 4. Architecture exploration (1–1.5 pages)
- One table: PWL-16 / T64 / T32: error, storage, pose generality. Selection: T32. Be honest that T64 is also sub-cell.
- One table: ray-to-address options: LUT, CORDIC, direct-bin, with accuracy (including the Round 3 boundary result for both), area, slack and maturity. Selection: CORDIC, for the stated reasons.
- One paragraph: lanes. One lane is capped at 100 M/s; 150 MHz does not close; therefore two lanes.

## 5. Real-data characterization (1 page)
- Rates (frame-averaged), the locality histogram, column readout order.
- Clearly marked: measured / inferred (roll) / assumed (intrinsics, poses).
- The finding that drives the design: consecutive events from a native word overwhelmingly land in the same 4 × 4 tile word (about 20 × 20 pixels per cell). That is the opportunity E-lite exploits.

## 6. Proposed architecture (2 pages)
- One block diagram (from `FINAL_ARCHITECTURE.md`).
- Three mechanisms, each with its invariant:
  1. **Warp grid + Q1.15 interpolation**: per-pose table, double-buffered, atomic swap.
  2. **Native-word node-fetch reuse**: exact; 81% fewer grid reads.
  3. **E-lite merge + 4-bank XOR tile memory**: consecutive-only; the final map is provably order-independent because the counter planes are monotone saturating sums. Verified identical to the non-merging baseline.
- Global-CE stall discipline: one enable, no per-lane stalls, metadata aligned by construction.

## 7. Fixed-point implementation (1 page)
- Format table and overflow-bound table (from audit §4).
- Precision sweep: the Q1.15 knee and the RNE effect.
- Accuracy statement: ≈0.004° mean direction error; address bins exact except ≤1-bin edge flips (0.28% of a boundary-stressed set).
- One sentence: precision is generous relative to the cell size, and that leaves an area lever for future work.

## 8. RTL verification (1 page)
- Two-layer method: numeric bit-exactness, then a system scoreboard that compares D2 and E-lite side by side.
- Test-matrix table (21 tests, grouped: datapath, flow control, hazards, frames/grid, saturation/conservation, real traffic).
- A short "what is not verified" paragraph: peak-frame bursts (unless follow-up 2 is done), formal proof, gate-level.

## 9. Synthesis and system results (1.5 pages)
- **Table A, logic PPA:** D2 vs E-lite at 100 MHz; caveat line; E-lite overhead breakdown (bank datapath 61%, metadata 26%, merger 10%).
- **Table B, system performance (RTL × clock):** cycles, stalls, conflicts, RMW/event and sustained events/s. If plotting a demand line, use the measured per-frame values and label the 110.070 M/s maximum; do not use the nominalized 162.75 M/s as a measured peak.
- **Table C, memory:** capacity, ports, access counts per event; per-access cost from a cited model, clearly labelled as an estimate.
- **Power:** activity-based energy per event if follow-up 3 is done; otherwise vectorless numbers in a footnote with an explicit "no energy conclusion".
- Timing: Round 1 → Round 2 single-register fix. The 150 MHz result marks the limit.

## 10. Limitations and future work (½–1 page)
Synthetic poses and pinhole model · frame-averaged rates, unknown bursts · counter saturation on real data · memory arrays not synthesized · pre-layout timing · map-resolution dependence of the merge benefit · direct-bin, CORDIC sizing and arithmetic reuse as next steps.

## Appendix
- **A.** Traceability table: each number in the report → experiment → file → hash.
- **B.** Full numeric contracts (ray-to-address, world memory format, grid load).
- **C.** Synthesis settings and per-block area.

---

## Style rules for the report
- No "we then tried…" chronology in the main text. Present the design choice, then the evidence for it.
- Every number carries its evidence class from `CLAIMS_AND_EVIDENCE.md` the first time it appears.
- Prefer one decisive figure (sustained rate vs demand) over many tables.
- Do not mention the AI agents or the worktree mechanics. The method section describes the *engineering* flow.
