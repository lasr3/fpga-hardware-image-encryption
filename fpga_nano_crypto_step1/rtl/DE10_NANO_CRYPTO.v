// DE10-Nano: D8M-GPIO camera -> AES-128 video encryption -> HDMI (640x480@60)
//
// D8M plugged into GPIO 1 (JP7), see docs/pinmap_d8m_gpio1.md.
//
// Controls
//   KEY0 : reset
//   KEY1 : autofocus
//   SW0  : encryption on
//   SW1  : ECB view (instead of CTR)
//   SW2  : receiver view: decrypt the CTR stream again
//   SW3  : receiver uses a wrong key
//
// LEDs
//   [7] video clock 1 Hz   [6] camera pixel clock 1 Hz   [5] MIPI refclk 1 Hz
//   [4] HDMI TX configured [3] AES keys ready            [2] encryption on
//   [1] camera configured  [0] MIPI bridge configured
module DE10_NANO_CRYPTO (
	// Clocks
	input         FPGA_CLK1_50,
	input         FPGA_CLK2_50,

	// Board I/O
	input  [1:0]  KEY,
	input  [3:0]  SW,
	output [7:0]  LED,

	// HDMI TX (ADV7513)
	inout         HDMI_I2C_SCL,
	inout         HDMI_I2C_SDA,
	output        HDMI_TX_CLK,
	output [23:0] HDMI_TX_D,
	output        HDMI_TX_DE,
	output        HDMI_TX_HS,
	output        HDMI_TX_VS,
	input         HDMI_TX_INT,

	// D8M-GPIO on GPIO 1
	inout         CAMERA_I2C_SCL,
	inout         CAMERA_I2C_SDA,
	output        CAMERA_PWDN_n,
	output        MIPI_CS_n,
	inout         MIPI_I2C_SCL,
	inout         MIPI_I2C_SDA,
	output        MIPI_MCLK,
	input         MIPI_PIXEL_CLK,
	input  [9:0]  MIPI_PIXEL_D,
	input         MIPI_PIXEL_HS,
	input         MIPI_PIXEL_VS,
	output        MIPI_REFCLK,
	output        MIPI_RESET_n
);

//=============================================================================
// Signals
//=============================================================================
wire        vga_clk;
wire        pll_locked;
wire        MIPI_PIXEL_CLK_;
wire        DLY_RST_0;
wire        DLY_RST_1;
wire        DLY_RST_2;
wire        RESET_N;
wire  [9:0] FB_RAW;
wire        READ_Request;
wire  [7:0] RED;
wire  [7:0] GREEN;
wire  [7:0] BLUE;
wire  [7:0] R_AUTO;
wire  [7:0] G_AUTO;
wire  [7:0] B_AUTO;
wire  [7:0] R_FOC;
wire  [7:0] G_FOC;
wire  [7:0] B_FOC;
wire        VGA_HS;
wire        VGA_VS;
wire        VGA_BLANK_N;
wire        I2C_RELEASE;
wire        AUTO_FOC;
wire        CAMERA_I2C_SCL_MIPI;
wire        CAMERA_I2C_SCL_AF;
wire        CAMERA_MIPI_RELAESE;
wire        MIPI_BRIDGE_RELEASE;
wire        hdmi_ready;
wire        keys_ready;
wire        D8M_CK_HZ;
wire        D8M_CK_HZ2;
wire        D8M_CK_HZ3;
reg   [3:0] sw_sync;

