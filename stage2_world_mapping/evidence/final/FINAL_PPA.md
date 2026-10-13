# Final Stage 2 PPA evidence

The frozen V1 baseline is the Round 2 E-lite MODE1 implementation at 100 MHz. This is the mapped logic result with the grid and world memory arrays black-boxed. Genus used the GPDK045 slow library at PVT_0P9V_125C, 10 ns clock, 0.2 ns uncertainty, 0.10 ns input transition, 1 ns input/output delays, and 0.001571432 output load. There is no placed clock tree or CTS power.

| Design | Cell area | Net area | Total area | WNS | TNS | Violating paths | Vectorless power |
|---|---:|---:|---:|---:|---:|---:|---:|
| D2 | 447,464.934 | 168,887.663 | 616,352.597 | 0 ps | 0 ps | 0 | 33.3356 mW |
| E-lite | 493,230.690 | 184,654.824 | 677,885.514 | 0 ps | 0 ps | 0 | 36.8067 mW |

Timing closes at 100 MHz. The critical paths are the Round 2 registered `wm_lerp` outputs into the `ray_z_reg` stage. E-lite is the frozen selected implementation because it reduces measured real-subset cycles by 33.7%, mapper stalls by 99.5%, and bank conflicts by 81.1%, despite the area and vectorless-power overhead.

Do not describe the vectorless values as activity power. The activity-based comparison was attempted but failed the annotation coverage gate; there are no accepted D2/E-lite activity-power or energy/event values. See [ACTIVITY_POWER.md](ACTIVITY_POWER.md). These PPA results are pre-layout logic power; the large memory arrays and a real clock tree are excluded.

Sources: `synthesis/results_round2/ppa_summary.csv`, Round 2 Genus reports in `synthesis/results_round2/d2_100MHz/` and `synthesis/results_round2/elite_100MHz/`.
