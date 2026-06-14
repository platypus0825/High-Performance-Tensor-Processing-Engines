set my_corner "saed32rvt_tt0p85v25c"

if {![file isdirectory "work"]} {
    file mkdir "work"
}
if {![file isdirectory "outputs_fp32"]} {
    file mkdir "outputs_fp32"
}
if {![file isdirectory "outputs_fp32/${my_corner}"]} {
    file mkdir "outputs_fp32/${my_corner}"
}

define_design_lib work -path ./work

set my_verilog_list          "filelist_int_fp_wrapper_pipepe.f"
set my_current_design_name   opt4c_int_fp_mode_wrapper
set my_current_file_name     opt4c_int_fp_mode_wrapper_pipepe_intfirst_int
set my_search_path           "/apps/synopsys/syn_vS-2021.06-SP5/dw/sim_ver"
set my_target_library        "/home/chenhao/work/High-Performance-Tensor-Processing-Engines/library/${my_corner}.db"
set my_link_library          "* ${my_target_library} /opt/Synopsys/syn/R-2020.09-SP4/libraries/syn/dw_foundation.sldb"

if {[info exists ::env(CLK_PERIOD)]} {
    set my_clk_period $::env(CLK_PERIOD)
} else {
    set my_clk_period 0.59
}

set search_path $my_search_path
set target_library $my_target_library
set link_library [concat $my_link_library]

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

create_clock -name clk -period $my_clk_period [get_ports clk]
set input_delay_value  [expr {$my_clk_period * 0.10}]
set output_delay_value [expr {$my_clk_period * 0.10}]

set input_ports [remove_from_collection [all_inputs] [get_ports clk]]
set input_ports [remove_from_collection $input_ports [get_ports rst_n]]
set_input_delay  $input_delay_value  -clock clk $input_ports
set_output_delay $output_delay_value -clock clk [all_outputs]
set_false_path -from [get_ports rst_n]

# INT-first diagnostic: unlike dc_int_fp_wrapper_pipepe.tcl, constrain mode_fp
# before compile so inactive FP scheduler/accumulator logic is constant-folded
# out of the active-mode timing problem. Use this to find the true INT-mode
# critical path; do not use its area as the full dual-mode wrapper area.
set_case_analysis 0 [get_ports mode_fp]
set_false_path -from [get_ports fp_*]
set_false_path -to [get_ports fp_*]

compile_ultra -retime

report_timing > ./outputs_fp32/${my_corner}/${my_current_file_name}_timing_report_${my_clk_period}.txt
report_timing -delay_type max -max_paths 10 -nets -transition_time -capacitance > ./outputs_fp32/${my_corner}/${my_current_file_name}_timing_top10_${my_clk_period}.txt
report_area -hierarchy > ./outputs_fp32/${my_corner}/${my_current_file_name}_area_report_${my_clk_period}.txt
report_constraint -all_violators > ./outputs_fp32/${my_corner}/${my_current_file_name}_constraint_violators_${my_clk_period}.txt

quit