//=============================================================================
// Clocks
//=============================================================================
sys_pll u_pll (
	.refclk   ( FPGA_CLK1_50 ),
	.rst      ( 1'b0 ),
	.outclk_0 ( vga_clk ),
	.outclk_1 ( MIPI_REFCLK ),
	.locked   ( pll_locked )
);

assign MIPI_MCLK = 1'b0;   // reserved on the D8M

// Pixel clock from the MIPI bridge, delayed to centre it on the data eye
CLOCK_DELAY del1 ( .iCLK ( MIPI_PIXEL_CLK ), .oCLK ( MIPI_PIXEL_CLK_ ) );

//=============================================================================
// Reset
//=============================================================================
RESET_DELAY u2 (
	.iRST   ( KEY[0] & pll_locked ),
	.iCLK   ( FPGA_CLK2_50 ),
	.oRST_0 ( DLY_RST_0 ),
	.oRST_1 ( DLY_RST_1 ),
	.oRST_2 ( DLY_RST_2 ),
	.oREADY ( RESET_N )
);

//=============================================================================
// D8M: MIPI bridge and camera configuration over I2C
//=============================================================================
assign CAMERA_PWDN_n = 1'b1;
assign MIPI_CS_n     = 1'b0;
assign MIPI_RESET_n  = RESET_N;

// The camera I2C bus is shared between the initial setup and the autofocus VCM
assign I2C_RELEASE    = CAMERA_MIPI_RELAESE & MIPI_BRIDGE_RELEASE;
assign CAMERA_I2C_SCL = I2C_RELEASE ? CAMERA_I2C_SCL_AF : CAMERA_I2C_SCL_MIPI;

MIPI_BRIDGE_CAMERA_Config cfin (
	.RESET_N            ( RESET_N ),
	.CLK_50             ( FPGA_CLK2_50 ),
	.MIPI_I2C_SCL       ( MIPI_I2C_SCL ),
	.MIPI_I2C_SDA       ( MIPI_I2C_SDA ),
	.MIPI_I2C_RELEASE   ( MIPI_BRIDGE_RELEASE ),
	.CAMERA_I2C_SCL     ( CAMERA_I2C_SCL_MIPI ),
	.CAMERA_I2C_SDA     ( CAMERA_I2C_SDA ),
	.CAMERA_I2C_RELAESE ( CAMERA_MIPI_RELAESE ),
	.STEP               ( ),
	.VCM_RELAESE        ( )
);

//=============================================================================
// Frame buffer (on-chip): camera clock in, video clock out
//=============================================================================
cam_frame_buffer u_fb (
	.iWR_CLK ( MIPI_PIXEL_CLK_ ),
	.iWR_VS  ( MIPI_PIXEL_VS ),
	.iWR_HS  ( MIPI_PIXEL_HS ),
	.iWR_RAW ( MIPI_PIXEL_D ),
	.iRD_CLK ( vga_clk ),
	.iRD_VS  ( VGA_VS ),
	.iREAD   ( READ_Request ),
	.oRAW    ( FB_RAW )
);

//=============================================================================
// Bayer (RAW) -> RGB
//=============================================================================
RAW2RGB_J u4 (
	.RST          ( VGA_VS ),
	.iDATA        ( FB_RAW ),
	.VGA_CLK      ( vga_clk ),
	.READ_Request ( READ_Request ),
	.VGA_VS       ( VGA_VS ),
	.VGA_HS       ( VGA_HS ),
	.oRed         ( RED ),
	.oGreen       ( GREEN ),
	.oBlue        ( BLUE )
);

//=============================================================================
// Autofocus (voice-coil motor on the camera I2C bus)
//=============================================================================
AUTO_FOCUS_ON vd (
	.CLK_50      ( FPGA_CLK2_50 ),
	.I2C_RELEASE ( I2C_RELEASE ),
	.AUTO_FOC    ( AUTO_FOC )
);

FOCUS_ADJ adl (
	.CLK_50         ( FPGA_CLK2_50 ),
	.RESET_N        ( I2C_RELEASE ),
	.RESET_SUB_N    ( I2C_RELEASE ),
	.AUTO_FOC       ( KEY[1] & AUTO_FOC ),
	.SW_Y           ( 1'b0 ),
	.SW_H_FREQ      ( 1'b0 ),
	.SW_FUC_LINE    ( 1'b0 ),
	.SW_FUC_ALL_CEN ( 1'b0 ),
	.VIDEO_HS       ( VGA_HS ),
	.VIDEO_VS       ( VGA_VS ),
	.VIDEO_CLK      ( vga_clk ),
	.VIDEO_DE       ( READ_Request ),
	.iR             ( R_AUTO ),
	.iG             ( G_AUTO ),
	.iB             ( B_AUTO ),
	.oR             ( R_FOC ),
	.oG             ( G_FOC ),
	.oB             ( B_FOC ),
	.READY          ( ),
	.SCL            ( CAMERA_I2C_SCL_AF ),
	.SDA            ( CAMERA_I2C_SDA ),
	.STATUS         ( )
);

//=============================================================================
// Video timing (640x480@60)
//=============================================================================
VGA_Controller u1 (
	.oRequest    ( READ_Request ),
	.iRed        ( RED ),
	.iGreen      ( GREEN ),
	.iBlue       ( BLUE ),
	.oVGA_R      ( R_AUTO ),
	.oVGA_G      ( G_AUTO ),
	.oVGA_B      ( B_AUTO ),
	.oVGA_H_SYNC ( VGA_HS ),
	.oVGA_V_SYNC ( VGA_VS ),
	.oVGA_SYNC   ( ),
	.oVGA_BLANK  ( VGA_BLANK_N ),
	.iCLK        ( vga_clk ),
	.iRST_N      ( DLY_RST_2 ),
	.H_Cont      ( ),
	.V_Cont      ( )
);

//=============================================================================
// Encryption, straight into the HDMI transmitter
//=============================================================================
always @(posedge vga_clk)
	sw_sync <= SW;

video_crypt u_crypt (
	.iCLK          ( vga_clk ),
	.iRST_N        ( DLY_RST_2 ),
	.iENCRYPT      ( sw_sync[0] ),
	.iECB          ( sw_sync[1] ),
	.iDECRYPT      ( sw_sync[2] ),
	.iRX_WRONG_KEY ( sw_sync[3] ),
	.iDE           ( VGA_BLANK_N ),
	.iHS           ( VGA_HS ),
	.iVS           ( VGA_VS ),
	.iRGB          ( {R_FOC, G_FOC, B_FOC} ),
	.oDE           ( HDMI_TX_DE ),
	.oHS           ( HDMI_TX_HS ),
	.oVS           ( HDMI_TX_VS ),
	.oRGB          ( HDMI_TX_D ),
	.oKEYS_READY   ( keys_ready )
);

// Inverted so the ADV7513 samples in the middle of each pixel (20 ns either side)
assign HDMI_TX_CLK = ~vga_clk;

I2C_HDMI_Config u_hdmi_cfg (
	.iCLK        ( FPGA_CLK1_50 ),
	.iRST_N      ( pll_locked & KEY[0] ),
	.I2C_SCLK    ( HDMI_I2C_SCL ),
	.I2C_SDAT    ( HDMI_I2C_SDA ),
	.HDMI_TX_INT ( HDMI_TX_INT ),
	.READY       ( hdmi_ready )
);

//=============================================================================
// Status
//=============================================================================
CLOCKMEM ck1 ( .CLK ( vga_clk ),         .CLK_FREQ ( 25000000 ), .CK_1HZ ( D8M_CK_HZ  ) );
CLOCKMEM ck2 ( .CLK ( MIPI_PIXEL_CLK_ ), .CLK_FREQ ( 25000000 ), .CK_1HZ ( D8M_CK_HZ2 ) );
CLOCKMEM ck3 ( .CLK ( MIPI_REFCLK ),     .CLK_FREQ ( 20000000 ), .CK_1HZ ( D8M_CK_HZ3 ) );

assign LED = { D8M_CK_HZ, D8M_CK_HZ2, D8M_CK_HZ3, hdmi_ready, keys_ready, sw_sync[0],
               CAMERA_MIPI_RELAESE, MIPI_BRIDGE_RELEASE };

endmodule
