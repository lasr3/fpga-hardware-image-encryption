# Prebuilt files

Built with Quartus Prime 25.1 Lite from the sources in `fpga/`.

| File | Use |
|---|---|
| `soc_system.rbf` | FPGA configuration for the microSD card: copy it to the card's FAT partition, U-Boot loads it at boot |
| `DE10_NANO_CRYPTO.sof` | FPGA configuration for JTAG: `quartus_pgm -m jtag -c 1 -o "p;DE10_NANO_CRYPTO.sof@2"` (lost at power-off) |
| `DE10_NANO_CRYPTO.qar` | Quartus project archive: *Project → Restore Archived Project*, then compile. Includes the generated Platform Designer system and the `crypto_regs` component |

The `.rbf` is compressed, matching the DE10-Nano's default MSEL switch setting.
See [setup](../docs/hardware-setup.md) for the rest of the SD card and board setup.
