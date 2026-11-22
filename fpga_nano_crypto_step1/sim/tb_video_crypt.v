`timescale 1ns/1ps
// Drives short synthetic frames through video_crypt in each mode and logs
// inputs and outputs; check_video_crypt.py verifies them against pycryptodome.
module tb_video_crypt;

localparam W = 16, H = 4, HBLANK = 8, VBLANK = 30, NFRAMES = 5;

reg clk = 0;
always #20 clk = ~clk;

reg        rst_n = 0;
reg        de = 0, hs = 1, vs = 1;
reg [23:0] rgb = 0;
reg        enc = 0, ecb = 0, dec = 0, wrong = 0;
wire       ode, ohs, ovs, ready;
wire [23:0] orgb;

video_crypt dut (
	.iCLK(clk), .iRST_N(rst_n),
	.iENCRYPT(enc), .iECB(ecb), .iDECRYPT(dec), .iRX_WRONG_KEY(wrong),
	.iDE(de), .iHS(hs), .iVS(vs), .iRGB(rgb),
	.oDE(ode), .oHS(ohs), .oVS(ovs), .oRGB(orgb), .oKEYS_READY(ready)
);

integer fd, f, x, y, mode;

// Log every output pixel
always @(posedge clk)
	if (ode) $fdisplay(fd, "o %06x", orgb);

initial begin
	fd = $fopen("video_crypt.log", "w");
	repeat (5) @(negedge clk);
	rst_n = 1;
	repeat (40) @(negedge clk);
	for (f = 1; f <= NFRAMES; f = f + 1) begin
		mode = f - 1;   // 0 ctr, 1 ctr+decrypt, 2 decrypt wrong key, 3 ecb, 4 plain
		enc = (mode != 4); dec = (mode == 1 || mode == 2); wrong = (mode == 2); ecb = (mode == 3);
		@(negedge clk) vs = 0;          // frame counter increments here
		repeat (VBLANK) @(negedge clk);
		vs = 1;
		repeat (HBLANK) @(negedge clk);
		for (y = 0; y < H; y = y + 1) begin
			for (x = 0; x < W; x = x + 1) begin
				de = 1;
				// Flat colour on the left half (ECB should repeat), random on the right
				rgb = (x < W/2) ? 24'h3366CC : $random;
				$fdisplay(fd, "i %0d %0d %0d %06x", mode, f, y*W + x, rgb);
				@(negedge clk);
			end
			de = 0;
			repeat (HBLANK) @(negedge clk);
		end
		repeat (20) @(negedge clk);     // let the pipeline drain before switching mode
	end
	repeat (40) @(negedge clk);
	$display("keys ready = %b", ready);
	$fclose(fd);
	$finish;
end

endmodule
