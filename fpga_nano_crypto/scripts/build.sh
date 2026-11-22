#!/usr/bin/env bash
# Generate the Platform Designer system and compile the FPGA project.
# Run inside the Quartus VM, from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

# soc_system.qsys = Terasic GHRD (HPS for the DE10-Nano) + crypto_regs (ip/crypto_regs)
qsys-generate soc_system.qsys --synthesis=VERILOG --output-directory=soc_system \
	--family="Cyclone V" --part=5CSEBA6U23I7 --search-path='ip/**/*,$'

quartus_sh --flow compile DE10_NANO_CRYPTO

# Bitstream for the SD card (the bootloader can configure the FPGA from it)
quartus_cpf -c -o bitstream_compression=on output_files/DE10_NANO_CRYPTO.sof output_files/soc_system.rbf

echo
grep -E "Fitter Status|Logic utilization|Total pins|Total memory bits|Total RAM Blocks|Total PLLs" output_files/DE10_NANO_CRYPTO.fit.summary || true
