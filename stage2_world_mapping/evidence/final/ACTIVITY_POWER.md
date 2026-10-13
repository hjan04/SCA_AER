# Activity-based D2 / E-lite power closure

## Workload captures

The measurement-only single-DUT bench drove the same 40,000-event Sept22b subset, 8,742 native words, synthetic frame convention, and 10 ns clock separately through D2 (`MERGE_EN=0`) and E-lite (`MERGE_EN=1`). Both runs passed and dropped zero events. The run summary is in `simulation_window.csv`; D2 completed its post-grid input-to-drain interval in 33,314 cycles (testbench status counter 34,304), and E-lite in 21,994 cycles (status counter 22,984). Saturation was 31,348 contributions in both. VCDs are single-DUT scopes from time 0 through drain: 0–348,215 ns for D2 and 0–235,015 ns for E-lite. Both preserve a 10 ns clock. No production RTL was changed.

Capture method: Xcelium 23.09, testbench `$dumpfile` / `$dumpvars(0,dut)`, using `activity_power/tb_single_dut_vcd.sv`; full logs are `activity_power/logs/d2_vcd.log` and `elite_vcd.log`. `activity_power/vcd/d2.vcd.gz` and `elite.vcd.gz` are the losslessly compressed captured traces; gunzip them to feed the documented Genus commands. The earlier SAIF attempt remains preserved but was not accepted.

## Stage 1 method inspected

The successful Stage 1 scripts read RTL, elaborate, synthesize/map/optimize, then read a VCD in Genus/Joules using the matching testbench DUT hierarchy. The Stage 1 log reported 100% primary inputs, 100% connected outputs, 96.04% flop outputs, 96.21% RTL driver nets, and 27.34% mapped driver nets. Exact scripts, logs, hierarchy, and commands are documented in [STAGE1_POWER_FLOW_REFERENCE.md](STAGE1_POWER_FLOW_REFERENCE.md). Stage 1 was inspected read-only.

## Stage 2 mapping diagnosis and stop

The original Stage 2 SAIF attempt loaded stimulus into a separately elaborated frozen netlist. It warned that `RTLStim2Gate` was off and reported 19.36% driver-net coverage and 1.05% output coverage; those numbers were rejected.

A Stage 1-style same-session RTL/VCD run was then executed with the matching top hierarchy. It still warned `STIM-0551` (`RTLStim2Gate` off), emitted warnings for asserted stimulus on undriven hierarchical pins, and reported:

| Object class | Annotated / total | Coverage |
|---|---:|---:|
| Primary inputs | 81 / 129 | 62.79% |
| Primary outputs | 7 / 775 | 1.05% |
| Flop outputs | 21,293 / 23,429 | 90.88% |
| Driver nets | 23,788 / 113,792 | 20.90% |
| RTL driver nets | 23,676 / 46,478 | 50.94% |

The installed Genus 23.14 Joules guide identifies `set_rtl_stim_to_gate_config -init <elab_db>` before loading the mapped netlist, followed by `read_stimulus` with RTLStim2Gate enabled, as the netlist-based flow. I followed that flow using the frozen Round 2 mapped D2 netlist, generated a clean elaborated DB (`reset_naming_rules` before `elaborate`), enabled `stim_auto_mapping`, and invoked the documented `-infer_rules`. The stimulus read completed without `STIM-0551`, and port/flop annotation improved substantially:

| Object class | Annotated / total | Coverage |
|---|---:|---:|
| Primary inputs | 127 / 129 | 98.44% |
| Connected primary outputs | 661 / 661 | 100.00% (114 additional outputs were unconnected) |
| Flop outputs | 26,653 / 28,027 | 95.09% |
| Driver nets | 29,260 / 147,333 | 19.87% |
| RTL driver nets | 29,133 / 147,204 | 19.80% |

The mapping report says 434,905 signals were present in the VCD, 401,475 were not present in the mapped design, and 29,040 were annotated. This is consistent with the remaining low driver-net coverage. The gate-driver annotation remains near the earlier 19.36% result, which the measurement gate explicitly treats as unacceptable. Therefore the Joules power reports produced during these attempts are **not accepted** and must not be used as D2 power or energy evidence. The E-lite Genus activity run was not launched after D2 failed the coverage gate.

The exact RTLStim2Gate command and activity log are in `activity_power/genus_rtlstim2gate.tcl`, `activity_power/genus_rtlstim2gate_read.tcl`, `activity_power/genus_d2_rtlstim2gate_v4/genus.log`, and `activity_power/genus_d2_rtlstim2gate_v4/missing_signals.rpt.gz`; the attempted report is retained only as rejected diagnostic output. See [STAGE1_POWER_FLOW_REFERENCE.md](STAGE1_POWER_FLOW_REFERENCE.md) and the installed Genus 23.14 Joules guides under `/tools/cadence/DDI231/GENUS231/doc/joules_ug_cui/` for the documented command syntax.

## Accepted result

No valid Stage 2 activity-based power result was obtained. D2 and E-lite activity-based power, dynamic power, leakage power, and energy/event are **unavailable**. The invalid report files under `activity_power/genus_d2_same_session/` and `activity_power/genus_d2_rtlstim2gate*/` are retained for traceability only; none is a measurement result. Vectorless Round 2 power remains separate: D2 33.3356 mW and E-lite 36.8067 mW. This experiment does not settle whether E-lite improves energy/event. All power evidence is pre-layout logic-only; MODE1 black-boxes the 71,424-bit grid and 262,144-bit world memories, and no real post-CTS clock tree is modeled.
