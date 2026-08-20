# Stage 5 Fmax sweep - adaptive, tighter period (9.3ns)
set LIBRARY_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib"
set TECH_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_tech.lef"
set MACRO_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_macro.lef"
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR [file dirname $SCRIPT_DIR]
set RESULT_DIR "$ROOT_DIR/results/adaptive_link_9p3"
set_db init_lib_search_path [list [file dirname $LIBRARY_FILE]]
set_db library [list $LIBRARY_FILE]
set_db lef_library [list $TECH_LEF_FILE $MACRO_LEF_FILE]
read_hdl -sv [list \
    "$ROOT_DIR/rtl/common/aer_event_capture.sv" \
    "$ROOT_DIR/rtl/common/rr_arbiter.sv" \
    "$ROOT_DIR/rtl/common/aer_link_serializer.sv"\
    "$ROOT_DIR/rtl/baseline/aer_row_col_arbiter.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_sparse_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_packetizer.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_block_occupancy.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_dense_block_selector.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_mode_controller.sv" \
    "$ROOT_DIR/rtl/adaptive/aer_adaptive_link_top.sv" \
]
elaborate aer_adaptive_link_top
# Fmax sweep point: tighter than the 10.0ns baseline run (which had +0.6ns slack).
create_clock -name clk -period 9.3 [get_ports clk]
file mkdir $RESULT_DIR
syn_generic
syn_map
syn_opt
report_area   > "$RESULT_DIR/report_area.rpt"
report_power  > "$RESULT_DIR/report_power.rpt"
report_timing > "$RESULT_DIR/report_timing.rpt"
report_qor    > "$RESULT_DIR/report_qor.rpt"
write_hdl > "$RESULT_DIR/aer_adaptive_link_top_netlist.v"
write_sdc > "$RESULT_DIR/aer_adaptive_link_top.sdc"
exit
