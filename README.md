# FPGA hardware image encryption (DE10-Nano)

Real-time AES-128 encryption of a camera stream in FPGA hardware, on a Terasic
DE10-Nano (Cyclone V SoC) with a D8M-GPIO camera. Insper SoC final project.

```
D8M camera -> Bayer to RGB -> AES-128-CTR (FPGA) -> HDMI (ADV7513)
                                    |
                                    +-> DDR3 -> ARM Linux (frame_server) -> Ethernet -> Mac (receiver.py, decrypts)
```

- Encryption is AES-128 in CTR mode, one keystream block per pixel:
  `cipher = RGB XOR AES(key, nonce | frame # | pixel #)[0:3]`.
- The key and nonce are generated on the ARM (`crypto_key`) and written to the
  FPGA through the lightweight HPS-to-FPGA bridge; they never cross the network.
- Switches choose what HDMI shows: plain camera, CTR ciphertext, ECB view (to
  show why ECB leaks the image), on-board decryption, or decryption with a wrong key.

## Folders

| Folder | Contents |
|---|---|
| `fpga_nano_crypto/` | Final project: FPGA design, Platform Designer system, ARM software, Mac receiver |
| `fpga_nano_crypto_step1/` | Step 1 snapshot: fixed key, camera -> encryption -> HDMI, no HPS |

Inside `fpga_nano_crypto/`:

| Path | Contents |
|---|---|
| `rtl/` | Top level, AES-128 pipeline, video encryption, frame buffer, frame writer (FPGA -> DDR3) |
| `terasic/` | Terasic D8M / HDMI / VGA demo modules (with local fixes) |
| `ip/crypto_regs/` | Avalon-MM register block for key, nonce and frame grabs |
| `soc_system.qsys` | Terasic GHRD + crypto_regs |
| `sw/` | ARM programs (`crypto_key`, `frame_server`), boot script, board setup |
| `host/receiver.py` | Mac side: receives and decrypts the stream |
| `sim/` | Testbenches and Python reference models |
| `docs/` | Camera pin map, streaming setup |

## Build

Quartus Prime 25.1 Lite, device 5CSEBA6U23I7. `scripts/build.sh` generates the
Platform Designer system, compiles, and writes `output_files/soc_system.rbf`
for the SD card (loaded by U-Boot at boot). See `docs/streaming.md` for the
board and network setup.
