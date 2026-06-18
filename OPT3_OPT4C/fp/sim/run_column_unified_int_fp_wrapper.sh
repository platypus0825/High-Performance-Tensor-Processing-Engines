#!/bin/bash
set -e

vcs -sverilog -full64 -debug_access+all -f filelist_column_unified_int_fp_wrapper.f -o simv_column_unified_int_fp_wrapper
./simv_column_unified_int_fp_wrapper
