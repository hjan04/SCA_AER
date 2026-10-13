# Stage 1 successful activity-power flow reference

Inspected Stage 1 scripts:

- `~/SCA_AER/scripts/genus_adaptive_link_model2_power_uniform0p8.tcl`
- `~/SCA_AER/scripts/genus_adaptive_link_model2_power_burst2_dur500.tcl`
- `~/SCA_AER/scripts/genus_baseline_link_power_uniform0p8.tcl`
- `~/SCA_AER/scripts/genus_baseline_link_power_burst2_dur500.tcl`

The two adaptive scripts are structurally identical except for result directory and VCD filename. The baseline pair follows the same pattern with the baseline top. Each script sets the same GPDK045 slow library, reads that design's RTL, elaborates the production top, creates a 10 ns clock, runs `syn_generic`, `syn_map`, and `syn_opt`, then calls `read_vcd -vcd_scope <testbench DUT instance> <VCD>` in the same Genus process and same synthesis session. Only then does it run `report_power`; it also writes area/timing/QoR reports and the mapped netlist/SDC.

The recorded VCD was produced by the matching Stage 1 testbench hierarchy (`tb_stage4_compare.gen_adaptive.dut` or `tb_stage4_compare.gen_baseline.dut`). Genus logs confirm it parsed that hierarchy with `design_root` equal to the corresponding elaborated RTL top, then propagated the stimulus to the mapped netlist. This is the critical distinction from the failed Stage 2 attempt: Stage 2 read SAIF into an independently elaborated mapped netlist and lacked the live synthesis correspondence. Stage 1 did not use SAIF, a separate netlist reload, or a name-map file. It used Cadence Xcelium VCD plus Genus/Joules `read_vcd` directly after mapping.

The Stage 1 log also shows Genus warning `STIM-0551` that `RTLStim2Gate` was off for RTL stimulus, while its annotation report still showed 100% primary inputs, 100% primary outputs (one unconnected output), 96.04% flop outputs, and 96.21% RTL driver nets. Gate-level driver coverage was only 27.34%. Thus, the successful precedent is specifically same-session RTL activity propagation with high RTL-object coverage and near-complete primary/flop annotation, not a blanket claim that every mapped internal net is directly annotated. Power is reported by Joules through `report_power` after activity propagation.

Primary evidence:

- `~/SCA_AER/scripts/genus_adaptive_link_model2_power_uniform0p8.tcl`
- `~/SCA_AER/scripts/genus_adaptive_link_model2_power_burst2_dur500.tcl`
- `~/SCA_AER/results/raw/power/genus_model2_uniform0p8_activity.log`
- `~/SCA_AER/results/raw/power/genus_model2_burst2_dur500_activity.log`
- `~/SCA_AER/results/raw/power/genus_baseline_uniform0p8_activity.log`
- `~/SCA_AER/results/raw/power/genus_baseline_burst2_dur500_activity.log`
- Matching `~/SCA_AER/results/waves/power/*.vcd` and `results/*_power_*/report_power.rpt`

Stage 1 was inspected read-only and was not modified.


## Genus 23.14 documented mapping options checked for Stage 2

The installed Joules guide `GENUS231/doc/joules_ug_cui/Recommended_RTL_Stimulus_to_Gating_Flow.html` documents `write_db` of an elaborated RTL design, `set_rtl_stim_to_gate_config -init <elab.db> -keep_libraries`, then loading the mapped netlist and using `read_stimulus`. The guide says post-synthesis netlist flows need suitable naming rules; `set_rtl_stim_to_gate_config -infer_rules` is available for netlist flows. The Stage 2 experiment followed these steps, additionally enabled `stim_auto_mapping`, and read VCD with `-resim_cg_enables`. The call completed without the prior `STIM-0551`, and ports/flops mapped well, but driver-net annotation stayed at 19.87%. The exact blocker and rejected result are in [ACTIVITY_POWER.md](ACTIVITY_POWER.md).

Compact copies of the inspected Stage 1 Tcl scripts and four matching Joules reports are preserved under `stage1_power_reference/`. The uniform and burst activity reports contain nonzero switching and internal power components across register, logic, and clock categories, corroborating that these are activity-based Joules reports. Their Stage 1 power values are not comparable to Stage 2 and are retained only to show the flow produced reports from mapped designs.
