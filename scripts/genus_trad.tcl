set_db init_lib_search_path { <표준셀_라이브러리_경로> }
set_db library { <표준셀_라이브러리_이름>.lib }

read_hdl -sv { ../rtl/aer_tx_traditional.v ../rtl/aer_rx_traditional.v }
elaborate aer_tx_traditional

read_sdc ./aer_trad.sdc

syn_generic
syn_map
syn_opt

mkdir -p ../results/trad
report_area   > ../results/trad/report_area.rpt
report_power  > ../results/trad/report_power.rpt
report_timing > ../results/trad/report_timing.rpt
report_qor    > ../results/trad/report_qor.rpt

write_hdl > ../results/trad/aer_tx_traditional_netlist.v
write_sdc > ../results/trad/aer_tx_traditional.sdc

exit