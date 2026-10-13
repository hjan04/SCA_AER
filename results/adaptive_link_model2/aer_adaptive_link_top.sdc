# ####################################################################

#  Created by Genus(TM) Synthesis Solution 23.14-s090_1 on Sat Aug 22 15:13:56 KST 2026

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1000fF
set_units -time 1000ps

# Set the current design
current_design aer_adaptive_link_top

create_clock -name "clk" -period 10.0 -waveform {0.0 5.0} [get_ports clk]
set_clock_gating_check -setup 0.0 
