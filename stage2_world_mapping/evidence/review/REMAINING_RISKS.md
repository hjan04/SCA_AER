# Remaining Risks and Scope Limits

This file summarizes limitations of the final Stage 2 evidence. Earlier review notes in this directory record the state at the time they were written; use `docs/CLAIMS_AND_EVIDENCE_INDEX.md` and `evidence/final/LIMITATIONS.md` for the current interpretation.

- **Activity-based power is unresolved.** Accepted power is vectorless, pre-layout logic power. RTL-to-gate activity annotation coverage was insufficient. There is no post-CTS clock-tree or whole-chip power result.
- **MODE1 PPA excludes grid and world memories.** The reported figures are logic comparison results, not total-chip PPA.
- **Sensor microburst timing is unknown.** Peak replay uses measured frame intervals and a uniform-within-frame native-word arrival model; physical within-frame arrivals are unavailable.
- **No trusted real pose ground truth exists.** Real recordings validate traffic behavior; inferred roll and map geometry are not ground truth.
- **Counter saturation is substantial.** The 4-bit ON/OFF counters are a configurable V1 default, and many contributions saturate.
- **FIFO_DEPTH=128 is an engineering default**, not a value derived from measured microburst timing.
- **Sept. 15 recording is absent from final recovered evidence.** Final real-data evidence covers the available Sept. 22 recordings.
- **CORDIC and direct-bin both have edge differences against the expanded Golden set.** CORDIC is retained based on integrated-system verification and timing closure; it is not exact on every expanded boundary vector.
- **Round 3 direct-bin is exploratory only.** The production baseline remains E-lite with CORDIC.
