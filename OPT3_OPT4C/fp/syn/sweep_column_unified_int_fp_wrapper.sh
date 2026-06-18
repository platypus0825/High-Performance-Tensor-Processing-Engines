#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-2.5 3.0}"
MODES="${MODES:-int fp}"

for mode in $MODES
do
  for p in $PERIODS
  do
    echo "Running opt4c_column_unified_int_fp_wrapper mode=${mode} period=${p} ns"
    MODE="$mode" CLK_PERIOD="$p" dc_shell -64bit -f dc_column_unified_int_fp_wrapper.tcl > "logs/dc_column_unified_int_fp_wrapper_${mode}_${p}.log" 2>&1
  done
done
