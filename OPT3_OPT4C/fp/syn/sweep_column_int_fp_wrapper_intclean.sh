#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-0.48 0.50 0.52 0.53 0.55 0.59 0.65}"

for p in $PERIODS
do
  echo "Running opt4c_column_int_fp_mode_wrapper_intclean_int period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_column_int_fp_wrapper_intclean.tcl > "logs/dc_column_int_fp_wrapper_intclean_int_${p}.log" 2>&1
done
