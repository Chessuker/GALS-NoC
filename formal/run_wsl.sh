#!/bin/bash
# helper: run sby inside WSL with the OSS CAD Suite on PATH
#   wsl -d Ubuntu-24.04 -- bash formal/run_wsl.sh <file>.sby [tasks...]
set -e
if [ -f /opt/eda/oss-cad-suite/environment ]; then source /opt/eda/oss-cad-suite/environment; fi
export PATH=/opt/eda/oss-cad-suite/bin:$PATH
cd "$(dirname "$0")"
f="$1"; shift
sby -f "$f" "$@"
