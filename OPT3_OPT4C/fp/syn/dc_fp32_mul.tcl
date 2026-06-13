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

set my_verilog_list          "filelist_fp32.f"
set my_current_design_name   fp32_mul_7bit_chunk
set my_current_file_name     fp32_mul_7bit_chunk
set my_search_path           "/apps/synopsys/syn_vS-2021.06-SP5/dw/sim_ver"
set my_target_library        "/home/chenhao/work/High-Performance-Tensor-Processing-Engines/library/${my_corner}.db"
set my_link_library          "* ${my_target_library} /apps/synopsys/syn_vS-2021.06-SP5/libraries/syn/dw_foundation.sldb"

if {[info exists ::env(CLK_PERIOD)]} {
    set my_clk_period $::env(CLK_PERIOD)
} else {
    set my_clk_period 5.0
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

# This top is combinational. Use a virtual clock to constrain input-to-output delay.
create_clock -name vclk -period $my_clk_period
set input_delay_value  [expr {$my_clk_period * 0.10}]
set output_delay_value [expr {$my_clk_period * 0.10}]
set_input_delay  $input_delay_value  -clock vclk [all_inputs]
set_output_delay $output_delay_value -clock vclk [all_outputs]
set_max_delay $my_clk_period -from [all_inputs] -to [all_outputs]

compile_ultra

report_timing > ./outputs_fp32/${my_corner}/${my_current_file_name}_timing_report_${my_clk_period}.txt
report_timing -delay_type max -max_paths 10 -nets -transition_time -capacitance > ./outputs_fp32/${my_corner}/${my_current_file_name}_timing_top10_${my_clk_period}.txt
report_area -hierarchy > ./outputs_fp32/${my_corner}/${my_current_file_name}_area_report_${my_clk_period}.txt
report_constraint -all_violators > ./outputs_fp32/${my_corner}/${my_current_file_name}_constraint_violators_${my_clk_period}.txt

# Keep netlist writing disabled by default to avoid large generated files in Git.
# write_file -f verilog -hierarchy -o ./outputs_fp32/${my_corner}/${my_current_file_name}_netlist_${my_clk_period}.v

quit
