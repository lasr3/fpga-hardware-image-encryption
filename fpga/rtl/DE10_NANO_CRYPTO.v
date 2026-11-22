// DE10-Nano: D8M-GPIO camera -> AES-128 video encryption -> HDMI (640x480@60)
//
// D8M plugged into GPIO 1 (JP7), see docs/pinmap_d8m_gpio1.md in the repository root.
//
// The ARM (HPS) loads the AES key and nonce through the crypto_regs component
// in soc_system (Platform Designer), at lightweight-bridge offset 0x6000, i.e.
// physical address 0xFF206000. Until then the built-in test key is used.
//
// On request (GRAB), frame_writer copies one frame of CTR ciphertext into the
// ARM's DDR3 through the FPGA-to-SDRAM port, for streaming over Ethernet.
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
//   [7] video clock 1 Hz   [6] camera pixel clock 1 Hz   [5] key from the ARM in use
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
	output        MIPI_RESET_n,

	// HPS: DDR3
	output [14:0] HPS_DDR3_ADDR,
	output [2:0]  HPS_DDR3_BA,
	output        HPS_DDR3_CAS_N,
	output        HPS_DDR3_CK_N,
	output        HPS_DDR3_CK_P,
	output        HPS_DDR3_CKE,
	output        HPS_DDR3_CS_N,
	output [3:0]  HPS_DDR3_DM,
	inout  [31:0] HPS_DDR3_DQ,
	inout  [3:0]  HPS_DDR3_DQS_N,
	inout  [3:0]  HPS_DDR3_DQS_P,
	output        HPS_DDR3_ODT,
	output        HPS_DDR3_RAS_N,
	output        HPS_DDR3_RESET_N,
	input         HPS_DDR3_RZQ,
	output        HPS_DDR3_WE_N,

	// HPS: peripherals
	inout         HPS_CONV_USB_N,
	output        HPS_ENET_GTX_CLK,
	inout         HPS_ENET_INT_N,
	output        HPS_ENET_MDC,
	inout         HPS_ENET_MDIO,
	input         HPS_ENET_RX_CLK,
	input  [3:0]  HPS_ENET_RX_DATA,
	input         HPS_ENET_RX_DV,
	output [3:0]  HPS_ENET_TX_DATA,
	output        HPS_ENET_TX_EN,
	inout         HPS_GSENSOR_INT,
	inout         HPS_I2C0_SCLK,
	inout         HPS_I2C0_SDAT,
	inout         HPS_I2C1_SCLK,
	inout         HPS_I2C1_SDAT,
	inout         HPS_KEY,
	inout         HPS_LED,
	inout         HPS_LTC_GPIO,
	output        HPS_SD_CLK,
	inout         HPS_SD_CMD,
	inout  [3:0]  HPS_SD_DATA,
	output        HPS_SPIM_CLK,
	input         HPS_SPIM_MISO,
	output        HPS_SPIM_MOSI,
	inout         HPS_SPIM_SS,
	input         HPS_UART_RX,
	output        HPS_UART_TX,
	input         HPS_USB_CLKOUT,
	inout  [7:0]  HPS_USB_DATA,
	input         HPS_USB_DIR,
	input         HPS_USB_NXT,
	output        HPS_USB_STP
);

