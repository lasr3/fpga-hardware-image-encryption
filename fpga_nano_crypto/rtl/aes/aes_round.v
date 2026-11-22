// One registered AES encryption round:
// SubBytes -> ShiftRows -> MixColumns (skipped when FINAL) -> AddRoundKey.
//
// State layout follows FIPS-197: byte k of the 128-bit word is bits
// [127-8k -: 8], and bytes are stored column by column (k = row + 4*col).
module aes_round #(
	parameter FINAL = 0
)(
	input              iCLK,
	input      [127:0] iSTATE,
	input      [127:0] iROUND_KEY,
	output reg [127:0] oSTATE
);

`include "aes_sbox.vh"

// Multiply by x in GF(2^8)
function [7:0] xtime;
	input [7:0] b;
	xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
endfunction

function [7:0] get_byte;
	input [127:0] w;
	input integer k;
	get_byte = w[127 - 8*k -: 8];
endfunction

reg [127:0] shifted;
reg [127:0] mixed;
integer r, c;
reg [7:0] a0, a1, a2, a3, t;

always @(*) begin
	// SubBytes + ShiftRows: row r is rotated left by r columns
	for (c = 0; c < 4; c = c + 1)
		for (r = 0; r < 4; r = r + 1)
			shifted[127 - 8*(r + 4*c) -: 8] = aes_sbox(get_byte(iSTATE, r + 4*((c + r) % 4)));

	// MixColumns
	for (c = 0; c < 4; c = c + 1) begin
		a0 = get_byte(shifted, 4*c);
		a1 = get_byte(shifted, 4*c + 1);
		a2 = get_byte(shifted, 4*c + 2);
		a3 = get_byte(shifted, 4*c + 3);
		t  = a0 ^ a1 ^ a2 ^ a3;
		mixed[127 - 8*(4*c)     -: 8] = a0 ^ t ^ xtime(a0 ^ a1);
		mixed[127 - 8*(4*c + 1) -: 8] = a1 ^ t ^ xtime(a1 ^ a2);
		mixed[127 - 8*(4*c + 2) -: 8] = a2 ^ t ^ xtime(a2 ^ a3);
		mixed[127 - 8*(4*c + 3) -: 8] = a3 ^ t ^ xtime(a3 ^ a0);
	end
end

always @(posedge iCLK)
	oSTATE <= (FINAL ? shifted : mixed) ^ iROUND_KEY;

endmodule
