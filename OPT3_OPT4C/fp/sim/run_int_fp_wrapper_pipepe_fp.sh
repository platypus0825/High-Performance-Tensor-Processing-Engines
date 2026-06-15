#!/bin/bash
set -e

vcs -sverilog -full64 -debug_access+all -f filelist_int_fp_wrapper_pipepe_fp.f -o simv_int_fp_wrapper_pipepe_fp

run_args=""
if [ "${TRACE_PIPEPE_FP:-0}" != "0" ]; then
    run_args="+TRACE_PIPEPE_FP"
fi

./simv_int_fp_wrapper_pipepe_fp ${run_args}
