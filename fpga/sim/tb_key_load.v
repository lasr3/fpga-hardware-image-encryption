`timescale 1ns/1ps
// ARM -> crypto_regs (50 MHz Avalon) -> toggle_sync -> video_crypt (25 MHz).
// Checks register read-back here; check_key_load.py checks the pixels.
module tb_key_load;

localparam W = 16, H = 4, HBLANK = 8, VBLANK = 30;
localparam [127:0] NEW_KEY   = 128'h000102030405060708090a0b0c0d0e0f;
localparam [63:0]  NEW_NONCE = 64'hfedcba9876543210;

reg clk50 = 0, clk25 = 0;
always #10 clk50 = ~clk50;
always #20 clk25 = ~clk25;

// Avalon master (the ARM)
reg  [3:0]  addr = 0;
reg         rd = 0, wr = 0;
reg  [31:0] wdata = 0;
wire [31:0] rdata;
reg         rst50 = 1;

wire [127:0] key;
wire [63:0]  nonce;
wire         commit_t, default_t, commit_p, default_p, ready, hps_key;

crypto_regs u_regs (
	.clk(clk50), .reset(rst50),
	.avs_address(addr), .avs_read(rd), .avs_readdata(rdata), .avs_write(wr), .avs_writedata(wdata),
	.coe_key(key), .coe_nonce(nonce), .coe_commit_toggle(commit_t), .coe_default_toggle(default_t),
	.coe_status({4'ha, 2'b00, hps_key, ready}),
	.coe_dma_addr(), .coe_grab(), .coe_grab_busy(1'b0), .coe_grab_done(1'b0),
	.coe_grab_overflow(1'b0), .coe_grab_ecb(1'b0), .coe_grab_frame(32'd0)
);

toggle_sync u_c (.iCLK(clk25), .iTOGGLE(commit_t),  .oPULSE(commit_p));
toggle_sync u_d (.iCLK(clk25), .iTOGGLE(default_t), .oPULSE(default_p));

reg        rst_n = 0, de = 0, hs = 1, vs = 1, enc = 1, dec = 0;
reg [23:0] rgb = 0;
wire       ode, ohs, ovs;
wire [23:0] orgb;

video_crypt dut (
	.iCLK(clk25), .iRST_N(rst_n),
	.iENCRYPT(enc), .iECB(1'b0), .iDECRYPT(dec), .iRX_WRONG_KEY(1'b0),
	.iKEY(key), .iNONCE(nonce), .iLOAD(commit_p), .iLOAD_DEFAULT(default_p),
	.iDE(de), .iHS(hs), .iVS(vs), .iRGB(rgb),
	.oDE(ode), .oHS(ohs), .oVS(ovs), .oRGB(orgb), .oKEYS_READY(ready), .oHPS_KEY(hps_key)
);

integer fd, f, x, y, errors = 0;

task bus_write(input [3:0] a, input [31:0] d);
	begin
		@(negedge clk50) addr = a; wdata = d; wr = 1;
		@(negedge clk50) wr = 0;
	end
endtask

task bus_read(input [3:0] a, output [31:0] d);
	begin
		@(negedge clk50) addr = a; rd = 1;
		@(negedge clk50) rd = 0;
		d = rdata;
	end
endtask

task expect_reg(input [3:0] a, input [31:0] want);
	reg [31:0] got;
	begin
		bus_read(a, got);
		if (got !== want) begin
			$display("FAIL reg %0d: got %h want %h", a, got, want);
			errors = errors + 1;
		end
	end
endtask

// One frame; frame numbers restart at 1 after each key change (counter -> 0, then VS)
task frame(input integer mode, input integer fnum);
	begin
		enc = 1; dec = (mode == 1);
		@(negedge clk25) vs = 0;
		repeat (VBLANK) @(negedge clk25);
		vs = 1;
		repeat (HBLANK) @(negedge clk25);
		for (y = 0; y < H; y = y + 1) begin
			for (x = 0; x < W; x = x + 1) begin
				de = 1; rgb = $random;
				$fdisplay(fd, "i %0d %0d %0d %06x", mode, fnum, y*W + x, rgb);
				@(negedge clk25);
			end
			de = 0;
			repeat (HBLANK) @(negedge clk25);
		end
		repeat (20) @(negedge clk25);
	end
endtask

always @(posedge clk25)
	if (ode) $fdisplay(fd, "o %06x", orgb);

initial begin
	fd = $fopen("key_load.log", "w");
	repeat (4) @(negedge clk50);
	rst50 = 0;
	repeat (4) @(negedge clk25);
	rst_n = 1;
	repeat (40) @(negedge clk25);

	expect_reg(4'h0, 32'h43525950);          // ID
	expect_reg(4'h2, 32'h00000a01);          // keys ready, default key, SW = 1010

	$fdisplay(fd, "k 2b7e151628aed2a6abf7158809cf4f3c 494e535045522121");
	frame(0, 1);

	// The ARM loads a new key and nonce
	bus_write(4'h4, NEW_KEY[127:96]);
	bus_write(4'h5, NEW_KEY[95:64]);
	bus_write(4'h6, NEW_KEY[63:32]);
	bus_write(4'h7, NEW_KEY[31:0]);
	bus_write(4'h8, NEW_NONCE[63:32]);
	bus_write(4'h9, NEW_NONCE[31:0]);
	bus_write(4'h1, 32'h1);                  // COMMIT
	repeat (40) @(negedge clk25);
	expect_reg(4'h6, NEW_KEY[63:32]);
	expect_reg(4'h2, 32'h00000a03);          // ARM key in use

	$fdisplay(fd, "k %032x %016x", NEW_KEY, NEW_NONCE);
	frame(0, 1);
	frame(0, 2);
	frame(1, 3);                             // receiver decrypts with the same key

	bus_write(4'h1, 32'h2);                  // back to the default key
	repeat (40) @(negedge clk25);
	expect_reg(4'h2, 32'h00000a01);
	$fdisplay(fd, "k 2b7e151628aed2a6abf7158809cf4f3c 494e535045522121");
	frame(0, 1);

	$display("register checks: %0d errors", errors);
	$fclose(fd);
	$finish;
end

endmodule
