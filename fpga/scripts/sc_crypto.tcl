# System Console test of crypto_regs over JTAG (no Linux needed).
# In the VM, with the board programmed:
#   system-console --script=scripts/sc_crypto.tcl
# Loads the key 000102...0f with nonce fedcba9876543210 and prints the status.

set masters [get_service_paths master]
set m ""
foreach p $masters { if {[string match "*fpga_only_master*" $p]} { set m $p } }
if {$m eq ""} { puts "fpga_only_master not found in: $masters"; exit 1 }
open_service master $m

set base 0x6000
proc rd {off}     { global m base; return [master_read_32 $m [expr {$base + $off}] 1] }
proc wr {off val} { global m base; master_write_32 $m [expr {$base + $off}] $val }

puts "ID     = [rd 0x00]  (expect 0x43525950)"
wr 0x10 0x00010203
wr 0x14 0x04050607
wr 0x18 0x08090a0b
wr 0x1c 0x0c0d0e0f
wr 0x20 0xfedcba98
wr 0x24 0x76543210
wr 0x04 0x1
after 10
puts "STATUS = [rd 0x08]  (bit 0 keys ready, bit 1 ARM key, bits 11:8 switches)"
puts "KEY    = [rd 0x10] [rd 0x14] [rd 0x18] [rd 0x1c]"
close_service master $m
