#!/usr/bin/env bash
# Compile the FPGA project. Run inside the Quartus VM, from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
quartus_sh --flow compile DE10_NANO_CRYPTO
echo
grep -E "Fitter Status|Logic utilization|Total pins|Total memory bits|Total RAM Blocks|Total PLLs" output_files/DE10_NANO_CRYPTO.fit.summary || true
