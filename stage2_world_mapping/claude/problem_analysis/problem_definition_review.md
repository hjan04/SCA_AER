# Stage 2 Problem Definition Review

Author: Claude (architecture/analysis workspace). Status: analysis, not a spec.
Nothing here should be copied into `shared/specs/` without team review.

Sources actually read for this review:

- `2차-preparations/Q&A 세션 GMT20260915-095556_Recording.txt` (auto subtitles, Sept 15 Q&A)
- `2차-preparations/GMT20260922-091341_Recording.cutfile.*.srt` (Sept 22 Q&A subtitles)
- `2차-preparations/ROUND2_PLANNING_BRIEF.md`, `DELTA_SDK_SETUP.md`
- `2차-preparations/SCA AER 2차 과제 추진 계획.pdf` (team plan, Oct 6)
- DELTA SDK README + `settings/Delta_01_1000FPS.txt` (sensor id `S5KRC1S`)
- NRV processing API page (ClassicEvent / CompactEvent / frameTimestamp)

Transcripts are machine subtitles of spoken Korean. They contain recognition
errors, and some statements are the professor thinking aloud. Paraphrases below
are labelled with the source session (Q15 = Sept 15, Q22 = Sept 22).

---

## A. Confirmed competition requirements

These are stated in the official task text, as quoted in the team plan and planning brief, or repeated firmly by the organizer.

| # | Requirement | Source |
|---|---|---|
| A1 | Map visual events from an n×m sensor into a larger N×M **World Memory** (n×m ≪ N×M). | Orientation PDF p.3 (via brief / team plan) |
| A2 | Core operation is **pixel coordinate → world coordinate** while the sensor *changes direction from a fixed position*. | Orientation PDF; Q15 |
| A3 | Judging cares about PPA, robustness, parallel hardware, and explanation of design choices and results. | Orientation PDF p.2 (via brief) |
| A4 | Final submission Oct 30, including a ~10-minute presentation recording. | Orientation PDF p.2 (via brief) |
| A5 | Digital flow is RTL → synthesis → timing. Gate-level schematic is not required. Layout/post-layout is stated for **analog**. Its applicability to digital is not confirmed. | Q15 |
| A6 | All semiconductor used counts toward cost, **including World Memory SRAM**. | Q15 ("사용하는 반도체는 모두 고려") |
| A7 | No SRAM compiler/macro is provided. Teams must design one or substitute an assumed memory model, and **explain** the latency, mapping, and cost assumptions. | Q15 |
| A8 | Standard cell library: 45 nm GPDK (gpdk045). | Q15 |
| A9 | A self-built testbench demonstrating operation is expected. | Q15 |

## B. Statements and hints from the Q&A (organizer-spoken, informal)

