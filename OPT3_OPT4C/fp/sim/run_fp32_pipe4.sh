#!/usr/bin/env bash
set -euo pipefail

vcs -full64 -sverilog -debug_access+all -f filelist_fp32_pipe4.f -o simv_fp32_pipe4
./simv_fp32_pipe4
