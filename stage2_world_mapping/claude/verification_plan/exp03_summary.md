# Experiment 03: Real-Traffic Locality and Block-Amortization Feasibility

Owner: Claude (analysis workspace). Status: **measured on real organizer recordings**, all in **image space**. No pose was applied. Nothing below is an actual world-memory collision rate; image-space numbers are labelled as *proxies* where they stand in for world-space quantities.

Reproduce: `exp03_tools/run_exp03.sh`. It copy-extracts, decodes, analyzes one dataset per process, and merges. Raw recordings are only read (SHA-256 in `exp03_results/input_sha256.txt`). Derived data lives in the git-ignored `exp03_cache/`.

## 0. Data actually found and analyzed

| Recording | Location (read-only) | Size | Analyzed |
|---|---|---|---|
| `2026-09-15-14-27-41-DELTA.dvs` | `~/DELTA_SDK-1.0.0/Linux/x64/RawDataSave/` (identical copy in `C:\Users\hwiju\Downloads`, same SHA-256) | 108,448,228 B | yes → `sept15_yaw` |
| `2026-09-22-16-42-32-DELTA.dvs` | inside `…/OneDrive/Desktop/동아리/AI 반도체 회로설계 경진 대회/2026-09-22-16-42-32-DELTA.zip` | 99,398,908 B | yes → `sept22a_1642_32` |
| `2026-09-22-16-42-44-DELTA.dvs` | inside `…/2026-09-22-16-42-44-DELTA.zip` (same folder) | 111,277,936 B | yes → `sept22b_1642_44` |

- **Not found anywhere:** `.h5`/`.hdf5` exports, CSV event dumps, any orientation/pose or calibration file. The SDK `calibration_values.txt` holds circle-grid/stereo-baseline settings, not our camera's intrinsics. `회전 setup.pptx` exists in the same OneDrive folder; it was not parsed here.
- **Existing parsers:** none in the repository; Codex's worktree (`/tmp/sca_aer_codex_modeling`) has no `.dvs` parser either. The only official decoder is the closed SDK (`libDELTA_SDK.so`) and the GUI's HDF5 export. Running the GUI export headless was not possible (it needs interactive WSLg).
- **Decoder used:** `exp03_tools/dvs_decode.py`, written for this experiment from a disassembly of the SDK's own parser (`FORMAT_NOTES.md`). Validation: coherent scene structure in `exp03_results/decode_check_accumulated.png`; only 0–3 out-of-range groups per file; the timing fields are self-consistent.
- **Which Sept 22 file is "rod orbit" and which is "turntable"** is not stated in the files. The names keep the timestamps. Both are *inferred* (heatmap) to contain strong roll-like motion; see §3C.

## 1. Data format

**A. Directly observed in the decoded files**
- 32-bit words. Per file: ~25 M event words, ~1.9 M column words, ~4.1 k time words, ~2,060 frame-end words, 7 header words.
- Stream per frame: `FRAME_END → TIME(coarse) → TIME(fine) → COLUMN 0 → events → COLUMN k → events → …`.
- **Column-major scan.** x is non-decreasing within every frame (100.00 % of consecutive pairs). Column words increase within a frame (99.8 %; the rest are frame transitions). About 903–947 column words per frame out of 960 columns.
- Within a column, y is *nearly* monotone: 97 % of consecutive pairs are non-decreasing in column-major address. The 3 % violations come from the two-group word packing.
- Each event word carries **two 8-pixel vertical groups** of the same column (group g and g+off), each with its own polarity bit and 8-bit mask. Mean **3.28–3.45 pixel events per 32-bit word**, i.e. ≈ 9.3–9.8 bits per pixel event on disk.
- One timestamp per frame. **Frame period 773 µs** (p1 = p99 = 773–774 µs) → **1293.7 FPS**. Recording length 1.589–1.592 s.
- Columns without events: 0.2 % of emitted column words. Empty columns are skipped (≈ 13–57 columns per frame absent), and empty 8-pixel groups are never emitted.
- Files start mid-frame. Frame 0 has no timestamp; 39 / 810 / 137 events are excluded from timing statistics.

**B. Documented behaviour** (NRV docs / organizer Q&A)
- Frame-based Group-AER readout with one timestamp per frame (CompactEvent `frameTimestamp`).
- Readout scans the whole array top-left → bottom-right (Q22).
- Hot pixels and noise are not filtered (Q15).