| # | Statement (paraphrased) | Session | Weight |
|---|---|---|---|
| B1 | Motion is **rotation only**. Axis-wise range is about ±180° (yaw, "sideways", and roll were each mentioned "within 180°"). No intentional translation. Small incidental translation exists because the rotation stage is not aligned to the sensor. | Q15 | Strong |
| B2 | **Sept 22 datasets:** the camera is mounted *on top of a rod* and revolves around the rod ("the rod is the earth, the sensor is the moon"). A second recording puts the rod on a larger turntable, giving two rotation axes and a larger radius. The professor says explicitly that **rotation is not about the sensor center**. | Q22 | Strong, and it **conflicts with "rotation only" geometrically** (see D1) |
| B3 | No ground truth (pose or 3D) is available. Known constraints are given instead: one axis, rotation in a plane. Rotation axis information "will be provided separately". Rod–sensor distances were marked (47.5 / 48.5 / …), but the professor said the numbers looked wrong and would be re-measured. | Q15, Q22 | Strong |
| B4 | Angular velocity/angle are **not provided** ("아직 없어요"). The professor expects teams can *infer* rotation speed. The 1000 FPS frame spacing is 1 ms and the scene is static. Vertical rods show which way is up. | Q15, Q22 | Strong |
| B5 | Camera is 960×720 with a 6 mm M12 lens (cheap security-camera lens). Distortion exists but is "probably not the main issue". If a team thinks it matters, they should explain why. Treating the lens as an ideal pinhole is acceptable ("그냥 아이디얼 하다라고 생각하고"). | Q15, Q22 | Strong |
| B6 | Data format is NRV/Samsung **Group-AER**. Each frame is raster-scanned top-left → bottom-right, and the timestamp is attached **once per frame**, not per event. Empty regions are skipped and x/y are compressed. Sensor output is about 1000 FPS. The playback showed "1291 FPS". | Q15, Q22 | Strong |
| B7 | Event timestamps do not equal the true change time. Dark scenes delay events, up to seconds for very dark scenes. The organizer's per-frame scheme bounded timestamp error to tens of µs (about 60 µs) in heavy traffic. | Q22 | Medium (design-philosophy statement) |
| B8 | Resolution and World Memory size are **the team's choice**. Matching 960×720 is fine. Subsampling first and refining later is suggested. N×M "too large is unrealistic". About 1000×1000 or 1024×1024 was the professor's initial wish, but "no real difference". Start small, then scale. | Q15 | Strong |
| B9 | What each cell stores is the team's choice: brightness, polarity, count, timestamp, decay. "Discard timestamps if not needed". Recent detail can be kept while old detail fades. Overwrite vs accumulate is the team's choice. | Q15, Q22 | Strong |
| B10 | Showing ON/OFF events accumulating at the same world location is the evidence that coordinate conversion works. Moving objects will *not* re-register, and that mismatch is itself meaningful (attention). | Q22 | Strong |
| B11 | Noise and hot pixels are **not filtered** in the provided data. | Q15 | Strong |
| B12 | 2×2 or 4×4 binned data may be recorded and shared. The professor is undecided whether binning or subsampling is a good idea and wants teams to justify it. | Q15 | Medium |
| B13 | Using the Stage 1 AER is **not mandatory** ("예시이지 반드시 이렇게 하라는 게 아니에요"). Formats such as XYPT are free, but teams must argue why their choice is more effective. | Q22 | Strong |
| B14 | The organizer described our Stage 1 design: "conventional AER plus packet-format grouping, applied adaptively by event distribution". For Stage 2 they asked teams to "carry the idea of **reducing accumulation computation**, with evidence: computation saved, speed, power, area." | Q22 | **Strong. This is direct guidance for our story.** |
| B15 | The ask is to propose a pixel XY → world conversion method and to identify **inefficiencies in the AER system** that the conversion exposes. | Q22 | Strong |
| B16 | Matching a rotation speed is "not the main point". FOV is effectively 360° when the head moves. | Q22 | Medium |
| B17 | The professor's narrative mentions "inferring distance" because near and far objects move at different pixel speeds. | Q15 | Ambiguous (see D1) |

## C. Our current assumptions (team-chosen; NOT requirements)

| # | Assumption | Why it is reasonable | Must stay configurable? |
|---|---|---|---|
| C1 | Ideal pinhole, principal point at the image center, square pixels, no distortion in V1 | B5 permits it | **Yes.** cx, cy, fx, fy, and an optional distortion table |
| C2 | Orientation is supplied to the mapper as an **input stream** (one sample per sensor frame or faster). It comes from a synthetic trajectory, or from an offline/online estimate on real data. | B4: not given; estimation is a separate problem | Yes. Source of pose must be pluggable |
| C3 | One orientation per sensor frame is adequate in V1, optionally with per-row interpolation. | B6 frame timestamp | Yes. Per-row time interpolation should be an option |
| C4 | Rotation-only geometry; translation is ignored in V1 | B1 | **Yes.** See D1. The real Sept 22 rig violates it |
| C5 | World representation = directional map (sphere/cylinder), not metric 3D | Rotation-only gives no depth | Yes |
| C6 | Input to the mapper is decoded events (x, y, p, frame_t). The `.dvs` decoder and DELTA SDK stay outside the measured hardware boundary. | Keeps scope tractable | Boundary must be stated explicitly in the report |
| C7 | World memory is an assumed synchronous SRAM, modeled with stated latency/ports and an area/power estimate from a cited source | A7 | Yes. Ports, latency, word width |
| C8 | Clock about 100 MHz in GPDK045 (Stage 1 reached 103–107 MHz pre-layout) | Stage 1 evidence | Yes |

## D. Unresolved questions

Ordered by how strongly the answer changes the architecture.

