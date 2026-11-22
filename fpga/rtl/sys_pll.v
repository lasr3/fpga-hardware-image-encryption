// System PLL for DE10-Nano (Cyclone V).
//
//   outclk_0 : 25 MHz  HDMI pixel clock (640x480@60)
//   outclk_1 : 20 MHz  D8M MIPI bridge reference clock
`timescale 1ns/10ps
module sys_pll (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire outclk_1,
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(2),
		.output_clock_frequency0("25.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.output_clock_frequency1("20.000000 MHz"),
		.phase_shift1("0 ps"),
		.duty_cycle1(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst      (rst),
		.outclk   ({outclk_1, outclk_0}),
		.locked   (locked),
		.fboutclk (),
		.fbclk    (1'b0),
		.refclk   (refclk)
	);

endmodule