**C. Inference**
- The organizer's "top-left to bottom-right" is, in the decoded coordinates, **column-by-column (left → right), each column top → bottom**.
- Time stamps are `ms_counter·1000 + µs` (from register comments and value ranges; not read from the SDK's scale constants).
- The order inside a frame is **format-imposed readout order, not physical event time**. All events of a frame share one timestamp.

## 2. Event rate

| | sept15_yaw | sept22a | sept22b |
|---|---|---|---|
| Pixel events | 86.8 M | 75.3 M | 88.1 M |
| **Mean rate** | **54.5 M ev/s** | **47.4 M ev/s** | **55.4 M ev/s** |
| Events/frame mean / p50 | 42.1 k / 46.8 k | 36.6 k / 38.7 k | 42.9 k / 45.1 k |
| Events/frame p95 / p99 / max | 79.2 k / 84.0 k / 86.7 k | 70.6 k / 79.4 k / 80.7 k | 76.8 k / 82.7 k / 125.8 k |
| Rate at p95 frame | 102 M ev/s | 91 M ev/s | 99 M ev/s |
| **Rate at max frame** | 112 M ev/s | 104 M ev/s | **163 M ev/s** |
| Peak 10 ms window | 109 M ev/s | 104 M ev/s | 109 M ev/s |
| Event words/s (mean) | ≈ 15.8 M | ≈ 14.5 M | ≈ 16.3 M |

Traffic ramps from ~1 k events/frame at rest to 70–125 k events/frame during motion (`events_per_frame.png`). The 1 ms window statistics alias against the 0.773 ms frame period (a window holds 1 or 2 frames), so **frame-basis rates are the primary numbers**.

**Immediate hardware consequence (measured rates vs. stated clock assumption):**
- At the ~100 MHz Stage 1 clock, a per-pixel-event datapath at 1 event/cycle runs at ~50–55 % average utilisation.
- It reaches ~100 % at p95 frames and is **overloaded by up to 1.6× at peak**.
- A single-port read-modify-write memory (≈ 0.5 RMW/cycle) **cannot sustain even the mean rate**.
- By contrast, one *sensor word* per cycle needs only ~16 M words/s on average (≤ ~48 M words/s at the 125.8 k-event peak frame).

## 3. Spatial clustering and block occupancy

Per frame (one 0.773 ms frame, the window in which the transform is constant). Events per *occupied* block:

| Block | Mean | p50 | p90 | p95 | p99 | Max | Singleton blocks | Events in blocks ≥2 / ≥4 / ≥8 / ≥16 |
|---|---|---|---|---|---|---|---|---|
| 2×2 | 1.45–1.47 | 1 | 3 | 3 | 4 | 6–14 | 67–69 % | 52–54 / 8–10 / 0 / 0 % |
| **1×8 (native group)** | 1.77–1.88 | 1 | 3–4 | 4–5 | 6–8 | 16–22 | 57–59 % | 67–69 / 25–31 / 1.6–5 / 0 % |
| **4×4** | 2.56–2.67 | 2 | 6 | 8 | 11–12 | 20–41 | 45–48 % | 82–83 / 54–56 / 19–22 / 0.4–2 % |
| **8×8** | 5.75–6.16 | 3 | 14–16 | 20–21 | 31–35 | 72–142 | 27–29 % | 95–96 / 84–86 / 65–68 / 36–38 % |
| 16×16 | 16.6–18.3 | 8–9 | 44–49 | 60–65 | 97–105 | 250–491 | 12–14 % | 99 / 97 / 91–92 / 79–81 % |
| 32×32 | 55.9–63.6 | 29–37 | 147–165 | 198–215 | 321–335 | 754–1430 | 4–6 % | ≈ 99–100 % |

Ranges span the three recordings. The values are **remarkably consistent across very different motions**, which argues that they reflect the sensor plus edge-structure statistics rather than one scene.

Multi-frame windows (4 frames ≈ 3.1 ms; 13 frames ≈ 10 ms) raise occupancy sharply: 4×4 goes to mean 6–6.4 (4 frames) and 15–16 (13 frames). They are **image-space** proxies, though. Under rotation the same image block sees different world points in different frames, so cross-frame merging requires world-space addressing. These rows are upper bounds and must not be quoted as achievable.

### 3B. Noise
- **24–26 % of events are isolated:** no other event in their 3×3 neighbourhood in the same frame. That is a noise-like floor (`isolated_event_frac`).
- Every one of the 691,200 pixels fires at least once. Mean ≈ 109–127 events per pixel over 2,060 frames.
- Much of the 2×2 / 1×8 singleton mass is this floor.

### 3C. Motion inferred from accumulated images (inference, not ground truth)
- `pixel_event_heatmap.png`: **Sept 15 shows horizontal streaking**, consistent with yaw (pan).
- **Both Sept 22 recordings show concentric rings** around a centre near (x ≈ 470–520, y ≈ 390–410), consistent with **roll-like rotation** about an axis close to, but not exactly at, the image centre (480, 360).
- The 10-frame snapshots (`decode_check_accumulated.png`) of Sept 22 are visibly tilted (22b strongly), with curved motion streaks.
- **Consequence:** a yaw-only mapper (Candidate C) cannot handle the Sept 22 data. Roll support (in-plane rotation, or the general warp grid D) is required.

## 4. Best block size for locality

There is no single "best". Amortization grows smoothly with area (`block_amortization_vs_block_size.png`): 1×8 → 1.8×, 4×4 → 2.6×, 8×8 → 6×, 16×16 → 17–18×. Three facts set the practical choice:

1. **The stream is column-major.** Only the native 1×8 column group arrives as one unit; a 2-D B×B block is visited in B separate column passes (4×4 → 1.8 visits; 8×8 → 3.3; 16×16 → 7.3 visits per block-frame). Assembling a B×B block therefore needs a **B-column strip buffer** (≈ B × 720 × 2 bits: ~5.8 kbit for 4×4, ~11.5 kbit for 8×8).
2. **Consecutive-event locality is moderate:** P(next event in same 4×4 / 8×8 / 16×16 block) = 29–31 % / 44–47 % / 56–59 %, with mean runs of 1.4 / 1.8–1.9 / 2.3–2.5 events. Same-block reuse distance p95 ≈ 130–180 events, i.e. a few columns.
3. **Diminishing returns vs. footprint risk:** larger image blocks map to larger and, under roll, rotated world footprints that touch more memory tiles. Memory merge benefit therefore saturates sooner than transform amortization.

**8×8 is the knee in these data:** 2.3× the amortization of 4×4, 65–68 % of events in blocks with ≥ 8 events, buffer cost still moderate. **The native 1×8 group is the zero-buffer option.**

## 5. How many events share an occupied block (per frame)

- **4×4:** median 2, mean ≈ 2.6. 45–48 % of occupied blocks hold a single event, but they carry only 17–18 % of events.
- **8×8:** median 3, mean ≈ 6.
- **Native 1×8:** median 1, mean ≈ 1.8.
- **Sensor word (two 1×8 groups):** mean 3.3–3.45.

## 6. Theoretical transform reuse

Idealized amortization (events / occupied blocks, one transform per block): **1.8× (1×8), 2.6× (4×4), 6.1× (8×8), 17–18× (16×16)**. Per *sensor word*: **3.3–3.45×** at no buffering cost.

Break-even model: grouped cost per block = `β·C_event + a·n·C_event` vs `n·C_event`, i.e. grouping wins when `n > β/(1−a)`. Fractions are of *events*; "adaptive" means "group only when n > n*", the Stage 1 break-even idea.

| Scenario (β, a) | n* | 4×4: events above n* | 4×4 cost (adaptive) | 8×8: events above n* | 8×8 cost (adaptive) |
|---|---|---|---|---|---|
| (1, 0.25) | 1.33 | 83 % | 0.58 | 96 % | 0.40 |
| (2, 0.25) | 2.67 | 68–69 % | 0.75 | 91 % | 0.51 |
| (4, 0.25) | 5.33 | 34–36 % | 0.91–0.92 | 76–77 % | 0.65–0.66 |

Costs are relative to per-event processing = 1.00. Always-grouped processing (no threshold) is *worse* than per-event for 4×4 at β = 4 (1.75×). **A threshold, i.e. adaptive grouping, is therefore required for small blocks.** β and a are normalized scenarios, not gate-level numbers. Full table: `break_even_summary.csv`.

## 7. Theoretical memory-update reduction (image-space proxy)

RMW ratio vs. one RMW per event, if every event of an occupied block is merged into at most k memory words (k = 1 ideal; 2 limited; 4 = conservative bound for a footprint straddling a 2×2 group of tiles):

| Block (1 frame) | k = 1 (ideal) | k = 2 | k = 4 (conservative) |
|---|---|---|---|
| 1×8 | 0.53–0.56 | 0.76–0.80 | 0.93–0.96 |
| 4×4 | 0.37–0.39 | 0.58–0.60 | **0.80–0.81** |
| 8×8 | 0.16–0.17 | 0.28–0.30 | **0.45–0.47** |
| 16×16 | 0.055–0.06 | 0.10–0.11 | 0.19–0.20 |

Caveats, all of which make these **upper-bound proxies**:
- Image-block → world-tile footprints are not measured, because there is no pose. Under the roll seen in Sept 22, footprints rotate, so k = 4 (or worse for large blocks at fine world scale) is the realistic assumption.
- This reduces the **number of accesses, not bits moved**: a 4×4 × 4-bit tile word is 64 bits and an 8×8 tile word is 256 bits.
- Cross-frame merging (4–13 frame windows: 4×4 k = 1 down to 0.06–0.16) would need world-space buffering and is not claimed.

## 8. Raster order

- **Real and strict at column level:** 100 % non-decreasing x within frames.
- **Near-monotone within a column:** 97 %.
- Only active columns and active 8-pixel groups are emitted.
- It is a readout order imposed by the format, not physical time order.
- **It is exploitable**, but as *column* streaming, not row streaming. The warp-grid node buffer proposed earlier (`candidate_architectures.md` D) must hold ~2 node *columns* (≈ 2 × (720/T + 1) nodes) instead of 2 node rows. A block assembler needs a B-column strip buffer.

## 9. Hot pixels

**Not significant** under the stated rule (count > 20× the 8-neighbour median AND active in > 20 % of frames):
- 3–9 candidates per file, ≤ 0.01 % of events.
- Sept 22a's 9 candidates cluster near the inferred rotation centre, where the scene barely moves; they are more likely low-motion artefacts than defective pixels.
- No pixel is active in > 90 % of frames.
- The top 0.1 % of pixels carry 0.5–0.6 % of events, and the top 1 % carry 2.2–2.5 %, so event load is spread almost uniformly.

The real noise issue is the **diffuse ~25 % isolated-event floor**, not hot pixels.

## 10. Polarity

| | sept15 | sept22a | sept22b |
|---|---|---|---|
| p1 / p0 | 52.0 / 48.0 % | 50.1 / 49.9 % | 51.3 / 48.7 % |
| 4×4 blocks with both polarities (per frame) | 9.5 % (17 % of events) | 5.1 % (8 % of events) | 4.8 % (7 % of events) |
| Same pixel, opposite polarity, same frame | ≈ 0 | ≈ 0 | 3×10⁻⁵ |
| Pixel refires next frame with same polarity | 7.4 % of events | 7.4 % | 8.0 % |
| … with opposite polarity | 1.3 % | 0.6 % | 0.7 % |

- Polarity is balanced overall but **spatially segregated** within a frame (few mixed blocks).
- Repeats are predominantly **same-polarity** bursts.
- Which bit value means ON is not determinable from the parser.

## 11. Banking (image-space, exploratory)

| Scheme | Load share | Consecutive same-bank pairs |
|---|---|---|
| 2 banks by x parity | 50/50 | **98 %** (consecutive events share a column) |
| 2 banks by y parity | 50/50 | 37–39 % |
| 4 banks by (x, y) parity | 25 % each | 36–38 % |
| **4 banks by y mod 4** | 25 % each | **15–16 %** |
| 4 banks by 4×4-tile parity | 25 % each | 54 % (same-tile runs: merge opportunities, not true conflicts) |

Long-run load is perfectly balanced for every scheme; per-frame skew is ≤ 1.02 mean and ≤ 1.08 p95. **Interleave must follow the scan:**
- banking by x is useless for a column-major stream;
- banking by low y bits (image) works best for per-event dual issue.

These are image-space results. In world space under roll, the sensor column direction rotates, so the final interleave must be re-measured with pose.

## 12. Model2 connection

- **The sensor already does Model2's job for transport.** Group-AER emits per-column 8-pixel bitmaps with shared addressing. That is effectively a permanent "dense mode" with 1×8 groups, delivering 3.3–3.45 pixel events per 32-bit word.
- Re-packetizing into Model2's 4×4 sparse/dense packets would be **redundant for transport**. It would also require column→block reordering, i.e. a strip buffer, with no transport benefit.
- **The data does expose sparse and dense regimes over time:** ~1 k events/frame at rest vs 70–125 k in motion, a 100× swing. Within a frame, 4×4 occupancy ranges from singletons (45 % of blocks) to dense blocks.
- **The Stage 1 break-even concept transfers directly:**
  - Grouped processing pays only above an occupancy threshold n* = β/(1−a).
  - With a threshold, 4×4 grouping is never worse than per-event.
  - Without one, it can be up to 1.75× worse (β = 4).
  - This is the same "dense only above break-even" logic as Model2's DENSE_ENTER_THRESHOLD.
- **Verdict:** reuse Model2's *idea* (occupancy-thresholded grouping, physical-cost break-even, hysteresis if mode switching has cost). Do not reuse its RTL or packet format as a stage in front of the mapper.

## 13. Architecture E classification

**B: PROMISING, NEEDS RTL COST CHECK.**

Evidence for:
- Locality is real and consistent across three different motions. 82–83 % of events share a 4×4 block, and 95–96 % share an 8×8 block, in the same frame.
- Transform amortization is 2.6× (4×4), 6× (8×8), and 3.3× free per sensor word.
- Measured rates (mean ~55 M, p95 ~100 M, peak 163 M ev/s) **exceed what a 1-event/cycle, 1-RMW/event design sustains at ~100 MHz**. Some form of grouping *or* lane/bank replication is needed anyway.

Evidence against / unresolved:
- The conservative per-frame memory saving is modest for 4×4 (~20 %) and only becomes large for 8×8 (~55 %, with 256-bit tile words) or bigger.
- 2-D blocks require column-strip buffering.
- World footprints under roll are unmeasured.
- About 25 % of events are isolated noise that groups poorly.
- The comparison that decides E is **E (grouping) vs D × N (replicated per-event lanes + banks)** at equal sustained throughput. That is an RTL/synthesis question this experiment cannot answer.

## Answers to the required questions

1. **Datasets analyzed:** all three real recordings that exist locally: Sept 15, Sept 22 16:42:32, Sept 22 16:42:44.
2. **Rates:** 1293.7 FPS (773 µs frames). 36.6–42.9 k events/frame mean, 79–84 k at p99, 125.8 k max. 47–55 M ev/s mean, ~100 M at p95 frames, 163 M peak. ~15–16 M sensor words/s.
3. **Clustering:** strong. 82–83 % of events share a 4×4 block and 95–96 % share an 8×8 block within a frame. A diffuse ~25 % isolated floor sits on top.
4. **Best block size:** 8×8 is the knee for amortization vs buffering. Native 1×8 / sensor-word grouping is the zero-cost baseline.
5. **Events per occupied block:** 4×4 median 2 (mean 2.6); 8×8 median 3 (mean 6.1); native group mean 1.8; sensor word 3.3–3.45.
6. **Transform reuse:** 2.6× (4×4), 6× (8×8), 3.3× per sensor word (free). With realistic overhead and a threshold, the transform cost ratio is 0.40–0.66 (8×8) and 0.58–0.92 (4×4).
7. **Memory-update reduction (proxy):** per frame, ideal 0.37 (4×4) / 0.16 (8×8); conservative 0.81 (4×4) / 0.46 (8×8) of per-event RMWs. Counts accesses, not bits; world footprint unmeasured.
8. **Raster order:** yes. Strict column-major across columns, near-monotone within a column. Exploitable with column-oriented buffers.
9. **Hot pixels:** insignificant (≤ 9 candidates, ≤ 0.01 % of events). Diffuse noise (~25 % isolated) is significant.
10. **Polarity:** balanced (50–52 % p1); spatially segregated; repeats are mostly same-polarity.
11. **Model2-style grouping:** its *break-even/threshold idea* is supported by the data. Its *packetization* is redundant with the sensor's Group-AER.
12. **Is E justified?** **B: promising, needs RTL cost check** against a replicated per-event design.