1. **D1: Is the real data actually "rotation-only"?** Q22 says the camera revolves *around a rod with an offset* (B2). That is rotation plus a translation of the camera center on a circle of radius r. The rotation-only mapping error then depends on depth. A point at distance D is mis-registered by approximately

   `ε ≈ (r / D) · sin(off-axis angle)` (radians) → `ε_px ≈ fx · ε`

   Illustration only, because r, D, and fx are not confirmed: with r = 4 cm, D = 0.5 m, and a half-FOV of 30° (fx ≈ 831 px), ε ≈ 0.04 rad ≈ 33 sensor pixels at the image edge. Seen from the opposite image edge, the same object can be about 66 px apart. That would dwarf every approximation error discussed in `math_review/`. **This is the single biggest open technical question.** It needs (a) the measured offset r, (b) the object distances (rods at about 0.5 m per the setup notes), and (c) a decision on whether to model a *nominal depth* or accept depth-dependent smear. This is probably what the professor meant by "you also need distance" (B17).
2. **D2: How is orientation obtained?** Possibilities: (a) not provided at all, so it must be estimated; (b) "rotation axis info" will be published (B3); (c) inferred from data, as the professor suggests. The answer decides whether a pose estimator is part of the evaluated circuit.
3. **D3: fx in pixels.** We know the 6 mm focal length but not the pixel pitch of the S5KRC1S. **We must not invent fx.** It can be (a) obtained from NRV/Samsung, (b) calibrated from the data, for example from known rod spacing or one full revolution of features, or (c) treated as a swept parameter. All designs here must parameterize fx (equivalently, the half-FOV).
4. **D4: Exact `.dvs`/HDF5 timestamp semantics.** Is it a frame timestamp only? What resolution? Is raster read order preserved in the export? Is the "1291 FPS" frame rate variable?
5. **D5: Which recordings are evaluated?** Sept 15 (yaw sweep, with a moving fan), Sept 22 ×2 (rod orbit, two-axis). Only the Sept 15 `.dvs` exists locally (`~/DELTA_SDK-1.0.0/Linux/x64/RawDataSave/`). The team plan says the Sept 22 files were secured, but they are not in the repo.
6. **D6: Is lossy processing allowed?** Pooling, dropping, merging repeats, per-frame time sharing. B12 is undecided.
7. **D7: Is P&R / post-layout required for digital?** (A5)
8. **D8: How is SRAM cost evaluated without a macro?** (A7) Which estimation source is acceptable?
9. **D9: Is a numeric scoring metric or tolerance planned?** None was announced. B10 suggests visual and consistency evidence.

## E. Optional research extensions (not required)

- On-chip orientation estimation (yaw-rate from inter-frame column histogram shift; see `architecture_candidates/candidate_architectures.md` §H).
- Nominal-depth parallax correction for the orbiting rig (D1).
- Lens distortion folded into the pixel→ray stage.
- Moving-object / "attention" map: events that fail to re-register (B10).
- Multi-resolution, foveated, or decaying world memory (B8, B9).
- Stereo / 3D (mentioned as future by the organizer; out of scope).

## Specific clarifications (the requested "be careful about" list)

- **Rotation vs translation.** The *official* framing is rotation-only (A2, B1). The *real rig* is an off-center orbit (B2). These are not the same. V1 assumes rotation-only. The report must quantify the parallax error (D1) instead of hiding it.
- **Known vs estimated orientation.** Pose is **not** provided (B4). Every accuracy claim must state its pose source: synthetic ground truth, estimated, or assumed constant speed.
- **Pixel vs world coordinate.** Pixel = (x, y) in the 960×720 sensor plane. World = direction in a fixed frame attached to the rotation stage, and only a direction (C5).
- **Directional map vs metric 3D.** For a pure rotation about the optical center, the mapping is depth-independent. So a directional map is the *correct* world model, and no 3D is needed. With an offset axis (D1) it stops being exact.
- **Unavailable ground truth.** Synthetic data with known pose gives absolute error metrics. Real data gives only self-consistency metrics (`verification_plan/metrics.md`).
- **Real timestamp behaviour.** One timestamp per about 1 ms frame, raster readout, brightness-dependent latency (B6, B7). Rotation converts timing error into angular error: `Δθ = ω · Δt`.
- **World memory size freedom.** Free (B8). The real constraint is cost (A6): there is no macro (A7), and the area must be estimated and reported.
- **Subsampling/binning.** Mentioned and permitted as an idea, but not endorsed (B12). It must be justified with measured accuracy impact.
- **Memory/PPA expectations.** Logic PPA from Genus; memory cost estimated separately and reported (A6, A7). Never silently synthesize a large map into flip-flops.
