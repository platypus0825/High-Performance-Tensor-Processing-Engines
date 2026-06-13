#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-3.0 2.5 2.2 2.0 1.8 1.6 1.4 1.2}"

for p in $PERIODS
do
  echo "Running fp32_mul_7bit_chunk_pipe4 period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_fp32_mul_pipe4.tcl > "logs/dc_fp32_pipe4_${p}.log" 2>&1
done
