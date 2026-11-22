// Camera frame buffer in on-chip M10K (640x480 x 8-bit raw Bayer).
//
// The DE10-Nano has no FPGA-side SDRAM, so this replaces the Terasic
// Sdram_Control of the DE10-Standard build. It is a dual-clock RAM:
//   write side : MIPI pixel clock, one raw pixel per cycle while HS & VS
//   read side  : video clock, with the same show-ahead timing as the SDRAM
//                read FIFO (the pixel for iREAD is already on oRAW)
// There is a single buffer, so a tear line can appear where the camera frame
// overtakes the display frame.
module cam_frame_buffer #(
	parameter H_ACT = 640,
	parameter V_ACT = 480
)(
	// Camera side
	input             iWR_CLK,
	input             iWR_VS,     // camera frame valid (high during the frame)
	input             iWR_HS,     // camera line valid
	input       [9:0] iWR_RAW,
	// Display side
	input             iRD_CLK,
	input             iRD_VS,     // video vertical sync (active low)
	input             iREAD,      // pixel consumed this cycle
	output      [9:0] oRAW
);

localparam DEPTH = H_ACT * V_ACT;

reg  [7:0]  mem [0:DEPTH-1];

//-----------------------------------------------------------------------------
// Write side
//-----------------------------------------------------------------------------
reg  [18:0] wr_pix = 19'd0;

always @(posedge iWR_CLK) begin
	if (!iWR_VS)
		wr_pix <= 19'd0;
	else if (iWR_HS && wr_pix != DEPTH-1)
		wr_pix <= wr_pix + 19'd1;

	if (iWR_VS && iWR_HS)
		mem[wr_pix] <= iWR_RAW[9:2];
end

//-----------------------------------------------------------------------------
// Read side: read one ahead so the registered output matches show-ahead data
//-----------------------------------------------------------------------------
reg  [18:0] rd_pix = 19'd0;
reg  [7:0]  q;

wire [18:0] rd_addr = (iREAD && rd_pix != DEPTH-1) ? rd_pix + 19'd1 : rd_pix;

always @(posedge iRD_CLK) begin
	if (!iRD_VS)
		rd_pix <= 19'd0;
	else if (iREAD && rd_pix != DEPTH-1)
		rd_pix <= rd_pix + 19'd1;

	q <= mem[rd_addr];
end

assign oRAW = {q, 2'b00};

endmodule
