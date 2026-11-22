// AES-128 encryption of a video stream (DE/HS/VS + 24-bit RGB).
//
// CTR mode (default): pixel n of frame f is XORed with the first 3 bytes of
//     AES(key, {NONCE, f, n})     NONCE 64 bits, f 32 bits, n zero-extended to 32 bits
// so bytes 0/1/2 of the keystream block mask R/G/B. f counts frames since
// reset and n is the pixel index (row*640 + col). Decryption is the same XOR.
//
// iDECRYPT runs a second "receiver" AES on the same counter and XORs again, as
// a receiver would. With iRX_WRONG_KEY the receiver uses a different key and
// the image stays scrambled.
//
// iECB shows each pixel replaced by AES(key, colour) instead. The colour is
// quantised to 3 bits per channel so flat areas map to the same ciphertext,
// which shows why ECB leaks the image. (The output keeps only 24 of the 128
// ciphertext bits, so this view is for comparison only, not decryptable.)
//
// The key and nonce start as the KEY/NONCE parameters (a public test key).
// iLOAD replaces them with iKEY/iNONCE (from the ARM) and restarts the frame
// counter, so a new session never reuses a keystream; iLOAD_DEFAULT goes back
// to the parameters.
//
// oCIPHER always carries the CTR ciphertext, whatever the display switches
// select, aligned with oRGB; oFRAME is the frame counter used for the frame
// currently at the output (it only changes during vertical blanking).
//
// All outputs are registered and delayed by the same amount (LATENCY clocks).
module video_crypt #(
	parameter [127:0] KEY   = 128'h2b7e151628aed2a6abf7158809cf4f3c,
	parameter [63:0]  NONCE = 64'h494E535045522121   // "INSPER!!"
)(
	input             iCLK,
	input             iRST_N,
	// Controls (synchronous to iCLK)
	input             iENCRYPT,
	input             iECB,
	input             iDECRYPT,
	input             iRX_WRONG_KEY,
	// Key from the ARM (iKEY/iNONCE must be stable around iLOAD)
	input     [127:0] iKEY,
	input      [63:0] iNONCE,
	input             iLOAD,          // one-clock pulse
	input             iLOAD_DEFAULT,  // one-clock pulse
	// Video in
	input             iDE,
	input             iHS,
	input             iVS,         // active low
	input      [23:0] iRGB,
	// Video out
	output reg        oDE,
	output reg        oHS,
	output reg        oVS,
	output reg [23:0] oRGB,
	output reg [23:0] oCIPHER,
	output     [31:0] oFRAME,
	// Status
	output            oKEYS_READY,
	output reg        oHPS_KEY       // the ARM's key is in use
);

localparam AES_LAT = 11;

//-----------------------------------------------------------------------------
// Key schedules: transmitter key and receiver key (optionally wrong)
//-----------------------------------------------------------------------------
wire [1407:0] tx_rk, rx_rk;
wire          tx_ready, rx_ready;
reg           start_tx = 1'b1;
reg           start_rx = 1'b1;
reg           rx_wrong_d = 1'b0;
reg [127:0]   key_r   = KEY;
reg  [63:0]   nonce_r = NONCE;
wire          new_key = iLOAD || iLOAD_DEFAULT;

initial oHPS_KEY = 1'b0;

always @(posedge iCLK) begin
	if (iLOAD) begin
		key_r    <= iKEY;
		nonce_r  <= iNONCE;
		oHPS_KEY <= 1'b1;
	end else if (iLOAD_DEFAULT) begin
		key_r    <= KEY;
		nonce_r  <= NONCE;
		oHPS_KEY <= 1'b0;
	end

	// Restart the key schedules one clock later, once key_r holds the new key
	start_tx   <= !iRST_N || new_key;
	rx_wrong_d <= iRX_WRONG_KEY;
	start_rx   <= !iRST_N || new_key || (rx_wrong_d != iRX_WRONG_KEY);
end

aes_key_expand u_tx_ke (
	.iCLK        ( iCLK ),
	.iSTART      ( start_tx ),
	.iKEY        ( key_r ),
	.oROUND_KEYS ( tx_rk ),
	.oREADY      ( tx_ready )
);

aes_key_expand u_rx_ke (
	.iCLK        ( iCLK ),
	.iSTART      ( start_rx ),
	.iKEY        ( rx_wrong_d ? key_r ^ 128'h1 : key_r ),
	.oROUND_KEYS ( rx_rk ),
	.oREADY      ( rx_ready )
);

assign oKEYS_READY = tx_ready & rx_ready;

//-----------------------------------------------------------------------------
// Input register and counters
//-----------------------------------------------------------------------------
reg        de0, hs0, vs0, vs_prev;
reg [23:0] rgb0;
reg [18:0] pix0;
reg [18:0] pix_cnt;
reg [31:0] frame;

always @(posedge iCLK) begin
	de0     <= iDE;
	hs0     <= iHS;
	vs0     <= iVS;
	rgb0    <= iRGB;
	pix0    <= pix_cnt;
	vs_prev <= iVS;

	if (!iRST_N || new_key)
		frame <= 32'd0;
	else if (vs_prev && !iVS)
		frame <= frame + 32'd1;

	if (!iVS)
		pix_cnt <= 19'd0;
	else if (iDE)
		pix_cnt <= pix_cnt + 19'd1;
end

wire [127:0] ctr_block = {nonce_r, frame, 13'd0, pix0};

assign oFRAME = frame;
wire [127:0] ecb_block = {rgb0[23:21], rgb0[15:13], rgb0[7:5], 119'd0};

//-----------------------------------------------------------------------------
// AES pipelines
//-----------------------------------------------------------------------------
wire [127:0] tx_out, rx_out;

aes128_enc_pipe u_tx_aes (
	.iCLK        ( iCLK ),
	.iROUND_KEYS ( tx_rk ),
	.iBLOCK      ( iECB ? ecb_block : ctr_block ),
	.oBLOCK      ( tx_out )
);

aes128_enc_pipe u_rx_aes (
	.iCLK        ( iCLK ),
	.iROUND_KEYS ( rx_rk ),
	.iBLOCK      ( ctr_block ),
	.oBLOCK      ( rx_out )
);

//-----------------------------------------------------------------------------
// Delay the video by the AES latency, then combine
//-----------------------------------------------------------------------------
reg [26:0] dly [0:AES_LAT-1];
integer i;

always @(posedge iCLK) begin
	dly[0] <= {de0, hs0, vs0, rgb0};
	for (i = 1; i < AES_LAT; i = i + 1)
		dly[i] <= dly[i-1];
end

wire        de_d  = dly[AES_LAT-1][26];
wire        hs_d  = dly[AES_LAT-1][25];
wire        vs_d  = dly[AES_LAT-1][24];
wire [23:0] rgb_d = dly[AES_LAT-1][23:0];

wire [23:0] cipher = rgb_d ^ tx_out[127:104];

always @(posedge iCLK) begin
	oDE <= de_d;
	oHS <= hs_d;
	oVS <= vs_d;
	oCIPHER <= de_d ? cipher : 24'd0;
	if (!de_d)
		oRGB <= 24'd0;
	else if (!iENCRYPT)
		oRGB <= rgb_d;
	else if (iECB)
		oRGB <= tx_out[127:104];
	else if (iDECRYPT)
		oRGB <= cipher ^ rx_out[127:104];
	else
		oRGB <= cipher;
end

endmodule
