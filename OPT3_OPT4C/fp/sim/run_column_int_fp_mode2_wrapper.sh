#!/bin/bash
set -e

vcs -sverilog -full64 -debug_access+all -f filelist_column_int_fp_mode2_wrapper.f -o simv_column_int_fp_mode2_wrapper
./simv_column_int_fp_mode2_wrapper
