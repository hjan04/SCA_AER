# Stage 5 Genus synthesis - model2 (hysteresis), implementation-output SDC
# Reconstructed to match docx section 7.1 conditions:
#   clock 10.0ns (100MHz), uncertainty 0.2ns
#   input delay 1.0ns / input transition 0.10ns on all inputs
#   output delay 1.0ns / load 0.001571432pF on link_valid_o, link_data_o[*], busy_o only
# NOTE: original "implementation-output" script (used for Model1's 24,246.490 um2
# result) was not authored by us - this is a best-effort reconstruction from the
# documented I/O assumption table. Verify against the original if it becomes available.

set LIBRARY_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib"
set TECH_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_tech.lef"
set MACRO_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_macro.lef"
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR [file dirname $SCRIPT_DIR]
set RESULT_DIR "$ROOT_DIR/results/adaptive_link_model2_implout"

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

create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]

# Input constraints: all inputs except clk/rst_n
set all_inputs_no_clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay 1.0 -clock clk $all_inputs_no_clk
set_input_transition 0.10 $all_inputs_no_clk

# Output constraints: ONLY the real physical-link outputs (not debug/metric ports)
set link_outputs [get_ports {link_valid_o link_data_o* busy_o}]
set_output_delay 1.0 -clock clk $link_outputs
set_load 0.001571432 $link_outputs

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