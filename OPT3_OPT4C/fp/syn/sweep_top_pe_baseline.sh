#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-1.2 1.0 0.9 0.8 0.7 0.65 0.6 0.59 0.58 0.55}"

for p in $PERIODS
do
  echo "Running top_pe baseline period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_top_pe_baseline.tcl > "logs/dc_top_pe_baseline_${p}.log" 2>&1
done
