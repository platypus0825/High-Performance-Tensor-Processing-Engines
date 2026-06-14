#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-1.5 2.0 2.5 3.0 4.0 5.0}"

for p in $PERIODS
do
  echo "Running opt4c_int_fp_mode_wrapper_pipepe_fpclean_fp period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_int_fp_wrapper_pipepe_fpclean.tcl > "logs/dc_int_fp_wrapper_pipepe_fpclean_fp_${p}.log" 2>&1
done
