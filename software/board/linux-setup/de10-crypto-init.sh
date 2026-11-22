#!/bin/sh
# Release the FPGA-to-SDRAM ports (the bootloader leaves them in reset),
# needed by frame_writer / frame_server. The static IP is set by connman
# (/var/lib/connman/de10-crypto.config).
devmem 0xFFC25080 32 0x1FF
