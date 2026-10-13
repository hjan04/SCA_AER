# Stage 2 Final Technical Audit

> Historical Exp01–04 audit snapshot. Its early-state missing-evidence notes are preserved as provenance; final recovered measurements and interpretations are documented in the sibling `../FINAL_VERIFICATION.md`, `../PEAK_FRAME_RTL.md`, `../LIMITATIONS.md`, and the repository `docs/CLAIMS_AND_EVIDENCE_INDEX.md`.

Auditor role: independent review of the evidence, done 2026-10-12. No RTL, results or existing documents were changed.

Scope read: `rtl/**`, `verification/**`, `codex/**` (Exp05/05b vectors and models), `reference/codex_contracts/*`, `synthesis/results_round{1,2,3}/**` (all summaries, plus the underlying Genus `report_qor`, `report_power`, `report_area_hier` and `report_timing` files), the Round 2 Xcelium regression log, and the Stage 1 docs and CSVs in `~/SCA_AER/`.

---

## 0. Verdict

**B: GO WITH REQUIRED SMALL FOLLOW-UP.**

The architecture is internally coherent. The RTL is verified bit-exact against the software reference. The logic closes timing at 100 MHz (Genus, slow corner). The central E-lite argument rests on RTL measurement, not only on modeling. Three items remain before the report can be written honestly. None of them needs an RTL redesign.

1. **Fix the evidence and the claims.** This is documentation only: the Round 3 rationale is wrong, Exp01–04 evidence is missing from the snapshot, and several docs are stale.
2. **Run one paced replay of the peak-demand frame** (testbench only). It should report sustained events/cycle, stalls, FIFO peak and drops at the measured peak rate.
3. **Run one activity-based power analysis** (SAIF, D2 vs E-lite, MODE1). The run in item 2 can provide it.

The rest of this section lists the problems the audit found that earlier summaries did not state.

---

## 1. Findings that change how the work must be reported

### F1. The Round 3 accuracy rationale for rejecting direct-bin is inverted (HIGH)

`round3_summary.md` and `direct_bin_verification.md` give this as the first reason to reject direct-bin: it "misses 24 of the added Golden boundary-neighbor vectors."

I re-analysed `synthesis/results_round3/verification/expanded_golden_comparison.csv` (44,291 rays). The **retained CORDIC path misses Golden on 124 vectors** (104 in x, 20 in y, maximum displacement 1 bin). Direct-bin misses 24.

| Set | rays | CORDIC ≠ Golden | Direct-bin ≠ Golden |
|---|---:|---:|---:|
| Original Exp05b | 33,231 | 0 | 0 |
| Round 3 additions (boundary-adjacent + random) | 11,060 | **124** | **24** |
| Total | 44,291 | 124 (0.28%) | 24 (0.054%) |

Consequences:
- On the harder set, direct-bin is the *more* Golden-faithful quantizer. "Strict expanded Golden equivalence" fails for **both** candidates, so it cannot be the reason to choose between them.
- Exp05b's claim "24-iteration CORDIC matched Golden on 33,231/33,231, maximum displacement zero" holds **only for that vector set**. The defensible statement is: angle error about 1e-5° (Exp05b); at most 1 bin of displacement at bin edges (Round 3 expanded set).
- Retaining CORDIC is still defensible (§14), but for other reasons: an unconvincing area saving, a higher vectorless power estimate, no system-level integration or verification, and schedule risk. The report must say this.

### F2. Most real-traffic events are lost to counter saturation (HIGH, semantic)

The Xcelium log of the real Sept22b subset (T09/T20/T21) shows `sat=31348` for 40,000 events. **78.4% of event contributions are clipped** by the 4-bit ON/OFF counters within two partial frames.

The cause is map resolution. With fx = 800, one pixel is about 0.072° and one world cell is 1.406°, so about 20 × 20 pixels fall into each cell. At about 1,300 FPS, a 4-bit counter saturates in a fraction of one frame. There is no decay, and clearing takes 512 cycles.

Consequences:
- The final memory image on real traffic is close to binary. Any "world map" or "reconstruction quality" claim is unsupported.
- On real traffic, final-memory equality (D2 = E-lite = golden) is a weaker check than it looks, because many cells are pinned at 15. The per-event address and metadata checks and the synthetic unsaturated scenarios remain strong evidence.
- This does **not** invalidate the datapath, the RMW counts or the throughput results, which do not depend on saturation. But the output must be described honestly as a *saturating event-occupancy map over a clear interval*, with `CNT_W` and the clear/readout policy left as application parameters.

