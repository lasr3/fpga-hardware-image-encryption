// Copies one video frame (on request) into HPS DDR3 through the FPGA-to-SDRAM
// port, so the ARM can send it over the network.
//
// Memory layout at iADDR (byte address, 32-byte aligned): the frame's pixels
// in raster order, 3 bytes each (R, G, B), no padding: H_ACT*V_ACT*3 bytes.
//
// Video side (iVCLK): after a grab request, waits for the next vertical sync,
// then packs every pixel of one frame, 32 pixels = 768 bits = three 256-bit
// words, into an async FIFO. If the FIFO is full the word is dropped and
// oOVERFLOW is set; video output is never stalled.
//
// Memory side (iMCLK): drains the FIFO with single-word Avalon-MM writes.
// Each grab first discards anything left in the FIFO (e.g. after the FPGA-to-
// SDRAM port was reset mid-capture), so a stray word can never shift a frame.
// oDONE rises once the whole frame has been written (or the capture ended and
// the FIFO is empty), with oFRAME = frame number used by the AES counter.
module frame_writer #(
	parameter H_ACT = 640,
	parameter V_ACT = 480
)(
	// Video side
	input              iVCLK,
	input              iDE,
	input              iVS,          // active low
	input       [23:0] iPIXEL,       // {R, G, B}
	input       [31:0] iFRAME,       // AES frame counter of the current frame
	input              iECB,         // ECB view selected (pixels are not CTR)

	// Memory side: control (same clock as the Avalon master)
	input              iMCLK,
	input              iRESET,
	input              iGRAB,        // one-clock pulse: capture the next frame
	input       [31:0] iADDR,
	output reg         oBUSY,
	output reg         oDONE,
	output reg         oOVERFLOW,
	output reg         oFRAME_ECB,
	output reg  [31:0] oFRAME,

	// Avalon-MM master to hps_0.f2h_sdram0_data (256-bit, word addresses)
	output      [26:0] avm_address,
	output       [7:0] avm_burstcount,
	output             avm_write,
	output     [255:0] avm_writedata,
	output      [31:0] avm_byteenable,
	input              avm_waitrequest
);

localparam PIXELS = H_ACT * V_ACT;
localparam WORDS  = PIXELS * 3 / 32;     // 28800 for 640x480

//=============================================================================
// Request: memory side -> video side
//=============================================================================
reg  grab_toggle = 1'b0;
wire grab_v;

toggle_sync u_grab_sync ( .iCLK ( iVCLK ), .iTOGGLE ( grab_toggle ), .oPULSE ( grab_v ) );

//=============================================================================
// Video side: wait for a frame start, then pack its pixels
//=============================================================================
localparam V_IDLE = 2'd0, V_WAIT = 2'd1, V_CAPTURE = 2'd2, V_FINISH = 2'd3;

reg  [1:0]   vstate = V_IDLE;
reg  [3:0]   finish_cnt;
reg          vs_prev = 1'b1;
reg  [18:0]  vpix;
reg  [4:0]   idx;
reg  [767:0] acc;
reg  [767:0] hold;
reg  [1:0]   pending = 2'd0;
reg          first;
reg  [31:0]  frame_lat;
reg          ecb_lat;
reg          overflow_v;
reg          done_toggle = 1'b0;

