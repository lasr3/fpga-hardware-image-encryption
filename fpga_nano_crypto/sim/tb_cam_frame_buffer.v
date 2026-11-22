`timescale 1ns/1ps
// Double-buffered cam_frame_buffer: the camera and the display run on
// different clocks and frame rates. Camera frame f writes (7*f + pixel) mod 64.
// Every displayed frame must come from a single camera frame (no tearing), with
// the pixel for iREAD on oRAW (show-ahead), and frames must keep advancing.
module tb_cam_frame_buffer;

parameter real CAM_HALF = 20.5;          // camera clock half period (ns)
parameter integer CAM_HBLANK = 6, CAM_VBLANK = 25;

localparam W = 16, H = 8, N = W * H;

reg cclk = 0, vclk = 0;
always #(CAM_HALF) cclk = ~cclk;
always #20 vclk = ~vclk;

reg        cvs = 0, chs = 0;
reg  [9:0] cdata = 0;
reg        vvs = 1, rd = 0;
wire [9:0] raw;

cam_frame_buffer #(.H_ACT(W), .V_ACT(H)) dut (
	.iWR_CLK(cclk), .iWR_VS(cvs), .iWR_HS(chs), .iWR_RAW(cdata),
	.iRD_CLK(vclk), .iRD_VS(vvs), .iREAD(rd), .oRAW(raw)
);

// Camera: frame f, pixel p -> value (7f + p) mod 64 in bits 9:4
integer cf = 0, cx, cy;
reg [5:0] cval;
initial begin
	repeat (10) @(negedge cclk);
	forever begin
		cf = cf + 1;
		@(negedge cclk) cvs = 1;
		repeat (3) @(negedge cclk);
		for (cy = 0; cy < H; cy = cy + 1) begin
			for (cx = 0; cx < W; cx = cx + 1) begin
				chs = 1; cval = (7*cf + cy*W + cx) % 64; cdata = {cval, 4'b0000};
				@(negedge cclk);
			end
			chs = 0;
			repeat (CAM_HBLANK) @(negedge cclk);
		end
		cvs = 0;
		repeat (CAM_VBLANK) @(negedge cclk);
	end
end

// Display: VS pulse, then H lines of W reads with blanking
integer df, x, y, p, f_first, f_prev = -1, errors = 0, torn = 0, shown = 0, k, val;
initial begin
	repeat (20) @(negedge vclk);
	for (df = 0; df < 40; df = df + 1) begin
		@(negedge vclk) vvs = 0;
		repeat (4) @(negedge vclk);
		vvs = 1;
		repeat (6) @(negedge vclk);
		f_first = -1;
		for (y = 0; y < H; y = y + 1) begin
			for (x = 0; x < W; x = x + 1) begin
				rd = 1;
				#1;                               // show-ahead: data valid with iREAD
				p = y*W + x;
				val = raw[9:4];
				if (f_first < 0) begin
					// Recover the camera frame number from pixel 0 (mod 64)
					f_first = -2;
					for (k = 0; k < 64; k = k + 1)
						if (((7*k) % 64) == val && f_first == -2) f_first = k;
				end else if (val != (7*f_first + p) % 64) begin
					torn = torn + 1;
				end
				@(negedge vclk);
			end
			rd = 0;
			repeat (8) @(negedge vclk);
		end
		if (f_first >= 0 && f_first != f_prev) shown = shown + 1;
		f_prev = f_first;
	end
	$display("camera frames written: %0d, distinct frames displayed: %0d, torn/misaligned pixels: %0d",
	         cf, shown, torn);
	$finish;
end

endmodule