### F3. The RTL "native-word reuse" saves grid reads only, not arithmetic (MEDIUM)

`DEFERRED_OPTIMIZATIONS.md` #1 and `CODEX_INTERFACE_NOTES.md` state that horizontal-interpolation (top/bottom) reuse is **not implemented**, because `wm_lerp` does not expose those results. The RTL reuses the **node fetch** keyed by grid cell: 32,430 of 40,000 lane node sets were served without a grid read (81%).

All 9 multiplies per event are still computed. The grid store is black-boxed, and no `REUSE_EN = 0` synthesis exists. **The PPA benefit of reuse is therefore unmeasured.** Its proven value is a lower read-port and bandwidth requirement on the grid memory. Report it that way.

### F4. FIFO depth 128 is unvalidated, and its area cost is large (MEDIUM–HIGH)

- In every real-traffic run the testbench offered words back-to-back to a backpressured source (`fifo_max = 128`, `dropped = 0`). The test therefore measures the *saturated drain rate*. It does not show that 128 words absorb real bursts. A real sensor interface may not accept backpressure.
- Exp03 timestamps exist only per frame, so intra-frame burst structure is unknown (`DEFERRED_OPTIMIZATIONS.md` #7).
- The FIFO is built from flip-flops: 72,345 cell area, **14.7% of E-lite logic area**. That is larger than the whole E-lite overhead. Its size is a parameter, not a derived value. The report must not imply it was sized from data.

### F5. The peak-rate margin is thin, and it was measured on a non-peak frame (HIGH)

These are the throughput figures, derived from the RTL cycle counts:

| | events / cycle (whole run) | at 100 MHz | vs 163 M/s observed peak |
|---|---:|---:|---:|
| D2 | 40,000 / 33,566 = 1.192 | 119 M/s | −27% (cannot sustain) |
| E-lite | 40,000 / 22,246 = 1.798 | 180 M/s | **+10%** |
| Issue-limited ceiling (pairing efficiency 0.914) | 40,000 / 21,870 = 1.829 | 183 M/s | +12% |

This is the strongest argument in the project: **at 100 MHz, E-lite is the difference between sustaining and not sustaining the measured peak rate.** It also carries real risk:
- The subset is the first 20,000 events of frames 900 and 901. Those frames average about 70k events, roughly 90 M/s. **The 163 M/s peak frame was never simulated in RTL.**
- The merge rate depends on the trace. RTL shows 0.441 records/event (55.9% reduction). The software replay over 3 recordings × 2 poses shows a 39.5–42.4% reduction. If the peak frame merges at the software rate, E-lite's sustained rate could fall close to 163 M/s.
- The 111 MHz ceiling is a pre-layout extrapolation, so there is no clock headroom to fall back on.

Required follow-up 2 settles this.

### F6. Exp01–Exp04 evidence is not in the audited snapshot (HIGH for the report, zero design risk)

`codex/results/` contains only `exp05/` and `exp05b/`. These numbers could not be checked against raw files here: Exp01 (0.0213° / 0.7788°), Exp02 (PWL-16 0.06186°, T32 0.00396°, T64 0.01537°), Exp03 (1,293.7 FPS, 55/100/163 M/s, locality, column order) and Exp04 (bank and lane modeling).

The only Exp04-derived tables present are the bank re-screen and the consecutive-merge replay in `world_memory_format.md`. I checked that their sums reproduce the 41.37% figure: 7,967,090 → 4,671,282. The remaining source files live in the Codex and Claude worktrees under `/tmp/...` and `/home/hj/...`, which are not on this machine. Before submission, copy the summary CSVs and scripts for Exp01–04 into the snapshot with hashes, so every number in the report has a file behind it.

### F7. Smaller factual errors in existing summaries (LOW, must be fixed)

- `round3_summary.md` says direct-bin WNS is "+0.3 ns". `report_qor.rpt` reports 0.3 **ps**, and `report_timing.rpt` Path 1 is "MET (0 ps)". Direct-bin meets timing with **zero** slack.
- `README.md`, `rtl/numeric/README.md`, `rtl/control/README.md`, `SYNTHESIS_PLAN.md` and `verification/numeric/results_integration/numeric_regression.txt` still say **52** enabled edges. `README.md` says synthesis is "not run yet". The `MANIFEST.md` hashes for `wm_mapper_lane.sv` and `wm_ctrl_pkg.sv` predate Round 2. `rtl_change_manifest.md` holds the current hashes, and I confirmed they match the files on disk.
- `README.md` says the cycle counts "include the 744-cycle initial grid load". T02 (one event) reports `cycles = 316` with `grid_wait = 744`, so the counter's start point is not what the README says. Confirm it before quoting events/cycle to three digits. The conclusions do not change.
- The Genus power reports show **clock = 0 W**: ideal clock, no CTS, about 27k flops. Vectorless totals exclude clock-tree power for both designs.

---

## 2. Decision evidence chain (A–J)

Legend: ✔ supported by evidence in this snapshot · ◐ supported, but the evidence is outside the snapshot or narrower than claimed · ✖ not supported as stated.

| # | Hypothesis | Experiment | Measured result | Decision | Verdict |
|---|---|---|---|---|---|
| A | Per-event geometry needs the true nonlinear projection; a linear model is inadequate | Exp01 (Golden vs LUT vs global linear) | LUT about 0.0213° mean, linear about 0.7788° | Reject linear; keep a Golden-faithful model | ◐ Raw files absent. Linear error is about 55% of one 1.406° cell, so rejecting it is sound |
| B | A compact pose-dependent table beats a separable PWL under 3-axis pose | Exp02 tournament | PWL-16 0.06186° (576 b) vs T32 0.00396° (35,712 b) | Warp grid | ◐ Correct for general pose, because PWL is separable in x/y and cannot express roll coupling. Raw files absent |
| C | T32 is needed over T64 | Exp02 | T32 0.00396° vs T64 0.01537° | T32 | ◐ **Weakest geometric decision.** Both are ≪ 1.406° cells (T64 error ≈ 1.1% of a cell). T32 buys bin-flip margin and headroom for future finer maps or lens distortion, at about 25 kbit/buffer more storage. Logic cost is identical. Present it as headroom, not as a requirement |
| D | One lane at 100 MHz is too slow | Exp03 rates + arithmetic + Round 2 timing | 1 lane = 100 M/s ≤ p95 (about 100 M/s) < 163 M/s peak; 150 MHz fails (−2.35 ns) | 2 lanes, II = 1 | ✔ One lane at 200 MHz is not credible given the 150 MHz result |
| E | E-lite pays for itself | RTL s11 + Genus R2 | −33.7% cycles, −81.1% conflicts, −99.5% stalls; +10.2% cell area | E-lite | ✔ for throughput. ✖ for energy (no activity power yet). See F5 for trace scope |
| F | Native-word reuse is exact and cuts work | Exp05 `map_native_group` + RTL T21 | Bit-exact; 81% node-set reads avoided; same addresses with reuse on and off | Keep node-fetch reuse | ◐ Exactness proven. Work reduction is grid reads only; arithmetic reuse was deferred (F3) |
| G | 4 banks with an XOR hash suffice for 2 lanes | Exp05b bank re-screen; RTL conflicts and stalls | XOR_NEG ≈ XOR_PLAIN ≫ tile_x mod 4; E-lite only 56 stall cycles | 4 banks, XOR_NEG | ◐ The hash choice is supported, and XOR_NEG is honestly called a tie. **No 2- vs 4- vs 8-bank sweep is in the snapshot.** Four banks is plausible (≥ 2× lanes), but it is not shown to be optimal |
| H | Q1.15 is the precision knee | Exp05 bit-width + rounding sweep | Q1.15 adds ≤ 0.0022° max; RNE halves the fixed-point deviation | Q1.15, RNE | ✔ as a *knee*. Q1.13 (+0.0031° mean) would also be ≪ 1 cell, so Q1.15 is conservative, not minimal |
| I | CORDIC is preferable to direct-bin | Exp05b + Round 3 | CORDIC: regular, explicit angles. Direct-bin: −19.2% cell area, +22.6% vectorless power, 0-ps slack | Retain CORDIC | ◐ The decision is acceptable. **The stated accuracy reason is wrong (F1)** |
| J | The lerp→isqrt path limits Fmax; one register fixes it | Round 1 timing → Round 2 | −2.14 ns → 0 ns WNS at 100 MHz; +100/+120 flops; latency 52 → 53; system cycles +1 | 53 edges | ✔ A clean single-variable experiment. All 21 system tests and the full numeric regression were re-run |

---

## 3. Experiment-by-experiment notes

### Exp01
- **Proved** that an ideal pinhole-plus-rotation projection cannot be replaced by a global linear angle model without about 0.78° mean error (more than half a cell). A full LUT reproduces Golden to quantization level.
- **Did not prove** anything about hardware cost, about real lenses (every model in `candidate_models.py` is an *undistorted pinhole*, `atan(dx/fx)`), or about real-pose accuracy.
- **Role:** motivation and baseline only. One paragraph, as the "why not trivial" argument. Do not present it as a hardware result.

### Exp02
- T32 remains justified for **general 3-axis pose**. The argument against PWL is structural (it cannot represent roll coupling), not just a ranking.
- Framing to avoid: "T32 is required for accuracy." At a 256 × 128 map, T64 would also give sub-cell error. Say instead that T32 was chosen for bin-boundary margin and headroom at modest storage (35.7 kbit/buffer, about 10% of total on-chip storage).
- Lens distortion was not modeled. A warp grid would absorb it naturally, while PWL would not. This is a reasonable *qualitative* argument, but it is untested.

### Exp03 (real event data)

| Statement | Status |
|---|---|
| About 1,293.7 FPS frame rate in the recordings | **Measured** (per-frame timestamps) |
| 55 M/s average, about 100 M/s p95, about 163 M/s peak | **Measured, frame-averaged.** Intra-frame instantaneous rates are unknown |
| Strong native-word and block spatial locality | **Measured** (also confirmed by RTL merge and reuse rates) |
| Column-based readout order | **Measured** from word and stream order. The sensor's internal timing is unknown |
| Polarity semantics | Unknown. `pol = 1 → ON` is a convention |
| Sept 22 imagery shows significant roll | **Inference** from visual appearance. No IMU or pose data. POSE-ROLL in Exp04/05b is a *synthetic* stress pose |
| Camera intrinsics (fx = fy = 800) | **Assumption** in all numeric and RTL tests |

### Exp04 (system feasibility)
- **Two lanes:** supported (D).
- **Native-word reuse:** exactness supported. The magnitude of the benefit depends on implementation (F3).
- **Four banks:** hash supported; bank count not swept in the available evidence (G).
- **E-lite:** the consecutive-only semantics were modeled exactly and then confirmed in RTL. The record counts match the Python reference in all 21 tests.
- **FIFO 128:** **unresolved.** Earlier modeling assumed uniformly distributed word arrivals within a frame. The RTL test used a backpressured, saturated source. Neither tests burst absorption. Risk remains open (F4).

---

## 4. Fixed-point review (Exp05/05b)

I re-checked the overflow bounds analytically from the contract widths.

| Stage | Worst case | Container | Safe |
|---|---|---|---|
| node delta | 32767 − (−32768) = 65,535 | 17-bit signed | ✔ |
| delta × offset | 65,535 × 31 = 2,031,585 < 2^21 | 22-bit signed | ✔ |
| lerp result | saturates to Q1.15 after the guard bit | 17 → 16 | ✔ (saturation is explicit) |
| CORDIC input | 32,768 × 2^12 = 2^27 | 32-bit | ✔ |
| CORDIC growth (azimuth) | √2 · 2^27 · 1.647 ≈ 3.1e8 < 2^31 | 32-bit | ✔ |
| CORDIC growth (elevation) | √3 · 2^27 · 1.647 ≈ 3.8e8 < 2^31 | 32-bit | ✔ |
| isqrt radicand | (2^30 + 2^30) << 24 = 2^55 | 56-bit | ✔ |
| isqrt root | ≤ 2^27.5 | 28-bit | ✔ |

- **Boundary semantics:** fully specified. Half-open horizontal bins with wrap; vertical clamp; arithmetic-shift floor; explicit axis handling. Pixel range: 960 = 30 × 32 (guard column 30); 720 = 22.5 × 32, so the last cell row is half used and guard row 23 exists. Coherent.
- **Zero ray:** caught by a `$fatal` simulation guard only. Synthesized hardware has no flag. It cannot occur with a sane unit-vector grid. LOW.
- **Sufficiency:** the evidence is enough for a competition. Precision is **generous** relative to the 1.406° map cell: total pipeline error is about 0.004°, about 1/300 of a cell. Q1.15, BAM32 and **24 CORDIC iterations were chosen for Golden bit-matching, not for minimum area.** F1 shows that 24 iterations still flip bins at edges, so a "match Golden exactly" target was never fully achievable. A width and iteration sweep against bin-flip rate is a legitimate *future* area lever: CORDIC is 38.6% of logic area. Do not frame the precision as minimal.

---

## 5. RTL verification review

**Strengths**
- Two independent layers: numeric (bit-exact vs the Codex fixed-point model, 8,064 + 33,231 + 66,462 + 33,231 vectors) and system (21 tests).
- Every system test runs **both** D2 and E-lite and checks: per-event address and metadata in order, exact counters (including the issue-cycle formula and the merge-record count vs the Python reference), final memory vs golden, D2 = E-lite, and event conservation including saturation loss.
- Stress coverage: random and periodic CE stalls, bank holds, RD_LAT 1 and 3, FIFO depth 8, partial-grid refusal, 5-frame swap, invalid coordinates, clear.
- Round 2 re-ran everything after the latency change. Numeric valid alignment was checked every cycle against a CE-frozen reference.

**Blind spots**
1. The real traffic is a 40k-event **prefix** of two non-peak frames, with synthetic poses (yaw 5k, roll 3k) and a backpressured source. Peak-frame and burst behaviour are untested (F4, F5).
2. Real-traffic memory comparisons are diluted by 78% saturation (F2).
3. The vector sets are not exhaustive. Round 3 showed that boundary-adjacent rays expose ≤ 1-bin flips that Exp05b's set did not contain (F1). This affects the *accuracy claim*, not RTL correctness: RTL = model.
4. No gate-level simulation of the Genus netlist. Conformal LEC maps (`fv/`) were generated but no LEC result is in the snapshot. Run LEC or cite it if done. It is cheap, but it is not one of the three required items because Genus flows from verified RTL.
5. Grid-load timing against frame rate: the STRICT policy is functionally tested, but not under realistic pose-update latency.
6. Reset in mid-stream and clear during traffic: clear is tested at idle (T17).

**Verdict:** sufficient for competition evidence. The single most valuable additional test is the **paced peak-frame replay** (required follow-up 2). Formal verification is **not** needed.

---

## 6. Synthesis review (Rounds 1–2)

The numbers in the summaries match the underlying `report_qor.rpt` and `report_power.rpt` exactly. I checked every headline figure. Interpretation notes:

- **Scope:** MODE1 = logic only. The grid store (71,424 b) and world memory (262,144 b) are black boxes with 0 W. The input FIFO (6,656 b) **is** included, as flops, adding about 15% of the area. The status counters (9,791 cell area, 2.0%) are verification logic and are also included. Report "logic PPA excluding grid/world memory arrays; includes the flop-based input FIFO and about 2% verification counters."
- **Corner and flow:** gsclib045 slow, `PVT_0P9V_125C`, interconnect mode "global" (wireload-like), no placement, no CTS. The timing is a pre-layout estimate.
- **Units:** Genus area units from the library (µm² for gsclib045). State the unit once and use cell area as the primary metric. Net area is a wireload estimate.
- **What the E-lite overhead consists of** (Round 2, cell area, from `report_area_hier.rpt`):

| Block | D2 | E-lite | Δ | share of Δ |
|---|---:|---:|---:|---:|
| 4 bank controllers (multi-cell delta datapath) | 21,925 | 49,822 | +27,898 | 61% |
| 2 metadata pipes (group/frame tag kept for merging) | 1,168 | 13,067 | +11,899 | 26% |
| merger | 1,401 | 6,116 | +4,715 | 10% |
| everything else | — | — | +1,114 | 3% |
| **top** | 447,465 | 493,231 | **+45,766 (+10.23%)** | |

  The merge logic itself is only about 1% of the design. The cost is in the **wider RMW datapath** (16 cells × multi-bit deltas) and in **carrying merge keys through 53 stages**. Say this in the report: it explains *why* the overhead is about 10% and where a future optimization would act.
- **Round 1 → Round 2 area went down** although registers were added. Meeting timing let Genus downsize cells. Treat it as a flow result. Do not present it as an area benefit of pipelining.
- **150 MHz:** fails by −2.353 ns, and area grows 19.6%. The "about 111 MHz ceiling" is an extrapolation from one over-constrained run. Call it an *indicative pre-layout ceiling*.
- **Post-layout risk not visible here:** `mapper_ce` is one global enable for about 27k flops. It is a large-fanout net that the global interconnect model does not stress. If the design ever goes to place-and-route, expect it to need buffering or replication.

---

## 7. Round 3 (direct-bin) review

- The comparison is fair on its stated terms: same flow, constraints and reports.
- It **under-states** direct-bin's system-level saving. Direct-bin latency is 4–5 edges against 52–53, so in E-lite the two 53-stage metadata pipes (13,067 cell area) would shrink to about 1/10. A projected in-system saving is about 2 × 25,492 + about 11,800 ≈ 63k cell area, roughly **−13% of E-lite logic**. *This is an unmeasured projection.*
- Direct-bin meets 100 MHz with **0 ps** slack (F7), so its margin is worse than CORDIC's.
- Direct-bin's vectorless power (+22.6%) comes from a large, mostly combinational compare cone (98% logic power, 414 flops). Vectorless glitch and activity assumptions treat such a cone unfavourably, and the real ranking could differ under activity-based power. The power figure is weak evidence either way.
- **Verdict on RETAIN CORDIC:** justified *for this submission*. CORDIC is verified at system level, has positive slack, keeps the debug angles, and direct-bin's saving is modest. **The accuracy argument must be removed or reversed.** Direct-bin is the strongest documented area-reduction path for future work. Its accuracy is better on boundary rays, its latency is 10× lower, and it projects about −13% logic area.

---

## 8. Timing target and throughput (§15–16 of the brief)

- 100 MHz is the **right** target. It closes with positive margin in the slow corner, and the ceiling (about 111 MHz pre-layout) is too close to justify claiming more.
- Do **not** compute throughput as 2 × 100 MHz. Use the RTL-measured rates in F5 and state their scope. Safe hierarchy of statements:
  - **A. Architectural:** 2 events/cycle maximum acceptance (2 lanes × II = 1; II = 1 verified in numeric and system TBs).
  - **B. Nominal capacity at 100 MHz:** 200 M events/s for the mapper (Genus pre-layout closure, slow corner).
  - **C. Measured system rate:** on a 40k-event real Sept22b subset (2 frame prefixes, synthetic poses, 1R1W behavioural memory, RD_LAT = 1, saturated input), E-lite sustains 1.80 events/cycle (about 180 M/s at 100 MHz) and D2 sustains 1.19 (about 119 M/s). Word-local pairing efficiency of 0.914 caps the rate at 1.83 events/cycle.
  - **D. Input demand:** about 55 M/s average, about 100 M/s p95, about 163 M/s peak, as **frame-averaged** rates over the recordings.
  - **Safe conclusion:** "At 100 MHz, E-lite's measured sustained rate on real traffic exceeds the observed frame-averaged peak by about 10%; D2's does not." Add "on the peak frame" only after follow-up 2.

---

## 9. Memory caveat (§13)

This is serious for a *total-chip* claim and acceptable for a *logic-architecture* claim, provided it is presented explicitly. Total on-chip storage is 333,568 b (40.7 KiB) of arrays + 6,656 b FIFO. Logic area alone cannot show this.

Present three separate tables:
- **A. Logic PPA (synthesized):** the Round 2 MODE1 numbers, with the caveats in §6.
- **B. Memory capacity and port requirements (architectural, exact):**
  - World: 4 banks × 512 × 128 b = 262,144 b; per bank one read + one write per cycle (RMW, RD_LAT parameter verified at 1 and 3).
  - Grid: 2 buffers × 744 × 48 b = 71,424 b. The logical requirement is **8 node reads/cycle peak: 4 parity sub-banks × 2 read ports + 1 write**. The behavioural array pads to 98,304 b. This port requirement is not trivial; a real implementation needs 2R1W sub-banks or 2× replication (about 143 kb).
  - Input FIFO: 128 × 52 b, currently flops.
- **C. Memory access counts (RTL-measured) and an estimated cost (cited model):**
  - World RMW per event: D2 1.000, E-lite 0.441 (s11). Grid node-set reads per event: 0.19 with reuse, 1.0 without.
  - Energy and area per access must come from a **named** source (for example a CACTI run for 45 nm, or a published 45 nm SRAM datasheet), shown as a formula with the source cited. Label it "estimate, not synthesized".
  - Never add the estimate into the synthesized totals without a visible separator.

---

## 10. Stage 1 → Stage 2 continuity

**The continuity is defensible, and stronger than the brief suggests,** provided it is stated as a principle rather than as reuse of Model2.

- Stage 1 Model2's dense packet is *(group id + bitmap)*. Stage 2's native sensor word is *(column x, group, 8-bit mask)*: the same structure, now coming from the sensor.
- Stage 1 amortizes **one link handshake** over the events in a dense group, only when occupancy makes it cheaper (break-even occupancy 2–3), and falls back to per-event packets otherwise.
- Stage 2 E-lite amortizes **one world-memory RMW** over consecutive events in a native group that land in the same tile word, and degrades to one RMW per event when there is no locality.
- The honest differences: E-lite has **no mode controller, threshold or hysteresis**. Its "adaptivity" is implicit (merge-if-compatible), at record granularity. Stage 1 measured activity-based power; Stage 2 has not yet.
- Stage 1's own result pattern carries over too: no gain under uniform traffic (saturation tied at 0.00%), large gains under bursty or local traffic. Stage 2's gain is likewise **locality-dependent**. It also depends on map resolution: about 20 × 20 pixels per cell makes same-word hits very likely. Saying this openly makes the continuity story more credible, not less.

Suggested framing: *"Stage 1 showed that a hardware event interface wins when it amortizes per-transaction cost over spatially grouped events, but only when the traffic actually contains them. Stage 2 applies the same principle one level deeper: to the world-memory update that a mapping accelerator must perform for each event."*

---

## 11. Contributions (evidence-based ranking)

No literature comparison was made, so nothing below is claimed as novel in the literature.

| Rank | Contribution | Type | Evidence strength |
|---|---|---|---|
| 1 | **Locality-aware world-memory update (E-lite + tile-word banking)**: about 10% logic area turns an architecture that cannot sustain the observed peak at 100 MHz into one that can (on the tested subset) | Competition + engineering | RTL-measured + Genus; needs follow-up 2 for peak-frame confirmation |
| 2 | **Complete, verified event-to-world-map hardware pipeline**: native word in, accumulated map out, II = 1, two lanes, bit-exact to a golden model, timing-closed | Engineering | Strongest raw evidence (numeric + 21 system tests + synthesis) |
| 3 | **Amortized pose-dependent warp grid (T32)**: per-event trigonometry replaced by a 744-node per-pose table plus interpolation; about 0.004° mean error | Engineering; *possible* research angle | Software sweeps (Exp02/05) + RTL bit-exactness. Note that the grid generator itself is outside the design and outside the PPA |
| 4 | **Evidence-driven design method**: tournament → real-traffic characterization → fixed-point freeze → RTL → controlled single-variable synthesis rounds | Competition | Visible across the documents; a strong judging point if told concisely |
| 5 | **Native sensor-word reuse**: exact node-fetch reuse; 81% fewer grid reads | Engineering | Exactness proven; PPA benefit unmeasured (F3) |

**Possible research novelty**, pending a literature check: combining a sensor-native group format with merge-on-locality RMW in an event-camera mapping accelerator. Do not call it novel without a related-work section.

---

## 12. Architecture freeze

Freeze all of it as **V1**: T32 · Q1.15 · 2 lanes · 53-edge pipeline · isqrt + CORDIC24/BAM32 · node-fetch reuse · E-lite consecutive merge · 4 banks XOR_NEG · 256 × 128 · CNT_W = 4 · FIFO 128.

Items that are frozen as **parameters, not justified values**, and must be described that way:
- `FIFO_DEPTH = 128`: unvalidated against bursts (F4).
- `CNT_W = 4` and the clear policy: saturates on real data (F2). These are application-level choices.
- 256 × 128 map: E-lite's benefit is coupled to this coarse resolution. A finer map would lower the merge rate.

**No further RTL redesign is justified before submission.** None of the open risks is a datapath bug. Each is settled by measurement or by wording.

See `REMAINING_RISKS.md` for the ranked gaps, `CLAIMS_AND_EVIDENCE.md` for safe and unsafe wording, `FINAL_ARCHITECTURE.md` for the frozen specification, and `REPORT_OUTLINE.md` for the report structure.
