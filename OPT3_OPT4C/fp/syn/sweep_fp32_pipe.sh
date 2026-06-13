#!/bin/bash
set -u

mkdir -p logs

PERIODS="${PERIODS:-4.0 3.5 3.0 2.8 2.7 2.65 2.6 2.4 2.2 2.0}"

for p in $PERIODS
do
  echo "Running fp32_mul_7bit_chunk_pipe period=${p} ns"
  CLK_PERIOD="$p" dc_shell -64bit -f dc_fp32_mul_pipe.tcl > "logs/dc_fp32_pipe_${p}.log" 2>&1
done
