#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-1.2 1.0 0.9 0.8 0.7 0.65 0.6 0.59 0.58 0.55}"
MODES="${MODES:-int fp}"

for mode in $MODES
do
  for p in $PERIODS
  do
    echo "Running opt4c_int_fp_mode_wrapper mode=${mode} period=${p} ns"
    MODE="$mode" CLK_PERIOD="$p" dc_shell -64bit -f dc_int_fp_wrapper.tcl > "logs/dc_int_fp_wrapper_${mode}_${p}.log" 2>&1
  done
done
