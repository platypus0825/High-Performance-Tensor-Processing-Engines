#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-0.59 0.6 0.65 0.7 0.75 0.8 0.9 1.0}"

for p in $PERIODS
do
  echo "Running opt4c_int_fp_mode_wrapper_pipepe_intclean_int period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_int_fp_wrapper_pipepe_intclean.tcl > "logs/dc_int_fp_wrapper_pipepe_intclean_int_${p}.log" 2>&1
done
