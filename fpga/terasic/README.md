# Third-party modules (Terasic)

These files come from Terasic's demos for the D8M-GPIO camera and the DE10-Nano
(System CDs: `DE1_SOC_D8M_RTL` and the DE10-Nano `HDMI_TX` demo). They are
included so the project builds on its own. Copyright belongs to Terasic.

| Folder | Contents |
|---|---|
| `d8m/` | Camera and MIPI bridge configuration over I2C, Bayer to RGB (`RAW2RGB_J`), line buffers |
| `autofocus/` | Autofocus (voice-coil motor control over I2C), triggered by KEY1 |
| `hdmi/` | ADV7513 HDMI transmitter configuration over I2C |
| `vga/` | 640x480 @ 60 Hz video timing |
| `common/` | Reset delay, clock monitor, I2C helpers |

## Changes made for this project

- `d8m/RAW2RGB_J.v`: new input `iPHASE[1:0]` that flips the X / Y parity of the
  Bayer demosaic. The camera data arrives one pixel later than the original
  design assumed; see [debugging, problem 7](../../docs/debugging.md#7-wrong-colours-greens-magenta-reds-green).
- `hdmi/HDMI_I2C_WRITE_WDATA.v`: the HDMI demo's `I2C_WRITE_WDATA` module,
  renamed because the camera demo has a different module with the same name.

The original frame buffer (SDRAM controller) and camera clock delay (`CLOCK_DELAY`)
of the DE1-SoC demo are not used: the DE10-Nano has no FPGA-side SDRAM, so
`fpga/rtl/cam_frame_buffer.v` replaces it, and the camera is sampled on the
falling clock edge instead (`fpga/rtl/DE10_NANO_CRYPTO.v`).
