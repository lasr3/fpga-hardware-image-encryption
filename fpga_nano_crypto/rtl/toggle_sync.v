// Brings a toggle from another clock domain into iCLK and turns each change
// into a one-clock pulse (two-flop synchroniser + edge detect).
module toggle_sync (
	input      iCLK,
	input      iTOGGLE,   // asynchronous
	output reg oPULSE
);

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [1:0] sync = 2'b00;
reg       prev = 1'b0;

always @(posedge iCLK) begin
	sync   <= {sync[0], iTOGGLE};
	prev   <= sync[1];
	oPULSE <= sync[1] ^ prev;
end

endmodule
