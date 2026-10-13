# Documentation updates made during final local integration

## Stage 1

- Replaced the root README with a two-stage project overview and distinction between traffic-dependent packetization (Stage 1) and locality-dependent memory-update amortization (Stage 2).
- Added `docs/stage1_model2_evidence.md` with verified entry/exit/hold defaults, the traffic-to-synthesis evidence chain, recovered power comparisons, timing wording, implementation-output caveat and local validation results.
- Added `docs/CLAIMS_AND_EVIDENCE_INDEX.md` for traceability across both stages.

## Stage 2 current-state corrections

- Updated the Stage 2 README, numeric/control READMEs, system verification README, synthesis plan and numeric regression summary to state 53 enabled edges for the complete mapper lane, while retaining 52 for the internal ray-to-angle stage.
- Corrected references to the final synthesis status and vectorless-only accepted Stage 2 power; clarified MODE1 memory exclusions and unresolved activity-power annotation coverage.
- Replaced the remaining-risks summary with current limitations and updated the report outline and curated Exp03 summary with the 110.070 M events/s measured frame-level maximum and 162.75 M/s nominalized-rate distinction.
- Updated current review claims and the ray-to-address contract to clarify expanded Golden mismatches and current traffic-rate interpretation. Marked dated audit snapshots as historical where their earlier findings remain preserved.
- Updated the retained system regression summary to remove obsolete external-worktree paths and record the final canonical run and no-reuse RD_LAT=3 metrics.
- Refreshed the frozen RTL SHA-256 inventory for the final canonical production/experimental file locations. Production RTL bytes match the authoritative integration source; no RTL was edited.

No RTL was modified during documentation updates. Historical experiment records and original source histories remain preserved.
