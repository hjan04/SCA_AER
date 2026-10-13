# Claude workspace: Stage 2 architecture and analysis

Owned by Claude. Contents: problem interpretation, mathematical review, architecture candidates, world-memory analysis, validation strategy, and RTL architecture recommendations.

**No RTL and no PPA numbers are produced here.** Numerical statements are either derivations or labelled sanity calculations (`math_review/sanity/`), which assume an ideal pinhole and an assumed half-FOV because fx is unknown, or Exp03 measurements on the real recordings (image space, no pose).

## Index

| Path | Content |
|---|---|
| `problem_analysis/problem_definition_review.md` | Confirmed requirements vs Q&A hints vs assumptions vs open questions |
| `problem_analysis/stage1_reuse_analysis.md` | What Model2 contributes, and what must not be inherited |
| `math_review/pixel_to_world_derivation.md` | Pixel → ray → rotation → world address; cost per implementation class |
| `math_review/approximation_analysis.md` | PWL, LUT, LUT+interp, CORDIC, and warp-grid error/storage |
| `math_review/sanity/*.py` | Tiny sanity calculations backing the tables |
| `architecture_candidates/world_representation.md` | Equirect vs cylinder vs plane vs ray-bins vs cube map |
| `architecture_candidates/candidate_architectures.md` | Candidates A–H with datapaths |
| `architecture_candidates/world_memory_architectures.md` | Memory organizations, cell semantics, hazards, V1 and ambitious policies |
| `architecture_candidates/adaptive_precision.md` | Traffic-adaptive mapping: what to keep and what to reject |
| `architecture_candidates/model2_integration.md` | Where mapping sits relative to Model2 |
| `architecture_candidates/architecture_decision_matrix.md` | Qualitative comparison and its assumptions |
| `verification_plan/metrics.md` | Metrics with and without ground truth |
| `verification_plan/experiment_plan.md` | Prioritized Exp 02+ |
| `verification_plan/real_data_validation.md` | Using the organizer recordings without pose truth |
| `recommendations/recommended_v1.md` | Current recommendation (hypothesis vs measured) |
| `recommendations/rtl_block_decomposition.md` | Proposed blocks, interfaces, and verification chain |
| `recommendations/questions_for_codex_results.md` | Review questions for Exp 01 |
| `recommendations/next_steps.md` | Pre-RTL evidence gates and schedule |
| `verification_plan/exp03_summary.md` | **Exp03 (measured, real data):** traffic, block locality, break-even, memory-update proxy, E classification |
| `verification_plan/exp03_results/` | Exp03 CSVs and plots |
| `verification_plan/exp03_tools/` | `.dvs` decoder (+ `FORMAT_NOTES.md`), analysis script, `run_exp03.sh` driver |
| `verification_plan/exp03_cache/` | Git-ignored derived data (decoded events, ~0.9 GB) |
| `recommendations/post_exp03_recommendation.md` | Recommendation updated with Exp03 evidence (pre-Exp03 version kept) |
| `rtl_spec/rtl_spec_summary.md` | **RTL microarchitecture spec** for the frozen E-lite architecture (start here); 11 companion documents in `rtl_spec/` |
| `rtl_spec/analysis/` | Real-stream dispatch / reuse cycle-count model and its results |
