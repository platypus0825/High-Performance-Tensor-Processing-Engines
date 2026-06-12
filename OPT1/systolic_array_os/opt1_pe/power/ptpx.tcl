set my_corner "saed32rvt_tt0p85v25c"
set my_search_path "/apps/synopsys/syn_vS-2021.06-SP5/dw/sim_ver"
set my_target_library           "/home/chenhao/work/High-Performance-Tensor-Processing-Engines/library/${my_corner}.db"
set my_link_library             "* ${my_target_library} /apps/synopsys/syn_vS-2021.06-SP5/libraries/syn/dw_foundation.sldb"

set my_clk_period   
set netlist_period  1.5
set save_name      opt1_mac
set file_path "/home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT1/systolic_array_os/opt1_pe/syn/outputs/saed32rvt_tt0p85v25c"
set fsdb_path "/home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT1/systolic_array_os/opt1_pe/sim"
set my_strip_path "test_opt1_mac/opt1_mac_test"


set my_netlist_file "${file_path}/opt1_mac_netlist_${netlist_period}.v"
set my_current_design_name "opt1_mac"
set my_sdc_path "${file_path}/sdc_${netlist_period}.sdc"
set my_parasitics_path "${file_path}/para_${netlist_period}"
set my_fsdb "${fsdb_path}/test.fsdb"

############## parameters end ###############################################################################

set power_enable_analysis TRUE
# set power_enable_timing_analysis true
set power_analysis_mode time_based
set power_analysis_mode averaged


#####################################################################
#       link design
#####################################################################
set search_path $my_search_path
set link_library $my_link_library
set link_library [concat $link_library]


read_verilog		$my_netlist_file
current_design		$my_current_design_name
link

#####################################################################
#       set transition time / annotate parasitics
#####################################################################
read_sdc $my_sdc_path
read_parasitics $my_parasitics_path

report_annotated_parasitics
# #####################################################################
# #       check/update/report timing
# #####################################################################

create_clock clk -period $my_clk_period

report_clock
check_timing
update_timing
report_timing


#####################################################################
#       read switching activity file
#####################################################################
read_fsdb $my_fsdb -strip_path $my_strip_path
# set i 0
# foreach fsdb_file $my_fsdb_list {
#     set my_fsdb_path $fsdb_file
#     read_fsdb $my_fsdb_path -strip_path $my_strip_path
    
#     update_power
#     # report_power > "power_$i.rpt"
#     report_power > "power.rpt"
#     incr i
# }
report_power
#####################################################################
#       check/update/report power
#####################################################################
check_power
update_power
report_power > power_${save_name}_${my_clk_period}.rpt

quit