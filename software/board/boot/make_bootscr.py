# Builds a U-Boot script image (same format as "mkimage -A arm -O linux -T script
# -C none -n bootscript"), so no U-Boot tools are needed.
#   python3 make_bootscr.py boot.script u-boot.scr
#
# boot.script is Terasic's original DE10-Nano boot script with one change:
# Linux is started with mem=1008M, which keeps the top 16 MB of DDR3
# (0x3F000000-0x3FFFFFFF) free for the FPGA's frame buffer.
import struct, sys, time, zlib

IH_MAGIC, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT, IH_COMP_NONE = 0x27051956, 5, 2, 6, 0

script = open(sys.argv[1], "rb").read()
data = struct.pack(">II", len(script), 0) + script      # one part, then terminator
name = b"bootscript".ljust(32, b"\0")
fields = [IH_MAGIC, 0, int(time.time()), len(data), 0, 0, zlib.crc32(data) & 0xFFFFFFFF]
header = struct.pack(">7I4B", *fields, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT, IH_COMP_NONE) + name
fields[1] = zlib.crc32(header) & 0xFFFFFFFF
header = struct.pack(">7I4B", *fields, IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT, IH_COMP_NONE) + name
open(sys.argv[2], "wb").write(header + data)
print(f"{sys.argv[2]}: {len(header + data)} bytes")
