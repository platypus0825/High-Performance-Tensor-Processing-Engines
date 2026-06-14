#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-0.59 0.6 0.65 0.7 0.75 0.8 0.9 1.0}"

for p in $PERIODS
do
  echo "Running top_pe_pipe_baseline period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_top_pe_pipe_baseline.tcl > "logs/dc_top_pe_pipe_baseline_${p}.log" 2>&1
done
