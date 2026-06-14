#!/bin/bash
set -e

vcs -sverilog -full64 -debug_access+all -f filelist_int_fp_wrapper_pipepe_int.f -o simv_int_fp_wrapper_pipepe_int
./simv_int_fp_wrapper_pipepe_int
