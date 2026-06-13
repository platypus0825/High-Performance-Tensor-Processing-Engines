#!/bin/bash
set -u

mkdir -p logs

TCL_SCRIPT="${TCL_SCRIPT:-dc_fp32_mul.tcl}"
PERIODS="${PERIODS:-12.0 10.0 8.0 6.0 5.0 4.0 3.0 2.5 2.0 1.8 1.6 1.4 1.2 1.0}"

for p in $PERIODS
do
  echo "Running fp32_mul_7bit_chunk period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f "$TCL_SCRIPT" > "logs/dc_fp32_${p}.log" 2>&1
done