//=============================================================================
// Signals
//=============================================================================
wire        vga_clk;
wire        pll_locked;
wire        MIPI_PIXEL_CLK_;
reg   [9:0] cam_d;
reg         cam_hs;
reg         cam_vs;
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
wire [12:0] VGA_H_CNT;
wire [12:0] VGA_V_CNT;
wire        video_de;
wire        I2C_RELEASE;
wire        AUTO_FOC;
wire        CAMERA_I2C_SCL_MIPI;
wire        CAMERA_I2C_SCL_AF;
wire        CAMERA_MIPI_RELAESE;
wire        MIPI_BRIDGE_RELEASE;
wire        hdmi_ready;
wire        keys_ready;
wire        hps_key;
wire [127:0] hps_key_value;
wire  [63:0] hps_nonce;
wire        hps_commit_toggle;
wire        hps_default_toggle;
wire        hps_commit;
wire        hps_default;
wire [23:0] cipher_rgb;
wire [31:0] cipher_frame;
wire [31:0] grab_addr;
wire        grab;
wire        grab_busy;
wire        grab_done;
wire        grab_overflow;
wire        grab_ecb;
wire [31:0] grab_frame;
wire [26:0] f2s_address;
wire  [7:0] f2s_burstcount;
wire        f2s_write;
wire [255:0] f2s_writedata;
wire [31:0] f2s_byteenable;
wire        f2s_waitrequest;
wire        D8M_CK_HZ;
wire        D8M_CK_HZ2;
reg   [3:0] sw_sync;
wire  [6:0] led_pio;
reg   [1:0] bayer_phase_meta;
reg   [1:0] bayer_phase;

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

// Camera input: the TC358748 bridge changes its outputs 1-6 ns after the rising
// edge of MIPI_PIXEL_CLK (datasheet 9.3, TpdOUT). Terasic's demo samples on that
// rising edge delayed by a chain of logic cells (CLOCK_DELAY), which lands inside
// the 1-6 ns window and depends on placement: a one-pixel slip swaps the Bayer
// colours. Sampling on the falling edge puts the capture in the middle of the
// stable window (6-41 ns), with the input registers in the I/O cells.
assign MIPI_PIXEL_CLK_ = ~MIPI_PIXEL_CLK;

always @(posedge MIPI_PIXEL_CLK_) begin
	cam_d  <= MIPI_PIXEL_D;
	cam_hs <= MIPI_PIXEL_HS;
	cam_vs <= MIPI_PIXEL_VS;
end

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
	.iWR_VS  ( cam_vs ),
	.iWR_HS  ( cam_hs ),
	.iWR_RAW ( cam_d ),
	.iRD_CLK ( vga_clk ),
	.iRD_VS  ( VGA_VS ),
	.iREAD   ( READ_Request ),
	.oRAW    ( FB_RAW )
);

//=============================================================================
// Bayer (RAW) -> RGB
//=============================================================================
// Bayer phase, set by the ARM through the GHRD led_pio (0xFF203000, bits 1:0).
// If the demosaic is one pixel or one line off, red and blue are both taken
// from green photosites (R == B on average, greens look magenta, reds green).
// Measured on the board (2026-11-19): the correct phase is X flipped, i.e. the
// frame buffer delivers the raw data one pixel later than RAW2RGB_J assumes.
// led_pio resets to 0x7F; the XOR makes that reset value give X flipped:
//   devmem 0xFF203000 32 3 -> X flipped (correct, default)
//                        2 -> no flip (old: R == B, greens magenta)
//                        0 -> Y flipped (red and blue swapped)
//                        1 -> X and Y flipped
always @(posedge vga_clk) begin
	bayer_phase_meta <= led_pio[1:0] ^ 2'b10;
	bayer_phase      <= bayer_phase_meta;
end

RAW2RGB_J u4 (
	.RST          ( VGA_VS ),
	.iDATA        ( FB_RAW ),
	.VGA_CLK      ( vga_clk ),
	.READ_Request ( READ_Request ),
	.VGA_VS       ( VGA_VS ),
	.VGA_HS       ( VGA_HS ),
	.iPHASE       ( bayer_phase ),
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
	.H_Cont      ( VGA_H_CNT ),
	.V_Cont      ( VGA_V_CNT )
);

// Terasic's counters run 0..800 and 0..525 (801 x 526 positions), so its blank
// signal leaves 641 x 481 pixels visible. The last column (H_Cont 800) and the
// last line (V_Cont 525) carry no camera data, and everything downstream
// (encryption counter, frame_writer, receiver) expects exactly 640 x 480.
assign video_de = VGA_BLANK_N && (VGA_H_CNT != 13'd800) && (VGA_V_CNT != 13'd525);

