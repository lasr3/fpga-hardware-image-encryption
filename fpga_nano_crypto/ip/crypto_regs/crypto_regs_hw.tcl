# Platform Designer component: AES key registers for the video encryption
package require -exact qsys 16.0

set_module_property NAME crypto_regs
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "AES video key registers"
set_module_property DESCRIPTION "Key/nonce registers for the D8M -> HDMI AES-CTR pipeline"
set_module_property GROUP "Insper SoC"
set_module_property AUTHOR "Insper SoC project"
set_module_property EDITABLE false
set_module_property INTERNAL false

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL crypto_regs
add_fileset_file crypto_regs.v VERILOG PATH crypto_regs.v TOP_LEVEL_FILE

# Clock and reset
add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset reset Input 1

# Avalon-MM slave: 16 x 32-bit words, read latency 1
add_interface s0 avalon end
set_interface_property s0 addressUnits WORDS
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 readLatency 1
set_interface_property s0 readWaitTime 0
set_interface_property s0 writeWaitTime 0
set_interface_property s0 maximumPendingReadTransactions 0
add_interface_port s0 avs_address address Input 4
add_interface_port s0 avs_read read Input 1
add_interface_port s0 avs_readdata readdata Output 32
add_interface_port s0 avs_write write Input 1
add_interface_port s0 avs_writedata writedata Input 32

# Conduit to the video pipeline (exported to the top level)
add_interface crypto conduit end
set_interface_property crypto associatedClock clock
add_interface_port crypto coe_key key Output 128
add_interface_port crypto coe_nonce nonce Output 64
add_interface_port crypto coe_commit_toggle commit_toggle Output 1
add_interface_port crypto coe_default_toggle default_toggle Output 1
add_interface_port crypto coe_status status Input 8
add_interface_port crypto coe_dma_addr dma_addr Output 32
add_interface_port crypto coe_grab grab Output 1
add_interface_port crypto coe_grab_busy grab_busy Input 1
add_interface_port crypto coe_grab_done grab_done Input 1
add_interface_port crypto coe_grab_overflow grab_overflow Input 1
add_interface_port crypto coe_grab_ecb grab_ecb Input 1
add_interface_port crypto coe_grab_frame grab_frame Input 32
