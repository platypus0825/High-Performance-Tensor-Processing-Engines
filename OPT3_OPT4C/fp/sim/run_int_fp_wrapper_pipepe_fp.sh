#!/bin/bash
set -e

vcs -sverilog -full64 -debug_access+all -f filelist_int_fp_wrapper_pipepe_fp.f -o simv_int_fp_wrapper_pipepe_fp
./simv_int_fp_wrapper_pipepe_fp
