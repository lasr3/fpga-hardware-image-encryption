`timescale 1ns/1ps
// Checks aes_key_expand + aes128_enc_pipe against vectors from gen_aes_vectors.py,
// streaming one block per clock.
module tb_aes;

localparam NKEYS = 6, N = 256, LAT = 11;

reg clk = 0;
always #5 clk = ~clk;

reg  [127:0] vec [0:NKEYS*(1 + 2*N) - 1];
reg  [127:0] key, blk;
reg          start = 0;
wire [1407:0] rks;
wire         ready;
wire [127:0] ct;

aes_key_expand u_ke (.iCLK(clk), .iSTART(start), .iKEY(key), .oROUND_KEYS(rks), .oREADY(ready));
aes128_enc_pipe u_enc (.iCLK(clk), .iROUND_KEYS(rks), .iBLOCK(blk), .oBLOCK(ct));

integer k, i, j, base, errors = 0;

initial begin
	$readmemh("aes_vectors.hex", vec);
	for (k = 0; k < NKEYS; k = k + 1) begin
		base = k * (1 + 2*N);
		@(negedge clk) key = vec[base]; start = 1;
		@(negedge clk) start = 0;
		wait (ready);
		if (k == 0 && rks[127:0] !== 128'h13111d7fe3944a17f307a78b4d2b30c5)
			begin $display("FAIL round key 10: %h", rks[127:0]); errors = errors + 1; end
		fork
			for (i = 0; i < N; i = i + 1) begin
				@(negedge clk) blk = vec[base + 1 + 2*i];
			end
			begin
				@(negedge clk);
				repeat (LAT) @(negedge clk);
				for (j = 0; j < N; j = j + 1) begin
					if (ct !== vec[base + 2 + 2*j]) begin
						if (errors < 10) $display("FAIL key %0d block %0d: got %h want %h", k, j, ct, vec[base + 2 + 2*j]);
						errors = errors + 1;
					end
					@(negedge clk);
				end
			end
		join
	end
	$display("%0d keys x %0d blocks checked, %0d errors", NKEYS, N, errors);
	$finish;
end

endmodule
