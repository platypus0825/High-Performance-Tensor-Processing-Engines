#!/bin/bash
set -u

mkdir -p logs

TCL_SCRIPT="${TCL_SCRIPT:-dc_array.tcl}"
ARRAY_NS="${ARRAY_NS:-16 32 64 128}"
PERIODS="${PERIODS:-1.4 1.2 1.0 0.9 0.8 0.7 0.65 0.6 0.59 0.58 0.55 0.53 0.5}"

for n in $ARRAY_NS
do
  for p in $PERIODS
  do
    echo "Running N=${n} period=${p} ns"
    rm -rf work
    ARRAY_N="$n" CLK_PERIOD="$p" dc_shell -64bit -f "$TCL_SCRIPT" > "logs/dc_n${n}_${p}.log" 2>&1
  done
done
