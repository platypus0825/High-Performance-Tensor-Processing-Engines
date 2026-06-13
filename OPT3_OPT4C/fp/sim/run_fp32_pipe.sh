#!/usr/bin/env bash
set -euo pipefail

vcs -full64 -sverilog -debug_access+all -f filelist_fp32_pipe.f -o simv_fp32_pipe
./simv_fp32_pipe
