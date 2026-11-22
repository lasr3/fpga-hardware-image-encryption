// AES-128 key schedule, computed iteratively (one round key per clock).
//
// Pulse iSTART with iKEY stable; oREADY rises 10 clocks later with all 11 round
// keys in oROUND_KEYS (round 0 in the top 128 bits, round 10 in the bottom).
// The key only changes rarely, so this costs 4 S-boxes instead of 40.
module aes_key_expand (
	input               iCLK,
	input               iSTART,
	input      [127:0]  iKEY,
	output reg [1407:0] oROUND_KEYS,
	output reg          oREADY
);

`include "aes_sbox.vh"

reg [127:0] rk;      // round key being extended
reg [7:0]   rcon;
reg [3:0]   round;   // next round to compute, 1..10; 0 = idle
reg [127:0] next_rk;

initial begin
	oREADY = 1'b0;
	round  = 4'd0;
end

// Next round key from the current one (FIPS-197 section 5.2)
always @(*) begin : expand
	reg [31:0] w0, w1, w2, w3, temp;
	{w0, w1, w2, w3} = rk;
	temp = {aes_sbox(w3[23:16]), aes_sbox(w3[15:8]), aes_sbox(w3[7:0]), aes_sbox(w3[31:24])}
	       ^ {rcon, 24'd0};
	w0 = w0 ^ temp;
	w1 = w1 ^ w0;
	w2 = w2 ^ w1;
	w3 = w3 ^ w2;
	next_rk = {w0, w1, w2, w3};
end

always @(posedge iCLK) begin
	if (iSTART) begin
		rk                    <= iKEY;
		rcon                  <= 8'h01;
		round                 <= 4'd1;
		oREADY                <= 1'b0;
		oROUND_KEYS[1407 -: 128] <= iKEY;
	end else if (round != 4'd0) begin
		rk                    <= next_rk;
		rcon                  <= {rcon[6:0], 1'b0} ^ (rcon[7] ? 8'h1b : 8'h00);
		oROUND_KEYS[1407 - 128*round -: 128] <= next_rk;
		if (round == 4'd10) begin
			round  <= 4'd0;
			oREADY <= 1'b1;
		end else
			round  <= round + 1'b1;
	end
end

endmodule
