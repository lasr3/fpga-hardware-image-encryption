// Camera frame buffer in on-chip M10K: two banks of 640x480 x 6-bit raw Bayer.
//
// The DE10-Nano has no FPGA-side SDRAM, so this replaces the Terasic
// Sdram_Control of the DE10-Standard build. It is double-buffered so a
// displayed frame never mixes two camera frames (no tearing):
//   - the camera writes into the bank the display is not reading;
//   - a finished camera frame is handed to the display side, which switches to
//     it at its next vertical sync and acknowledges;
//   - while a finished frame is still waiting for the display, new camera
//     frames are skipped rather than overwriting it.
// Two 8-bit banks would not fit in the 553 M10K blocks, hence 6 bits per pixel.
//
// Read side timing is the same as the SDRAM read FIFO it replaces (show-ahead:
// the pixel for iREAD is already on oRAW).
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

reg  [5:0]  mem0 [0:DEPTH-1];
reg  [5:0]  mem1 [0:DEPTH-1];

//-----------------------------------------------------------------------------
// Handshake between the two clock domains
//-----------------------------------------------------------------------------
reg  req_toggle = 1'b0;     // camera side: "pend_bank holds a finished frame"
reg  ack_toggle = 1'b0;     // display side: "switched to it"
reg  pend_bank  = 1'b0;     // stable from req_toggle until ack_toggle

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg  [1:0] req_sync = 2'b00;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg  [1:0] ack_sync = 2'b00;

//-----------------------------------------------------------------------------
// Write side
//-----------------------------------------------------------------------------
reg  [18:0] wr_pix   = 19'd0;
reg         vs_prev  = 1'b0;
reg         writing  = 1'b0;
reg         wbank    = 1'b1;
reg         disp_bank = 1'b0;   // bank the display is on (as last acknowledged)
reg         pending  = 1'b0;    // a finished frame waits for the display
reg         ack_seen = 1'b0;

always @(posedge iWR_CLK) begin
	vs_prev  <= iWR_VS;
	ack_sync <= {ack_sync[0], ack_toggle};

	// The display took the pending frame
	if (pending && ack_sync[1] != ack_seen) begin
		ack_seen  <= ack_sync[1];
		pending   <= 1'b0;
		disp_bank <= pend_bank;
	end

	if (vs_prev && !iWR_VS) begin
		// Frame end: hand the finished bank to the display side
		if (writing) begin
			pend_bank  <= wbank;
			pending    <= 1'b1;
			req_toggle <= ~req_toggle;
		end
		writing <= 1'b0;
	end else if (!iWR_VS) begin
		// Between frames: prepare the next one. Write the free bank, or skip
		// the frame if the only other bank still holds a frame the display
		// has not taken yet
		wr_pix  <= 19'd0;
		writing <= !pending;
		wbank   <= !disp_bank;
	end else if (iWR_HS && wr_pix != DEPTH-1) begin
		wr_pix <= wr_pix + 19'd1;
	end

	if (writing && iWR_VS && iWR_HS) begin
		if (wbank) mem1[wr_pix] <= iWR_RAW[9:4];
		else       mem0[wr_pix] <= iWR_RAW[9:4];
	end
end

//-----------------------------------------------------------------------------
// Read side: switch banks during vertical sync, read one ahead so the
// registered output matches show-ahead data
//-----------------------------------------------------------------------------
reg  [18:0] rd_pix   = 19'd0;
reg         rd_vs_prev = 1'b1;
reg         rbank    = 1'b0;
reg         req_seen = 1'b0;
reg  [5:0]  q0, q1;

wire [18:0] rd_addr = (iREAD && rd_pix != DEPTH-1) ? rd_pix + 19'd1 : rd_pix;

always @(posedge iRD_CLK) begin
	rd_vs_prev <= iRD_VS;
	req_sync   <= {req_sync[0], req_toggle};

	if (rd_vs_prev && !iRD_VS && req_sync[1] != req_seen) begin
		req_seen   <= req_sync[1];
		rbank      <= pend_bank;    // stable: set before req_toggle changed
		ack_toggle <= ~ack_toggle;
	end

	if (!iRD_VS)
		rd_pix <= 19'd0;
	else if (iREAD && rd_pix != DEPTH-1)
		rd_pix <= rd_pix + 19'd1;

	q0 <= mem0[rd_addr];
	q1 <= mem1[rd_addr];
end

assign oRAW = {rbank ? q1 : q0, 4'b0000};

endmodule
