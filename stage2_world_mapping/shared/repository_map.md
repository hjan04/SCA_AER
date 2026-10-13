# Existing repository map

Paths below are existing Stage 1 assets. They are listed for reference only and
remain in their current locations.

- **Traffic-Adaptive Hybrid AER (Model2) design/specification:**
  `docs/traffic_adaptive_hybrid_aer_v0.2.md`
- **Hybrid RTL:** `rtl/aer_tx_hybrid.sv`
- **Adaptive architecture RTL:** `rtl/adaptive/`
- **Hybrid testbench and runner:** `tb/tb_aer_tx_hybrid.sv`,
  `scripts/run_hybrid_sim.sh`
- **Adaptive and link testbenches:** `tb/tests/`
- **Traffic trace driver and generators:** `tb/traffic/tb_trace_driver.sv`,
  `scripts/sweep_baseline_traffic.py`, `scripts/sweep_adaptive_stage3.py`,
  `scripts/sweep_stage4.py`
- **Genus synthesis scripts:** `scripts/genus_*.tcl`
- **Genus environment documentation:** `docs/genus_environment.md`
- **Genus reports and netlists:** `results/baseline_link/`,
  `results/baseline_link_9p7/`, `results/adaptive_link/`,
  `results/adaptive_link_9p3/`
- **Compact benchmark summaries:** `results/csv/baseline_summary.csv`,
  `results/csv/adaptive_stage3_summary.csv`, `results/csv/stage4_summary.csv`
- **Stage 1 reports and evidence:** `1차 보고서/` (currently untracked local
  material; left untouched)
- **Competition Stage 2 preparation material:** `2차-preparations/` (currently
  untracked local material; left untouched)

Generated traces, per-run outputs, and simulator artifacts also exist under
`traces/generated/` and `results/`; those directories are not modified here.
