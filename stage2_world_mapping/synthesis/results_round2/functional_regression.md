# Round 2 functional regression

## Result

- Numeric RTL regression: **PASS**. `run_numeric_tests.py` ran with Icarus 12.0 built locally under `/tmp`; all four benches passed. The mapper lane checked 8,064 vectors at **53 enabled edges**, and compared its valid output against a CE-frozen 53-edge reference on every cycle, including stalls. The separate isqrt, CORDIC, and ray2angle/world-quant benches passed 33,231, 66,462, and 33,231 vectors, respectively. Interpolation, angle, and world-address golden comparisons remain exact.
- System regression: **21/21 PASS**. All scenarios and build configurations in `verification/system/run_system_tests.py`'s `MATRIX`/`BUILDS` were run using Cadence Xcelium 23.09. Icarus 12.0 was also built locally, but its compiler does not support the testbench's existing `break` statement, so the system matrix was run with Xcelium without modifying or weakening the tests.
- Metadata alignment: **PASS**. The testbench's per-lane `v_out` versus metadata-valid assertions passed, including T06 with random CE stalls and input gaps.
- D2/E-lite memory identity: **PASS**. All 2,048 final tile words matched each other and the golden image in every system scenario.
- Event conservation, exact issue/event/record counters, saturation accounting, grid swap, bank hazards, FIFO/backpressure, clear, and real traffic subset: **PASS** across the matrix.

## Throughput and event accounting

On the real Sept22b subset with reuse enabled (T09), both architectures retain the same issue efficiency (0.914) and 21,870 issue cycles. E-lite remains at 3,207 bank conflicts, 8,871 merges, 17,622 RMW records, and 0.441 RMW/event. D2 remains at 16,957 bank conflicts, no merges, 40,000 RMW records, and 1.000 RMW/event. Compared with Round 1, D2 and E-lite cycle counts each increase by exactly one (33,565→33,566 and 22,245→22,246), the expected added fill/drain edge. Throughput and steady-state behavior are unchanged; II=1 is preserved.

The no-reuse/RD_LAT=3 real-traffic case also retains event efficiency, merge count, conflict count, and RMW/event; its cycle count increases by one over the prior result for that configuration, consistent with the added fill/drain edge.

## Lint

Verilator 4.228 `--lint-only -Wall` ran on both the pre-change snapshot and modified RTL. It reports the same three pre-existing WIDTH diagnostics in each run: one in `wm_ctrl_pkg.sv`'s existing `popcount8` addition and two at the existing `inflight` expression in `wm_world_mapper_top.sv`. No new WIDTH, latch, signedness, or undriven warnings were introduced by the Round 2 change. Other diagnostics are the existing UNUSED warnings. Verilator returns nonzero because this `-Wall` invocation treats warnings as fatal; baseline and modified warning logs are retained beside this report.