//=============================================================================
// HPS (ARM) system from Platform Designer: Terasic GHRD + crypto_regs
//=============================================================================
soc_system u0 (
	.clk_clk                                ( FPGA_CLK1_50 ),
	.reset_reset_n                          ( KEY[0] ),

	.memory_mem_a                           ( HPS_DDR3_ADDR ),
	.memory_mem_ba                          ( HPS_DDR3_BA ),
	.memory_mem_ck                          ( HPS_DDR3_CK_P ),
	.memory_mem_ck_n                        ( HPS_DDR3_CK_N ),
	.memory_mem_cke                         ( HPS_DDR3_CKE ),
	.memory_mem_cs_n                        ( HPS_DDR3_CS_N ),
	.memory_mem_ras_n                       ( HPS_DDR3_RAS_N ),
	.memory_mem_cas_n                       ( HPS_DDR3_CAS_N ),
	.memory_mem_we_n                        ( HPS_DDR3_WE_N ),
	.memory_mem_reset_n                     ( HPS_DDR3_RESET_N ),
	.memory_mem_dq                          ( HPS_DDR3_DQ ),
	.memory_mem_dqs                         ( HPS_DDR3_DQS_P ),
	.memory_mem_dqs_n                       ( HPS_DDR3_DQS_N ),
	.memory_mem_odt                         ( HPS_DDR3_ODT ),
	.memory_mem_dm                          ( HPS_DDR3_DM ),
	.memory_oct_rzqin                       ( HPS_DDR3_RZQ ),

	.hps_0_hps_io_hps_io_emac1_inst_TX_CLK  ( HPS_ENET_GTX_CLK ),
	.hps_0_hps_io_hps_io_emac1_inst_TXD0    ( HPS_ENET_TX_DATA[0] ),
	.hps_0_hps_io_hps_io_emac1_inst_TXD1    ( HPS_ENET_TX_DATA[1] ),
	.hps_0_hps_io_hps_io_emac1_inst_TXD2    ( HPS_ENET_TX_DATA[2] ),
	.hps_0_hps_io_hps_io_emac1_inst_TXD3    ( HPS_ENET_TX_DATA[3] ),
	.hps_0_hps_io_hps_io_emac1_inst_RXD0    ( HPS_ENET_RX_DATA[0] ),
	.hps_0_hps_io_hps_io_emac1_inst_MDIO    ( HPS_ENET_MDIO ),
	.hps_0_hps_io_hps_io_emac1_inst_MDC     ( HPS_ENET_MDC ),
	.hps_0_hps_io_hps_io_emac1_inst_RX_CTL  ( HPS_ENET_RX_DV ),
	.hps_0_hps_io_hps_io_emac1_inst_TX_CTL  ( HPS_ENET_TX_EN ),
	.hps_0_hps_io_hps_io_emac1_inst_RX_CLK  ( HPS_ENET_RX_CLK ),
	.hps_0_hps_io_hps_io_emac1_inst_RXD1    ( HPS_ENET_RX_DATA[1] ),
	.hps_0_hps_io_hps_io_emac1_inst_RXD2    ( HPS_ENET_RX_DATA[2] ),
	.hps_0_hps_io_hps_io_emac1_inst_RXD3    ( HPS_ENET_RX_DATA[3] ),
	.hps_0_hps_io_hps_io_sdio_inst_CMD      ( HPS_SD_CMD ),
	.hps_0_hps_io_hps_io_sdio_inst_D0       ( HPS_SD_DATA[0] ),
	.hps_0_hps_io_hps_io_sdio_inst_D1       ( HPS_SD_DATA[1] ),
	.hps_0_hps_io_hps_io_sdio_inst_CLK      ( HPS_SD_CLK ),
	.hps_0_hps_io_hps_io_sdio_inst_D2       ( HPS_SD_DATA[2] ),
	.hps_0_hps_io_hps_io_sdio_inst_D3       ( HPS_SD_DATA[3] ),
	.hps_0_hps_io_hps_io_usb1_inst_D0       ( HPS_USB_DATA[0] ),
	.hps_0_hps_io_hps_io_usb1_inst_D1       ( HPS_USB_DATA[1] ),
	.hps_0_hps_io_hps_io_usb1_inst_D2       ( HPS_USB_DATA[2] ),
	.hps_0_hps_io_hps_io_usb1_inst_D3       ( HPS_USB_DATA[3] ),
	.hps_0_hps_io_hps_io_usb1_inst_D4       ( HPS_USB_DATA[4] ),
	.hps_0_hps_io_hps_io_usb1_inst_D5       ( HPS_USB_DATA[5] ),
	.hps_0_hps_io_hps_io_usb1_inst_D6       ( HPS_USB_DATA[6] ),
	.hps_0_hps_io_hps_io_usb1_inst_D7       ( HPS_USB_DATA[7] ),
	.hps_0_hps_io_hps_io_usb1_inst_CLK      ( HPS_USB_CLKOUT ),
	.hps_0_hps_io_hps_io_usb1_inst_STP      ( HPS_USB_STP ),
	.hps_0_hps_io_hps_io_usb1_inst_DIR      ( HPS_USB_DIR ),
	.hps_0_hps_io_hps_io_usb1_inst_NXT      ( HPS_USB_NXT ),
	.hps_0_hps_io_hps_io_spim1_inst_CLK     ( HPS_SPIM_CLK ),
	.hps_0_hps_io_hps_io_spim1_inst_MOSI    ( HPS_SPIM_MOSI ),
	.hps_0_hps_io_hps_io_spim1_inst_MISO    ( HPS_SPIM_MISO ),
	.hps_0_hps_io_hps_io_spim1_inst_SS0     ( HPS_SPIM_SS ),
	.hps_0_hps_io_hps_io_uart0_inst_RX      ( HPS_UART_RX ),
	.hps_0_hps_io_hps_io_uart0_inst_TX      ( HPS_UART_TX ),
	.hps_0_hps_io_hps_io_i2c0_inst_SDA      ( HPS_I2C0_SDAT ),
	.hps_0_hps_io_hps_io_i2c0_inst_SCL      ( HPS_I2C0_SCLK ),
	.hps_0_hps_io_hps_io_i2c1_inst_SDA      ( HPS_I2C1_SDAT ),
	.hps_0_hps_io_hps_io_i2c1_inst_SCL      ( HPS_I2C1_SCLK ),
	.hps_0_hps_io_hps_io_gpio_inst_GPIO09   ( HPS_CONV_USB_N ),
	.hps_0_hps_io_hps_io_gpio_inst_GPIO35   ( HPS_ENET_INT_N ),
	.hps_0_hps_io_hps_io_gpio_inst_GPIO40   ( HPS_LTC_GPIO ),
	.hps_0_hps_io_hps_io_gpio_inst_GPIO53   ( HPS_LED ),
	.hps_0_hps_io_hps_io_gpio_inst_GPIO54   ( HPS_KEY ),
	.hps_0_hps_io_hps_io_gpio_inst_GPIO61   ( HPS_GSENSOR_INT ),

	// GHRD peripherals kept as they are; readable from Linux
	.led_pio_external_connection_export     ( led_pio ),
	.dipsw_pio_external_connection_export   ( SW ),
	.button_pio_external_connection_export  ( KEY ),

	.hps_0_h2f_reset_reset_n                ( ),
	.hps_0_f2h_cold_reset_req_reset_n       ( 1'b1 ),
	.hps_0_f2h_debug_reset_req_reset_n      ( 1'b1 ),
	.hps_0_f2h_warm_reset_req_reset_n       ( 1'b1 ),
	.hps_0_f2h_stm_hw_events_stm_hwevents   ( 28'd0 ),

	// AES key registers
	.crypto_key                             ( hps_key_value ),
	.crypto_nonce                           ( hps_nonce ),
	.crypto_commit_toggle                   ( hps_commit_toggle ),
	.crypto_default_toggle                  ( hps_default_toggle ),
	.crypto_status                          ( {SW, 2'b00, hps_key, keys_ready} ),
	.crypto_dma_addr                        ( grab_addr ),
	.crypto_grab                            ( grab ),
	.crypto_grab_busy                       ( grab_busy ),
	.crypto_grab_done                       ( grab_done ),
	.crypto_grab_overflow                   ( grab_overflow ),
	.crypto_grab_ecb                        ( grab_ecb ),
	.crypto_grab_frame                      ( grab_frame ),

	// FPGA-to-SDRAM port (frame_writer only writes)
	.f2sdram_address                        ( f2s_address ),
	.f2sdram_burstcount                     ( f2s_burstcount ),
	.f2sdram_waitrequest                    ( f2s_waitrequest ),
	.f2sdram_readdata                       ( ),
	.f2sdram_readdatavalid                  ( ),
	.f2sdram_read                           ( 1'b0 ),
	.f2sdram_writedata                      ( f2s_writedata ),
	.f2sdram_byteenable                     ( f2s_byteenable ),
	.f2sdram_write                          ( f2s_write )
);

// Key changes from the ARM, brought into the video clock domain
toggle_sync u_commit_sync  ( .iCLK ( vga_clk ), .iTOGGLE ( hps_commit_toggle ),  .oPULSE ( hps_commit ) );
toggle_sync u_default_sync ( .iCLK ( vga_clk ), .iTOGGLE ( hps_default_toggle ), .oPULSE ( hps_default ) );

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
	.iKEY          ( hps_key_value ),
	.iNONCE        ( hps_nonce ),
	.iLOAD         ( hps_commit ),
	.iLOAD_DEFAULT ( hps_default ),
	.iDE           ( video_de ),
	.iHS           ( VGA_HS ),
	.iVS           ( VGA_VS ),
	.iRGB          ( {R_FOC, G_FOC, B_FOC} ),
	.oDE           ( HDMI_TX_DE ),
	.oHS           ( HDMI_TX_HS ),
	.oVS           ( HDMI_TX_VS ),
	.oRGB          ( HDMI_TX_D ),
	.oCIPHER       ( cipher_rgb ),
	.oFRAME        ( cipher_frame ),
	.oKEYS_READY   ( keys_ready ),
	.oHPS_KEY      ( hps_key )
);

//=============================================================================
// Ciphertext frames to DDR3 (for the ARM to stream over Ethernet)
//=============================================================================
frame_writer u_fw (
	.iVCLK           ( vga_clk ),
	.iDE             ( HDMI_TX_DE ),
	.iVS             ( HDMI_TX_VS ),
	.iPIXEL          ( cipher_rgb ),
	.iFRAME          ( cipher_frame ),
	.iECB            ( sw_sync[1] ),
	.iMCLK           ( FPGA_CLK1_50 ),
	.iRESET          ( !KEY[0] ),
	.iGRAB           ( grab ),
	.iADDR           ( grab_addr ),
	.oBUSY           ( grab_busy ),
	.oDONE           ( grab_done ),
	.oOVERFLOW       ( grab_overflow ),
	.oFRAME_ECB      ( grab_ecb ),
	.oFRAME          ( grab_frame ),
	.avm_address     ( f2s_address ),
	.avm_burstcount  ( f2s_burstcount ),
	.avm_write       ( f2s_write ),
	.avm_writedata   ( f2s_writedata ),
	.avm_byteenable  ( f2s_byteenable ),
	.avm_waitrequest ( f2s_waitrequest )
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

assign LED = { D8M_CK_HZ, D8M_CK_HZ2, hps_key, hdmi_ready, keys_ready, sw_sync[0],
               CAMERA_MIPI_RELAESE, MIPI_BRIDGE_RELEASE };

endmodule
