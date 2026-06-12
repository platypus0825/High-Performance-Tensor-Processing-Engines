#!/usr/bin/env bash
set -euo pipefail

vcs -full64 -sverilog -debug_access+all -f filelist.f -o simv
./simv
