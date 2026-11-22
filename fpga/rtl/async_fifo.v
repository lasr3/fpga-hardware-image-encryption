// Dual-clock FIFO with Gray-coded pointers and show-ahead output
// (oQ holds the oldest word whenever oEMPTY is low; iRD pops it).
module async_fifo #(
	parameter WIDTH = 256,
	parameter AW    = 6        // depth = 2**AW
)(
	// Write side
	input              iWCLK,
	input              iWR,
	input  [WIDTH-1:0] iD,
	output             oFULL,
	// Read side
	input              iRCLK,
	input              iRD,
	output [WIDTH-1:0] oQ,
	output             oEMPTY
);

reg [WIDTH-1:0] mem [0:(1<<AW)-1];

function [AW:0] bin2gray;
	input [AW:0] b;
	bin2gray = b ^ (b >> 1);
endfunction

// Write pointer (binary + Gray) and the read pointer seen from the write side
reg  [AW:0] wbin = 0, wgray = 0;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg  [AW:0] rgray_w1 = 0, rgray_w2 = 0;

// Read pointer and the write pointer seen from the read side
reg  [AW:0] rbin = 0, rgray = 0;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg  [AW:0] wgray_r1 = 0, wgray_r2 = 0;

wire [AW:0] wbin_next = wbin + 1'b1;
wire [AW:0] rbin_next = rbin + 1'b1;

// Full when the write pointer is one lap ahead (top two Gray bits inverted)
assign oFULL  = (wgray == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});
assign oEMPTY = (rgray == wgray_r2);
assign oQ     = mem[rbin[AW-1:0]];

always @(posedge iWCLK) begin
	rgray_w1 <= rgray;
	rgray_w2 <= rgray_w1;
	if (iWR && !oFULL) begin
		mem[wbin[AW-1:0]] <= iD;
		wbin  <= wbin_next;
		wgray <= bin2gray(wbin_next);
	end
end

always @(posedge iRCLK) begin
	wgray_r1 <= wgray;
	wgray_r2 <= wgray_r1;
	if (iRD && !oEMPTY) begin
		rbin  <= rbin_next;
		rgray <= bin2gray(rbin_next);
	end
end

endmodule
