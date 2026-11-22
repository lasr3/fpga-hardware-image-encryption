// Avalon-MM register block for the video encryption key (Platform Designer
// component, see crypto_regs_hw.tcl). Reached by the ARM through the
// lightweight HPS-to-FPGA bridge.
//
// Word offsets (byte offset = 4 x word):
//   0x00 ID        RO  0x43525950 ("CRYP")
//   0x04 CTRL      WO  bit 0: COMMIT - apply KEY/NONCE (frame counter restarts)
//                      bit 1: DEFAULT - go back to the built-in test key
//                      bit 2: GRAB - copy the next ciphertext frame to DMA_ADDR
//   0x08 STATUS    RO  bit 0: AES round keys ready
//                      bit 1: key loaded from the ARM in use
//                      bit 2: grab busy
//                      bit 3: grab done (cleared by the next GRAB)
//                      bit 4: grabbed frame incomplete (FIFO overflow)
//                      bit 5: grabbed frame was taken in ECB view (not CTR)
//                      bits 11:8: slide switches SW[3:0]
//   0x10..0x1C KEY0..KEY3  RW  key bits 127:96 .. 31:0 (KEY0 = first 4 key bytes)
//   0x20 NONCE_HI  RW  nonce bits 63:32
//   0x24 NONCE_LO  RW  nonce bits 31:0
//   0x28 DMA_ADDR  RW  physical byte address of the frame buffer in DDR3
//   0x2C FRAME     RO  AES frame number of the grabbed frame
//
// COMMIT and DEFAULT flip toggle outputs; the video clock domain detects the
// toggle and samples KEY/NONCE, which software must not change in between.
module crypto_regs (
	input             clk,
	input             reset,
	// Avalon-MM slave
	input      [3:0]  avs_address,
	input             avs_read,
	output reg [31:0] avs_readdata,
	input             avs_write,
	input      [31:0] avs_writedata,
	// Conduit to the video pipeline
	output     [127:0] coe_key,
	output     [63:0] coe_nonce,
	output reg        coe_commit_toggle,
	output reg        coe_default_toggle,
	input      [7:0]  coe_status,         // asynchronous, synchronised here
	// Conduit to the frame writer (same clock domain)
	output reg [31:0] coe_dma_addr,
	output reg        coe_grab,
	input             coe_grab_busy,
	input             coe_grab_done,
	input             coe_grab_overflow,
	input             coe_grab_ecb,
	input      [31:0] coe_grab_frame
);

localparam [31:0] ID = 32'h43525950;

reg [31:0] key   [0:3];
reg [31:0] nonce [0:1];
reg [7:0]  status_m, status_s;

// Power-up contents: the built-in test key/nonce (same as video_crypt)
initial begin
	key[0]   = 32'h2b7e1516; key[1] = 32'h28aed2a6; key[2] = 32'habf71588; key[3] = 32'h09cf4f3c;
	nonce[0] = 32'h494E5350; nonce[1] = 32'h45522121;
	coe_dma_addr = 32'h3F000000;   // top 16 MB of DDR3, reserved with mem=1008M
	coe_grab     = 1'b0;
end

assign coe_key   = {key[0], key[1], key[2], key[3]};
assign coe_nonce = {nonce[0], nonce[1]};

always @(posedge clk) begin
	status_m <= coe_status;
	status_s <= status_m;
end

always @(posedge clk) begin
	coe_grab <= 1'b0;
	if (reset) begin
		coe_commit_toggle  <= 1'b0;
		coe_default_toggle <= 1'b0;
	end else if (avs_write) begin
		case (avs_address)
			4'h1: begin
				if (avs_writedata[0]) coe_commit_toggle  <= ~coe_commit_toggle;
				if (avs_writedata[1]) coe_default_toggle <= ~coe_default_toggle;
				if (avs_writedata[2]) coe_grab           <= 1'b1;
			end
			4'ha: coe_dma_addr <= avs_writedata;
			4'h4, 4'h5, 4'h6, 4'h7: key[avs_address[1:0]] <= avs_writedata;
			4'h8: nonce[0] <= avs_writedata;
			4'h9: nonce[1] <= avs_writedata;
			default: ;
		endcase
	end
end

always @(posedge clk) begin
	if (avs_read) begin
		case (avs_address)
			4'h0: avs_readdata <= ID;
			4'h2: avs_readdata <= {20'd0, status_s[7:4], 2'd0, coe_grab_ecb, coe_grab_overflow,
			                       coe_grab_done, coe_grab_busy, status_s[1:0]};
			4'h4, 4'h5, 4'h6, 4'h7: avs_readdata <= key[avs_address[1:0]];
			4'h8: avs_readdata <= nonce[0];
			4'h9: avs_readdata <= nonce[1];
			4'ha: avs_readdata <= coe_dma_addr;
			4'hb: avs_readdata <= coe_grab_frame;
			default: avs_readdata <= 32'd0;
		endcase
	end
end

endmodule
