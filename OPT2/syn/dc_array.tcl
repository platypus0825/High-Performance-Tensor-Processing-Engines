set my_corner "saed32rvt_tt0p85v25c"
################## parameters begin #################
if {![file isdirectory "work"]} {
    file mkdir "work"
    puts "Directory 'work' created."
} else {
    puts "Directory 'work' already exists. No action taken."
}
if {![file isdirectory "outputs_array"]} {
    file mkdir "outputs_array"
}
if {![file isdirectory "outputs_array/${my_corner}"]} {
    file mkdir "outputs_array/${my_corner}"
}
define_design_lib work -path ./work

# set_host_options -max_cores 1

set my_verilog_list  "filelist.f"
set my_current_design_name      top_tpe
set my_current_file_name        top_tpe_n16
set my_search_path              "/apps/synopsys/syn_vS-2021.06-SP5/dw/sim_ver"
set my_target_library           "/home/chenhao/work/High-Performance-Tensor-Processing-Engines/library/${my_corner}.db"
set my_link_library             "* ${my_target_library} /apps/synopsys/syn_vS-2021.06-SP5/libraries/syn/dw_foundation.sldb"
set my_clk_list {
                                "clk"
}
if {[info exists ::env(CLK_PERIOD)]} {
    set my_clk_period $::env(CLK_PERIOD)
} else {
    set my_clk_period               1.45
}
set my_constrain_list {
}
set my_output_netlist_name      ${my_current_file_name}_netlist
set my_output_sdf_name          sdf
set my_output_sdc_name          sdc
set my_output_parasitics_name   para

# set_multicycle_path 
# set_false_path 
# set_max_delay 

##################### parameters end ############

set search_path $my_search_path
set target_library $my_target_library
set link_library $my_link_library
set link_library [concat $link_library]

set fp [open $my_verilog_list r]
set files [split [read $fp] "\n"]
close $fp
foreach file $files {
    if {[string trim $file] != ""} {
        analyze -format sverilog $file
    }
}

elaborate $my_current_design_name
current_design $my_current_design_name
link

check_design

foreach clk_name_i $my_clk_list {
    create_clock $clk_name_i -period $my_clk_period
}

foreach constrain_i $my_constrain_list {
    eval $constrain_i
}

# report_clock
# compile_ultra -no_autoungroup
# report_timing   > ./outputs_array/${my_corner}/timing_report_${my_clk_period}.txt
# report_area -hierarchy     > ./outputs_array/${my_corner}/area_report_${my_clk_period}.txt

# set_dont_touch {core}
# set_dont_touch [get_cells -hierarchical -filter "ref_name == top_pe_tile"]

report_clock
compile_ultra -retime
report_timing   > ./outputs_array/${my_corner}/${my_current_file_name}_timing_report_${my_clk_period}.txt
report_timing -delay_type max -max_paths 10 -nets -transition_time -capacitance > ./outputs_array/${my_corner}/${my_current_file_name}_timing_top10_${my_clk_period}.txt
report_area  -hierarchy   > ./outputs_array/${my_corner}/${my_current_file_name}_area_report_${my_clk_period}.txt
report_power    > ./outputs_array/${my_corner}/${my_current_file_name}_power_report_${my_clk_period}.txt
report_constraint -all_violators > ./outputs_array/${my_corner}/${my_current_file_name}_constraint_violators_${my_clk_period}.txt

write_file -f verilog -hierarchy -o ./outputs_array/${my_corner}/${my_output_netlist_name}_${my_clk_period}.v
write_sdf ./outputs_array/${my_corner}/${my_output_sdf_name}_${my_clk_period}.sdf
write_sdc ./outputs_array/${my_corner}/${my_output_sdc_name}_${my_clk_period}.sdc
write_parasitics -format reduced -output ./outputs_array/${my_corner}/${my_output_parasitics_name}_${my_clk_period}
quit

