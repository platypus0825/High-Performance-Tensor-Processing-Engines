#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-0.59 0.6 0.65 0.7 0.75 0.8 0.9 1.0}"
MODES="${MODES:-int}"

for mode in $MODES
do
  for p in $PERIODS
  do
    echo "Running opt4c_int_fp_mode_wrapper_pipepe mode=${mode} period=${p} ns"
    MODE="$mode" CLK_PERIOD="$p" dc_shell -64bit -f dc_int_fp_wrapper_pipepe.tcl > "logs/dc_int_fp_wrapper_pipepe_${mode}_${p}.log" 2>&1
  done
done
