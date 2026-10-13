# Stage 2 V1 world mapper - Cadence Genus synthesis (PREPARED, NOT YET RUN).
#
# Driven by environment variables (see run_genus_sweep.sh):
#   WM_CONFIG  = D2 | ELITE        -> MERGE_EN 0 | 1 (only difference)
#   WM_MODE    = 1 | 2             -> 1: memories black-boxed (primary PPA)
#                                     2: memories inferred (diagnostic only)
#   WM_PERIOD  = clock period, ns  -> 10.0 (100 MHz, primary) / 6.667 / 5.0
#   WM_OUT     = result directory
# Library setup copied from the Stage 1 GPDK045 flow (slow corner 0.9 V/125 C).

set LIBRARY_FILE   "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib"
set TECH_LEF_FILE  "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_tech.lef"
set MACRO_LEF_FILE "/tools/config/GPDK/gsclib045_svt_v4.7/gsclib045/lef/gsclib045_macro.lef"

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR   [file dirname $SCRIPT_DIR]
set CONFIG $::env(WM_CONFIG)
set MODE   $::env(WM_MODE)
set PERIOD $::env(WM_PERIOD)
set OUT    $::env(WM_OUT)
file mkdir $OUT

switch -- $CONFIG {
  D2    { set MERGE_EN 0 }
  ELITE { set MERGE_EN 1 }
  default { puts "ERROR: WM_CONFIG must be D2 or ELITE"; exit 1 }
}
set FLIST [expr {$MODE == 1 ? "$ROOT_DIR/scripts/synth_mode1.f" : "$ROOT_DIR/scripts/synth_mode2.f"}]

# ---------------------------------------------------------------- library
set_db init_lib_search_path [list [file dirname $LIBRARY_FILE]]
set_db library     [list $LIBRARY_FILE]
set_db lef_library [list $TECH_LEF_FILE $MACRO_LEF_FILE]

# Keep hierarchy so area/power can be attributed per block (lanes, isqrt,
# CORDICs, merger, router, banks, control). Do not flatten in diagnostics.
set_db auto_ungroup none

# ---------------------------------------------------------------- read RTL
set files {}
set fh [open $FLIST r]
while {[gets $fh line] >= 0} {
  set line [string trim $line]
  if {$line eq "" || [string match "//*" $line]} continue
  lappend files "$ROOT_DIR/$line"
}
close $fh
read_hdl -sv -define SYNTHESIS $files

# MERGE_EN is the ONLY configuration difference between D2 and E-lite.
# All other parameters stay at their RTL defaults:
#   REUSE_EN=1 FIFO_DEPTH=128 OUTBUF_DEPTH=4 BQ_DEPTH=4 RD_LAT=1
elaborate wm_world_mapper_top -parameters [list [list MERGE_EN $MERGE_EN]]

# MODE 1 sanity: the stubs must be black boxes (no cells inside).
if {$MODE == 1} {
  foreach m {wm_grid_store wm_world_mem_model} {
    set mods [get_db modules -if ".name==$m*"]
    puts "BLACKBOX-CHECK $m modules=[llength $mods]"
  }
}
check_design -unresolved > "$OUT/check_design.rpt"

# ---------------------------------------------------------------- constraints
# Identical for D2 and E-lite. I/O delay = 10 % of the period (1.0 ns at
# 100 MHz, as in the Stage 1 implementation-output constraint set).
set IO_DLY [expr {0.1 * $PERIOD}]
create_clock -name clk -period $PERIOD [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set in_ports [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay  $IO_DLY -clock clk $in_ports
set_input_transition 0.10 $in_ports
set_output_delay $IO_DLY -clock clk [all_outputs]
set_load 0.001571432 [all_outputs]

# ---------------------------------------------------------------- synthesize
syn_generic
syn_map
syn_opt

# ---------------------------------------------------------------- reports
report_area -depth 6                 > "$OUT/report_area_hier.rpt"
report_area                           > "$OUT/report_area.rpt"
report_gates                          > "$OUT/report_gates.rpt"
report_timing -nworst 10              > "$OUT/report_timing.rpt"
report_qor                            > "$OUT/report_qor.rpt"
report_power -depth 6                 > "$OUT/report_power_hier.rpt"
report_power                          > "$OUT/report_power.rpt"
foreach h {u_lane0 u_lane1 u_merge u_router u_reuse u_frame u_unpack u_fifo u_outbuf u_status} {
  catch { report_area [get_db hinsts *$h] >> "$OUT/report_area_blocks.rpt" }
}
write_hdl > "$OUT/wm_world_mapper_top_${CONFIG}_mode${MODE}.v"
write_sdc > "$OUT/wm_world_mapper_top_${CONFIG}_mode${MODE}.sdc"
puts "DONE config=$CONFIG mode=$MODE period=$PERIOD"
exit
