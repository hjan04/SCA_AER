set LIBRARY_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib"
set TECH_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_tech.lef"
set MACRO_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_macro.lef"
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR [file dirname [file dirname $SCRIPT_DIR]]
set TOP $::env(TOP)
set OUT $::env(OUT)
file mkdir $OUT
set_db init_lib_search_path [list [file dirname $LIBRARY_FILE]]
set_db library [list $LIBRARY_FILE]
set_db lef_library [list $TECH_LEF_FILE $MACRO_LEF_FILE]
set_db auto_ungroup none
set RTL_LIST [split $::env(RTL_FILES)]
read_hdl -sv -define SYNTHESIS $RTL_LIST
elaborate $TOP
check_design -unresolved > "$OUT/check_design.rpt"
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set in_ports [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay 1.0 -clock clk $in_ports
set_input_transition 0.10 $in_ports
set_output_delay 1.0 -clock clk [all_outputs]
set_load 0.001571432 [all_outputs]
syn_generic
syn_map
syn_opt
report_area -depth 6 > "$OUT/report_area_hier.rpt"
report_area > "$OUT/report_area.rpt"
report_gates > "$OUT/report_gates.rpt"
report_timing -nworst 20 > "$OUT/report_timing.rpt"
report_qor > "$OUT/report_qor.rpt"
report_power > "$OUT/report_power.rpt"
write_hdl > "$OUT/${TOP}.v"
write_sdc > "$OUT/${TOP}.sdc"
exit
