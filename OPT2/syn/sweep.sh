#!/bin/bash
set -u

mkdir -p logs

TCL_SCRIPT="${TCL_SCRIPT:-dc_array.tcl}"
PERIODS="${PERIODS:-3.0 2.5 2.0 1.8 1.6 1.4 1.2 1.0 0.9 0.8 0.7 0.6}"

for p in $PERIODS
do
  echo "Running period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f "$TCL_SCRIPT" > "logs/dc_${p}.log" 2>&1
done
