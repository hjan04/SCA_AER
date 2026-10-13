# Claims and Evidence

> **Current-state correction:** This review began before recovery of the final real-data replay and the 53-edge integration. Use `docs/CLAIMS_AND_EVIDENCE_INDEX.md` and `evidence/final/` for current final claims. The measured Sept. 22 maximum frame-level rate is **110.070 M events/s**. The historical **162.75 M/s** is a nominalized event-count/median-interval calculation, not a measured peak. Peak-sequence RTL replay was later completed under measured frame intervals and a uniform-within-frame native-word arrival model. Stage 2 activity-based power remains unresolved; accepted power is vectorless pre-layout logic power.

Each claim below gets an evidence class, a source, and wording that is safe to use.

Evidence classes:
- **RTL**: measured in RTL simulation (Icarus/Xcelium) in this snapshot.
- **SW**: software model (Codex Python), traceable to a file in this snapshot.
- **SW\***: software model reported in earlier documents, **raw files not in this snapshot** (Exp01–04). Must be imported before submission.
- **SYN-L**: Genus synthesis, MODE1 logic only, slow corner, pre-layout.
- **SYN-V**: Genus vectorless power (no activity, no clock tree).
- **DATA**: measured from the real recordings (Exp03).
- **INF**: inference or engineering judgement.
- **ARCH**: true by construction (spec/RTL structure).

---

## 1. Headline claims

| # | Claim | Class | Source | Safe wording |
|---|---|---|---|---|
| 1 | 2 events/cycle acceptance, II = 1 | ARCH + RTL | numeric TB (II = 1 under CE stalls), system TB issue-cycle check | "Two fully pipelined lanes accept up to two events per cycle (II = 1, verified in RTL)." |
| 2 | 100 MHz closes | SYN-L | `results_round2/{d2,elite}_100MHz/report_qor.rpt`: WNS 0, TNS 0, 0 violating paths | "Both variants meet a 10 ns clock in Genus synthesis (GPDK045 slow corner, 0.9 V/125 °C, pre-layout, ideal clock)." |
| 3 | 200 M events/s | ARCH × SYN-L | 1 + 2 | "Nominal mapper capacity is 200 M events/s at 100 MHz." Never present this as delivered throughput |
| 4 | E-lite sustains about 180 M events/s on real traffic | RTL × SYN-L | T09: 40,000 events / 22,246 cycles = 1.80 events/cycle | "On a 40k-event real-recording subset, E-lite sustains 1.80 events/cycle (≈180 M events/s at 100 MHz) vs 1.19 (≈119 M events/s) for the non-merging baseline." State the scope: 2 frame prefixes, synthetic poses, behavioural memory, saturated input |
| 5 | Peak replay context | RTL × DATA | measured peak 110.070 M/s; historical nominalized 162.75 M/s | Use the current-state correction above and cite `evidence/final/PEAK_FRAME_RTL.md`; throughput replay assumes uniform within-frame arrivals. |
| 6 | −33.7% cycles | RTL | 33,566 → 22,246 (Round 2) | "−34% cycles on the real subset (RTL)" |
| 7 | −81.1% bank conflicts | RTL | 16,957 → 3,207 | "−81% same-bank conflicts (RTL)" |
| 8 | −99.5% stall cycles | RTL | 11,374 → 56 | "Stall cycles fall from 11,374 to 56 (RTL)" |
| 9 | −41.37% RMW | SW | `world_memory_format.md`: 3 recordings × 2 synthetic poses, sampled frames; sum 7,967,090 → 4,671,282 (checked) | "Consecutive-only merging removes 39.5–42.4% of world-memory RMW operations across three recordings (software replay, sampled frames)." |
| 10 | 0.441 RMW/event | RTL | T09 | "0.441 RMW records per event on the RTL subset (−56%); the multi-recording software replay gives −40 to −42%." Always quote the two together, because merging depends on the trace |
| 11 | About 10% area overhead | SYN-L | 447,464.934 → 493,230.690 cell (+10.23%); 616,352.597 → 677,885.514 total (+9.98%) | "+10.2% logic cell area (memory arrays excluded); the increase is mainly in the wider bank-update datapath (61%) and the merge-key metadata pipes (26%)." |
| 12 | Power 33.3 / 36.8 mW | SYN-V | `report_power.rpt` | "Vectorless Genus estimates: 33.3 mW (D2) and 36.8 mW (E-lite), logic only, no clock tree, no switching activity. Not used for energy conclusions." |
| 13 | Bit-exact RTL | RTL | numeric 8,064 / 33,231 / 66,462 / 33,231; system 21/21 | "The RTL is bit-exact to the fixed-point reference model on all checked vectors (not a formal proof)." |
| 14 | Address accuracy vs ideal geometry | SW | Exp05b set; Round 3 expanded set | "Angle error ≈1e-5° in the ray-to-angle stage; on 44,291 rays, including boundary-adjacent ones, 99.72% of addresses match the ideal floating-point bin, and every mismatch is a 1-bin edge flip." |
| 15 | Mapping accuracy 0.0043° | SW | `fixed_point_spec.md` (Q1.15 RNE vs Golden) | "Mean 0.0043° (p95 0.0073°) direction error under synthetic 3-axis poses and an ideal pinhole camera (fx = 800), ≈1/300 of a map cell." |
| 16 | 81% of grid reads avoided | RTL | T09: node_reads 7,570 / 40,000 | "Node-fetch reuse serves 81% of lane node sets without a grid read (RTL, real subset). Interpolation arithmetic is not shared in V1." |
| 17 | D2 and E-lite produce identical maps | RTL | all 21 tests | "Merging never changes the result: final maps are bit-identical to the non-merging baseline and to the golden model in all 21 system tests." |

