#!/usr/bin/env bash
set -euo pipefail

vcs -full64 -sverilog -debug_access+all -f filelist_opt4c.f -o simv_opt4c
./simv_opt4c
