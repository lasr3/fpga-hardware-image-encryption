#**************************************************************
# DE10-Nano + D8M-GPIO + AES video encryption -> HDMI
#**************************************************************

# Board oscillators
create_clock -period "50.0 MHz" -name FPGA_CLK1_50 [get_ports FPGA_CLK1_50]
create_clock -period "50.0 MHz" -name FPGA_CLK2_50 [get_ports FPGA_CLK2_50]

# D8M MIPI bridge parallel output clock (25 MHz for 640x480)
create_clock -period "25.0 MHz" -name MIPI_PIXEL_CLK [get_ports MIPI_PIXEL_CLK]
create_clock -period "25.0 MHz" -name MIPI_PIXEL_CLK_ext

derive_pll_clocks
derive_clock_uncertainty

# PLL outputs (sys_pll): 0 = video, 1 = MIPI refclk
set clk_vga  [get_clocks {u_pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set clk_mref [get_clocks {u_pll|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]

# Pixel clock at the HDMI_TX_CLK pin (inverted in the top level)
create_generated_clock -name clk_hdmi_ext -invert \
	-source [get_pins {u_pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
	[get_ports {HDMI_TX_CLK}]

#**************************************************************
# Inputs
#**************************************************************
# D8M: tpd min 1 ns, max 6 ns
set_input_delay -max 6.1 -clock MIPI_PIXEL_CLK_ext [get_ports {MIPI_PIXEL_VS MIPI_PIXEL_HS MIPI_PIXEL_D[*]}]
set_input_delay -min 0.9 -clock MIPI_PIXEL_CLK_ext [get_ports {MIPI_PIXEL_VS MIPI_PIXEL_HS MIPI_PIXEL_D[*]}]

#**************************************************************
# Outputs: ADV7513 setup 1.0 ns / hold 0.7 ns plus board margin
#**************************************************************
set_output_delay -max -clock clk_hdmi_ext  1.5 [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]
set_output_delay -min -clock clk_hdmi_ext -1.2 [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]

#**************************************************************
# Clock groups: domains only meet in the dual-clock frame buffer RAM
# and in slow status/handshake signals
#**************************************************************
set_clock_groups -asynchronous \
	-group [list FPGA_CLK1_50] \
	-group [list $clk_vga clk_hdmi_ext] \
	-group [list $clk_mref] \
	-group [list MIPI_PIXEL_CLK MIPI_PIXEL_CLK_ext] \
	-group [list FPGA_CLK2_50]

#**************************************************************
# False paths
#**************************************************************
set_false_path -from [get_ports {KEY* SW* HDMI_TX_INT}] -to *
set_false_path -from * -to [get_ports {LED*}]
set_false_path -to [get_ports {CAMERA_* MIPI_CS_n MIPI_RESET_n MIPI_I2C_* MIPI_MCLK MIPI_REFCLK HDMI_I2C_*}]
set_false_path -from [get_ports {CAMERA_I2C_SDA MIPI_I2C_* HDMI_I2C_*}]