---

## 2. Precise E-lite value statement (replaces the "10% buys 34/81/41" wording)

The proposed sentence mixes four evidence classes, and its RMW figure does not match the RTL figure that sits beside it. Use this instead:

> **On the tested 40,000-event recording subset, E-lite reduced RTL cycles, conflicts and world-memory RMW/event relative to D2. Round 2 MODE1 synthesis reports 10.2% more logic cell area for E-lite, with grid and world memories excluded. Peak-sequence replay passed for 253,145 events under measured frame intervals and uniform-within-frame native-word arrivals. This is a modeled arrival schedule, not a measurement of physical sensor microbursts. Activity-based power remains unresolved.**

| Part | Class |
|---|---|
| 34% cycles, 81% conflicts, 56% RMW | RTL |
| 40–42% RMW | SW |
| 10.2% area | SYN-L |
| 119 → 180 M events/s | RTL cycles × SYN-L clock |
| Measured maximum frame-level rate | 110.070 M events/s, using each frame's own measured interval |
| Historical 162.75 M/s | Nominalized event count divided by median frame interval; not measured peak |
| Stage 2 activity power | unresolved; accepted power is vectorless pre-layout logic power |

---

## 3. Claims that must be corrected or avoided

| Existing wording (where) | Problem | Safer wording |
|---|---|---|
| "misses 24 of the added Golden boundary-neighbor vectors" as the reason to reject direct-bin (`round3_summary.md`, `direct_bin_verification.md`) | The retained CORDIC misses **124** vectors on the same set (re-analysis of `expanded_golden_comparison.csv`). The argument is inverted | "Neither quantizer is exact at every bin edge (CORDIC 124, direct-bin 24 of 44,291 rays; ≤ 1 bin). CORDIC is retained because it is verified at system level, has positive timing slack, and direct-bin's 19% path-area saving was not judged to outweigh the integration risk." |
| "+0.3 ns WNS" for direct-bin (`round3_summary.md`) | The report shows 0.3 **ps**; Path 1 is MET (0 ps) | "Meets 100 MHz with zero slack." |
| "24-iteration BAM32 CORDIC matched … 33,231/33,231 … maximum displacement zero" / "matched all tested bins" (`ray_to_address_contract.md`) | True only for the Exp05b set; superseded by Round 3 | "Exact on the Exp05b set; ≤1-bin edge flips on 0.28% of a boundary-stressed set." |
| "E-lite's ~10% area overhead is justified by …" (`round2_summary.md`) | Value judgement; fine for throughput, but it reads as an overall efficiency claim | "Justified for throughput: it is the difference between sustaining and not sustaining the observed peak at 100 MHz." |
| "roughly 38% more events per total synthesis area" (`synthesis_round1_summary.md`) | Divides by logic-only area, which excludes about 334 kbit of arrays (the same in both) | "≈37% more sustained events/s per unit of *logic* area; with memory arrays included the ratio improves further, because the arrays are identical in both variants." (Or omit) |
| "Two lanes … 200 Mevent/s … above … 163 M/s peak" (`ray_to_address_contract.md`) | Nominal capacity compared against measured demand; D2 actually delivers 119 M/s | Use claim 5 above |
| "52 enabled edges", "Synthesis … Not run yet" (`README.md`, numeric/control READMEs, `SYNTHESIS_PLAN.md`) | Stale | "53 enabled edges (52 numeric + 1 interpolation register, Round 2)." |
| "Cycle counts include the 744-cycle initial grid load" (`README.md`, `SYNTHESIS_PLAN.md`) | T02 reports 316 cycles with grid_wait = 744 | Confirm the counter start point, then restate |
| "native-word reuse" without qualification (prompt / architecture summaries) | V1 implements node-fetch reuse only; no arithmetic is shared | "Native-word node-fetch reuse" |
| "world reconstruction" / "world map" (implied) | Rotation-only direction map; no depth or translation; real data saturates 78% of contributions | "Panoramic (equirectangular) event-occupancy map under externally supplied camera rotation." |
| "real-time" | No end-to-end latency budget, grid-generation latency or intra-frame burst evidence | "Sustains the measured frame-averaged event rates at 100 MHz" (rate, not latency) |
| "ground truth" for roll or pose | No IMU or pose data; roll is inferred from imagery | "Synthetic poses; real recordings are used for traffic and locality only." |
| "power reduction" / "energy-efficient" | Vectorless only; E-lite estimate is **+10.4%** | Avoid until SAIF results exist. Then say "energy per event (activity-based, logic only) …" |
| "optimal" (T32, 4 banks, Q1.15, FIFO 128) | No optimality search; 4 banks not swept; FIFO not sized | "selected", "knee of the measured sweep" (Q1.15 only), "engineering default" (FIFO, CNT_W) |
| "physical AI" | No downstream perception task was evaluated | Use only as motivation in the introduction, never as a result |
| "hardware-efficient" | No comparison with a reference implementation | "logic area X at 100 MHz; Y events/cycle" (numbers, not adjectives) |
| "novel" | No literature comparison | "to our knowledge" only after a related-work check; otherwise "proposed" |
| "Golden accuracy" for Exp01 LUT / Exp02 T32 | Ideal pinhole, no lens distortion, synthetic intrinsics | "relative to an ideal pinhole + rotation reference" |
| "Sept 22 recordings contain significant roll" | Inference | "Visual inspection suggests roll; we therefore stress-tested with a synthetic roll pose." |

---

## 4. Evidence that is valid but must carry its caveat every time it appears

- Every area or power number: "MODE1, memory arrays black-boxed, includes flop FIFO (≈15%) and verification counters (≈2%)."
- Every power number: "vectorless; no clock tree."
- Every events/s number: "RTL cycles on <trace> × 100 MHz synthesis clock."
- Every accuracy number: "synthetic poses, ideal pinhole, fx = 800."
- Every peak-rate number: "frame-averaged; intra-frame burst timing unknown."
