#!/bin/bash
set -e

vcs -sverilog -full64 -debug_access+all -f filelist_column_int_fp_wrapper_s23.f -o simv_column_int_fp_wrapper_s23
./simv_column_int_fp_wrapper_s23
