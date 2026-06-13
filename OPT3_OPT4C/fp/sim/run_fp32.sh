#!/usr/bin/env bash
set -euo pipefail

vcs -full64 -sverilog -debug_access+all -f filelist_fp32.f -o simv_fp32
./simv_fp32
