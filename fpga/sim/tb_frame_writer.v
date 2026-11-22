`timescale 1ns/1ps
// frame_writer with a small frame (64x4), an Avalon slave with random wait
// states standing in for the FPGA-to-SDRAM port, and a byte-exact check of the
// memory contents.
module tb_frame_writer;

localparam W = 64, H = 4, HBLANK = 10, VBLANK = 40;
localparam NBYTES = W * H * 3;
localparam BASE = 32'h3F000000;

reg vclk = 0, mclk = 0;
always #20 vclk = ~vclk;     // 25 MHz
always #10 mclk = ~mclk;     // 50 MHz

reg        de = 0, vs = 1;
reg [23:0] pixel = 0;
reg [31:0] frame = 0;
reg        reset = 1, grab = 0;
wire       busy, done, overflow, fecb;
wire [31:0] fframe;
wire [26:0] addr;
wire [7:0]  bc;
wire        wr;
wire [255:0] wdata;
wire [31:0] be;
reg         waitreq = 1;

frame_writer #(.H_ACT(W), .V_ACT(H)) dut (
	.iVCLK(vclk), .iDE(de), .iVS(vs), .iPIXEL(pixel), .iFRAME(frame), .iECB(1'b0),
	.iMCLK(mclk), .iRESET(reset), .iGRAB(grab), .iADDR(BASE),
	.oBUSY(busy), .oDONE(done), .oOVERFLOW(overflow), .oFRAME_ECB(fecb), .oFRAME(fframe),
	.avm_address(addr), .avm_burstcount(bc), .avm_write(wr), .avm_writedata(wdata),
	.avm_byteenable(be), .avm_waitrequest(waitreq)
);

// Memory model: byte array relative to BASE
reg [7:0] mem [0:NBYTES-1];
reg [7:0] expect_mem [0:NBYTES-1];
integer i, writes = 0, errors = 0, bad_addr = 0;

always @(posedge mclk) begin
	waitreq <= ($random & 3) == 0;           // stall ~25% of cycles
	if (wr && !waitreq) begin
		writes = writes + 1;
		if (addr < BASE/32 || addr >= BASE/32 + NBYTES/32 || be !== 32'hFFFFFFFF || bc !== 8'd1)
			bad_addr = bad_addr + 1;
		else
			for (i = 0; i < 32; i = i + 1)
				mem[(addr - BASE/32)*32 + i] = wdata[8*i +: 8];
	end
end

integer f, x, y, n;

task video_frame(input integer fnum, input integer record);
	begin
		frame = fnum;
		@(negedge vclk) vs = 0;
		repeat (VBLANK) @(negedge vclk);
		vs = 1;
		repeat (HBLANK) @(negedge vclk);
		for (y = 0; y < H; y = y + 1) begin
			for (x = 0; x < W; x = x + 1) begin
				de = 1; pixel = $random;
				if (record) begin
					n = (y*W + x) * 3;
					expect_mem[n] = pixel[23:16]; expect_mem[n+1] = pixel[15:8]; expect_mem[n+2] = pixel[7:0];
				end
				@(negedge vclk);
			end
			de = 0;
			repeat (HBLANK) @(negedge vclk);
		end
	end
endtask

task check(input integer want_frame);
	begin
		if (!done || busy || overflow) begin
			$display("FAIL flags: done=%b busy=%b overflow=%b", done, busy, overflow); errors = errors + 1;
		end
		if (fframe !== want_frame) begin
			$display("FAIL frame %0d, want %0d", fframe, want_frame); errors = errors + 1;
		end
		for (i = 0; i < NBYTES; i = i + 1)
			if (mem[i] !== expect_mem[i]) begin
				if (errors < 10) $display("FAIL byte %0d: got %h want %h", i, mem[i], expect_mem[i]);
				errors = errors + 1;
			end
	end
endtask

initial begin
	repeat (4) @(negedge mclk);
	reset = 0;

	// Grab issued mid-frame: the writer must wait for the next frame start
	fork
		begin video_frame(5, 0); video_frame(6, 1); video_frame(7, 0); end
		begin
			repeat (300) @(negedge mclk);
			grab = 1; @(negedge mclk) grab = 0;
		end
	join
	repeat (200) @(negedge mclk);
	check(6);
	$display("grab 1: %0d words written, %0d bad writes", writes, bad_addr);

	// Leave a stray word in the FIFO (what a port reset mid-capture did on the
	// board): the next grab must discard it instead of shifting the frame
	@(negedge vclk) force dut.u_fifo.iWR = 1'b1;
	@(negedge vclk) release dut.u_fifo.iWR;
	repeat (20) @(negedge mclk);

	// Second grab: different data and frame number
	writes = 0;
	grab = 1; @(negedge mclk) grab = 0;
	repeat (20) @(negedge mclk);           // request reaches the video side first
	video_frame(8, 1); video_frame(9, 0);
	repeat (200) @(negedge mclk);
	check(8);
	$display("grab 2: %0d words written, %0d bad writes", writes, bad_addr);

	$display("%0d errors (expect %0d words per frame)", errors + bad_addr, NBYTES/32);
	$finish;
end

endmodule
