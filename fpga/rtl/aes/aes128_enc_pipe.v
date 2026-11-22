// Fully pipelined AES-128 encryption: accepts one block per clock and returns
// its ciphertext LATENCY clocks later (initial AddRoundKey register + 10 rounds).
//
// iROUND_KEYS comes from aes_key_expand and must stay constant while blocks are
// in flight.
module aes128_enc_pipe (
	input          iCLK,
	input  [1407:0] iROUND_KEYS,
	input  [127:0] iBLOCK,
	output [127:0] oBLOCK
);

localparam LATENCY = 11;

reg  [127:0] s0;
wire [127:0] s [0:10];

assign s[0] = s0;

always @(posedge iCLK)
	s0 <= iBLOCK ^ iROUND_KEYS[1407 -: 128];

genvar i;
generate
	for (i = 1; i <= 10; i = i + 1) begin : g_round
		aes_round #(.FINAL(i == 10)) u_round (
			.iCLK      (iCLK),
			.iSTATE    (s[i - 1]),
			.iROUND_KEY(iROUND_KEYS[1407 - 128*i -: 128]),
			.oSTATE    (s[i])
		);
	end
endgenerate

assign oBLOCK = s[10];

endmodule
