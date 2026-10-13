# Stage 4 transport-normalized baseline AER synthesis.
set LIBRARY_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib"
set TECH_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_tech.lef"
set MACRO_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_macro.lef"
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR [file dirname $SCRIPT_DIR]
set RESULT_DIR "$ROOT_DIR/results/baseline_link_power_hotspot0p8"

set_db init_lib_search_path [list [file dirname $LIBRARY_FILE]]
set_db library [list $LIBRARY_FILE]
set_db lef_library [list $TECH_LEF_FILE $MACRO_LEF_FILE]

read_hdl -sv [list \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_link_serializer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_packetizer.sv" \
    "$ROOT_DIR/rtl/baseline/aer_baseline_link_top.sv" \
]

elaborate aer_baseline_link_top

# Shared initial Stage 5 timing assumption.  Keep this identical in the
# adaptive script for an apples-to-apples comparison.
create_clock -name clk -period 10.0 [get_ports clk]

file mkdir $RESULT_DIR

syn_generic
syn_map
syn_opt
read_vcd -vcd_scope tb_stage4_compare.gen_baseline.dut "$ROOT_DIR/results/waves/power/baseline_hotspot0p8.vcd"

report_area   > "$RESULT_DIR/report_area.rpt"
report_power  > "$RESULT_DIR/report_power.rpt"
report_timing > "$RESULT_DIR/report_timing.rpt"
report_qor    > "$RESULT_DIR/report_qor.rpt"

write_hdl > "$RESULT_DIR/aer_baseline_link_top_netlist.v"
write_sdc > "$RESULT_DIR/aer_baseline_link_top.sdc"

exit
