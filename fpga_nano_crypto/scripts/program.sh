#!/usr/bin/env bash
# Program the FPGA over JTAG (USB-Blaster on the DE10-Nano's mini-USB port).
# Run inside the Quartus VM. The FPGA is the 2nd device in the JTAG chain.
set -euo pipefail
cd "$(dirname "$0")/.."
quartus_pgm -m jtag -c 1 -o "p;output_files/DE10_NANO_CRYPTO.sof@2"
