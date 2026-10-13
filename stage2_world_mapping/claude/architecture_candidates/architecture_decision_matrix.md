# Architecture Decision Matrix

**Qualitative scores only.** No synthesis or measured data exists yet for any Stage 2 candidate. Scores are 1 (poor) to 5 (good), relative among these candidates. Sanity calculations (ideal pinhole, assumed θh) inform the accuracy row; they are not measurements.

Candidates (from `candidate_architectures.md`):

- **A**: full fixed-point per-event pipeline (rotation + 2× pipelined CORDIC)
- **C**: yaw-only column PWL/LUT mapper (cylindrical), optional roll front-end
- **D**: per-frame warp grid + per-event bilinear
- **E**: D + block-amortized mapping + tiled/banked world update (Model2 concept)
- **G**: traffic-adaptive *precision* mapper

| Criterion | A | C | D | E | G | Notes / assumptions behind the score |
|---|---|---|---|---|---|---|
| Accuracy potential | 5 | 3 | 4 | 4 | 2 | C is exact for pure yaw but blind to pitch/roll. D/E ≤ 0.25 cell at T = 32 in sanity runs, with pole breakdown. G's accuracy varies with load |
| Arithmetic complexity (5 = least) | 1 | 5 | 4 | 3 | 2 | Per-event operator counts; per-frame cost excluded |
| LUT/storage (5 = least) | 5 | 5 | 3 | 2 | 3 | D needs node rows (~4 kbit if raster, ~30 kbit if not). E adds patch buffers |
| Memory bandwidth (5 = least traffic) | 2 | 2 | 2 | 4 | 3 | E reduces RMWs **only if** real block occupancy ≥ break-even. Unmeasured. Score is conditional |
| Throughput potential | 4 | 4 | 4 | 5 | 3 | All per-event designs are ≤ 1 ev/clk and memory-bound. E is multi-event per access |
| Scalability (motion/representation) | 5 | 2 | 5 | 5 | 3 | D/E absorb distortion, parallax, and representation changes in the node generator |
| Implementation risk (5 = lowest) | 2 | 5 | 4 | 2 | 2 | Oct 30 deadline. E's merge/bank/forwarding logic is the riskiest |
| Verification difficulty (5 = easiest) | 3 | 5 | 4 | 3 | 1 | Commutative cell semantics make E bit-exact checkable. G needs a mode trace in the golden model |
| Novelty | 2 | 1 | 4 | 5 | 3 | Per-frame/per-event split and block amortization are the distinctive ideas |
| Fit with competition objective | 3 | 3 | 4 | 5 | 2 | Q22 asks for "reducing accumulation computation, with evidence" and AER-inefficiency analysis |
| Compatibility with Model2 | 2 | 2 | 3 | 5 | 3 | E uses Model2's packet vocabulary and break-even method |

## Assumptions that would change the scores

1. **Real data stays yaw-dominant with negligible pitch:** C's accuracy rises to 4–5 and D's scalability advantage matters less for the demo.
2. **Decoded events are not raster-ordered within a frame:** D/E storage drops to 2 (full node frame).
3. **Real block occupancy is low** (most groups hold 1–2 events, or s ≥ 1): E's bandwidth advantage disappears. E then collapses into D with extra complexity → **drop E**.
4. **Off-axis parallax (problem_definition D1) is large on real data:** absolute accuracy of all candidates on real data is bounded by parallax. D/E gain relative value because they can add nominal-depth correction for free.
5. **Event rate is low** (≤ a few M ev/s): an iterative CORDIC (B) per event becomes viable, and A/D/E throughput advantages stop mattering.
6. **The organizer requires pole/full-sphere views:** the representation must be a cube map. D/E handle this in the node generator; C cannot.

## Reading of the matrix

- **C** is the lowest-risk path to a correct, demonstrable V1.
- **D** is the best general mapper per unit of risk. It is the recommended V2 core.
- **E** is the strongest *story*, but its score is conditional on a measurement (assumption 3). It must not be committed to before Experiment 03.
- **A** stays as the per-event-exact hardware reference and the "naive" comparison point.
- **G** (precision-adaptive) is not recommended.