wire         fifo_full;
wire         fifo_wr = (pending != 2'd0);
wire [255:0] fifo_d  = hold[256*(3 - pending) +: 256];

always @(posedge iVCLK) begin
	vs_prev <= iVS;

	// Write out a completed group of 32 pixels, one word per clock
	if (pending != 2'd0) begin
		pending <= pending - 2'd1;
		if (fifo_full)
			overflow_v <= 1'b1;
	end

	case (vstate)
		V_IDLE:
			if (grab_v) begin
				vstate     <= V_WAIT;
				overflow_v <= 1'b0;
			end
		V_WAIT:
			if (vs_prev && !iVS) begin
				vstate <= V_CAPTURE;
				vpix   <= 19'd0;
				idx    <= 5'd0;
				first  <= 1'b1;
			end
		V_CAPTURE:
			if (iDE) begin
				// Byte order in memory: R, G, B
				acc[24*idx +: 24] <= {iPIXEL[7:0], iPIXEL[15:8], iPIXEL[23:16]};
				if (idx == 5'd31) begin
					hold    <= acc;
					hold[24*31 +: 24] <= {iPIXEL[7:0], iPIXEL[15:8], iPIXEL[23:16]};
					pending <= 2'd3;
				end
				idx  <= idx + 5'd1;
				vpix <= vpix + 19'd1;
				if (first) begin
					frame_lat <= iFRAME;
					ecb_lat   <= iECB;
					first     <= 1'b0;
				end
				if (vpix == PIXELS - 1) begin
					vstate     <= V_FINISH;
					finish_cnt <= 4'd0;
				end
			end
		// Signal "done" only after the last words have been in the FIFO for a
		// while, so the memory side never sees "done + empty" too early
		V_FINISH: begin
			finish_cnt <= finish_cnt + 4'd1;
			if (finish_cnt == 4'd15) begin
				vstate      <= V_IDLE;
				done_toggle <= ~done_toggle;
			end
		end
	endcase
end

//=============================================================================
// FIFO between the clock domains
//=============================================================================
wire [255:0] fifo_q;
wire         fifo_empty;
reg          flushing = 1'b0;
wire         wr_accept = avm_write && !avm_waitrequest;
wire         fifo_rd   = wr_accept || (flushing && !fifo_empty);

async_fifo #(.WIDTH(256), .AW(6)) u_fifo (
	.iWCLK  ( iVCLK ),
	.iWR    ( fifo_wr ),
	.iD     ( fifo_d ),
	.oFULL  ( fifo_full ),
	.iRCLK  ( iMCLK ),
	.iRD    ( fifo_rd ),
	.oQ     ( fifo_q ),
	.oEMPTY ( fifo_empty )
);

//=============================================================================
// Memory side: Avalon-MM writes
//=============================================================================
reg  [26:0] base_word;
reg  [14:0] wcount;
reg         vdone_seen;
wire        vdone;

toggle_sync u_done_sync ( .iCLK ( iMCLK ), .iTOGGLE ( done_toggle ), .oPULSE ( vdone ) );

assign avm_address    = base_word + wcount;
assign avm_burstcount = 8'd1;
assign avm_write      = oBUSY && !flushing && !fifo_empty;
assign avm_writedata  = fifo_q;
assign avm_byteenable = 32'hFFFFFFFF;

initial begin
	oBUSY = 1'b0;
	oDONE = 1'b0;
end

always @(posedge iMCLK) begin
	if (iRESET) begin
		oBUSY    <= 1'b0;
		oDONE    <= 1'b0;
		flushing <= 1'b0;
	end else begin
		// Ignored while a capture is running
		if (iGRAB && !oBUSY) begin
			base_word   <= iADDR[31:5];
			wcount      <= 15'd0;
			vdone_seen  <= 1'b0;
			oBUSY       <= 1'b1;
			oDONE       <= 1'b0;
			flushing    <= 1'b1;
		end else if (flushing) begin
			// Empty the FIFO, then let the video side start capturing
			if (fifo_empty) begin
				flushing    <= 1'b0;
				grab_toggle <= ~grab_toggle;
			end
		end else if (oBUSY) begin
			if (wr_accept)
				wcount <= wcount + 15'd1;
			if (vdone)
				vdone_seen <= 1'b1;
			// Finished: every word written, or the video side is done and the
			// FIFO has drained (some words were dropped: oOVERFLOW)
			if ((wr_accept && wcount == WORDS - 1) || (vdone_seen && fifo_empty)) begin
				oBUSY      <= 1'b0;
				oDONE      <= 1'b1;
				// Stable: latched by the video side long before the last word
				oFRAME     <= frame_lat;
				oFRAME_ECB <= ecb_lat;
				oOVERFLOW  <= overflow_v || !(wr_accept && wcount == WORDS - 1);
			end
		end
	end
end

endmodule
