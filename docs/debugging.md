# Problems found and how they were solved

Most of the work after the design simulated correctly went into problems that
only showed up on the real board. Each entry gives the symptom, how it was
diagnosed, and the fix.

## 1. Green image: camera sampled at the wrong moment

**Symptom:** after the step-3 build, which changed nothing in the camera path,
the image turned green.

**Cause:** Terasic's demo samples the camera data on the rising edge of the pixel
clock, delayed by a chain of logic cells (`CLOCK_DELAY`). The TC358748 bridge
changes its outputs 1-6 ns after that same edge (datasheet, *TpdOUT*), so the
sampling point fell inside the switching window, and where it fell depended on
placement. A one-pixel slip shifts the Bayer pattern, which swaps colours.

**Fix:** sample on the **falling** edge, in the middle of the stable window
(6-41 ns), with the input registers placed in the I/O cells
(`FAST_INPUT_REGISTER`). The result no longer depends on placement.

## 2. Linux and the FPGA using the same memory

**Symptom:** the FPGA needs a DDR3 area to write frames into, but Linux uses all
of the 1 GB.

**Fix:** boot Linux with `mem=1008M` (modified `u-boot.scr`), which leaves
`0x3F000000-0x3FFFFFFF` (16 MB) to the FPGA. `frame_server` checks
`/proc/iomem` before using it.

## 3. FPGA-to-SDRAM port stuck in reset

**Symptom:** frame grabs timed out; the FPGA's writes to DDR3 never completed.

**Cause:** the SDRAM controller's `fpgaportrst` register is left at 0 (all ports
in reset) by Terasic's bootloader handoff.

**Fix:** `devmem 0xFFC25080 32 0x1FF` at every boot (a systemd service), and again
in `frame_server` at startup.

## 4. Sheared image: 641-pixel lines

**Symptom:** received frames were sheared diagonally, and HDMI showed a green
line at the right edge.

**Diagnosis:** a saved frame looked right when re-read with a stride of **641**
pixels instead of 640.

**Cause:** Terasic's `VGA_Controller` counts 0..800 and 0..525, so its blanking
signal leaves 641 x 481 active pixels. The last column and line carry no camera
data, but they were being encrypted and streamed.

**Fix:** a `video_de` signal that excludes column 800 and line 525, feeding the
encryption and the frame writer: exactly 640 x 480.

## 5. Frame buffer: guaranteeing whole frames

**Symptom:** the diagonal split of problem 4 was first taken for *tearing*: the
camera and the display run on different clocks, and with a single frame buffer a
displayed (and encrypted) frame can mix two camera frames.

**Fix:** even after the real cause was found, the buffer was kept as
**double buffered** (`cam_frame_buffer.v`): the camera writes one bank
while the display reads the other, and banks are swapped during vertical sync with
a handshake between the two clock domains. Two 8-bit banks do not fit in the
FPGA's RAM, so pixels are stored with 6 bits. Verified with `tb_cam_frame_buffer.v`
(camera and display at different rates, 0 torn pixels).

## 6. Decryption failing after JTAG reprogramming (two bugs)

**Symptom:** after reprogramming the FPGA over JTAG while Linux was running,
decrypted frames were mostly noise.

**Diagnosis:** with the key known, each received 32-byte word was tested against
the keystream at different offsets:

- bytes 16-23 of every 32-byte word were stale: one 64-bit lane of the
  FPGA-to-SDRAM port was not being written;
- the whole frame was shifted by exactly one word (32 bytes).

**Causes and fixes:**

1. Reconfiguring the FPGA with the ports already released left one write lane
   stuck. Fix: `frame_server` cycles the port reset (`0` then `0x1FF`) at startup.
2. A word left in `frame_writer`'s FIFO from an interrupted capture was written at
   the start of the next frame. Fix: the FIFO is **flushed at every grab** before
   capture starts. `tb_frame_writer.v` reproduces it: 766 errors before the fix,
   0 after.

## 7. Wrong colours: greens magenta, reds green

**Symptom:** decrypted images had pink whites, magenta greens and greenish reds.

**Diagnosis:** in every saved frame, the average red and blue were almost exactly
equal (e.g. 172.9 / 172.9). That is what happens when the Bayer demosaic is one
pixel or one line out of phase: the red and blue outputs both come from **green**
photosites, and green comes from red and blue.

**Fix:** a phase input on the demosaic (`RAW2RGB_J.iPHASE`), driven by the ARM
through the unused GHRD `led_pio` (`0xFF203000`), so all four phases could be
tested on the running board without recompiling. Grabbing one frame per phase
showed that the one-pixel (X) shift is correct. That phase is now the default
after reset.

| Phase | Mean R / G / B | Result |
|---|---|---|
| none (old) | 121.8 / 119.8 / 121.7 | R = B, greens magenta |
| X flipped | 142.1 / 125.9 / 106.4 | **correct** |
| Y flipped | 96.5 / 119.7 / 138.1 | red and blue swapped |
| both | 119.9 / 118.9 / 120.0 | R = B again |

## 8. Old bitstream on the SD card

**Symptom:** fixes worked when the FPGA was programmed over JTAG, but not after a reboot.

**Cause:** U-Boot loads `soc_system.rbf` from the SD card at every boot. Compiling
from the Quartus GUI does not regenerate it, so the card still held an old version.

**Fix:** regenerate the `.rbf` after every compile (`build.sh` does it; from the
GUI, run `quartus_cpf`) and copy it to the card.

## Lessons

- Simulation caught the logic bugs (AES, CTR counter, FIFO, double buffering), but
  timing at the pins, boot-time register state and memory port behaviour only
  showed up on hardware.
- Knowing the key turned the ciphertext into a diagnostic tool: any error in the
  data path shows up as a precise byte offset.
- Making a setting changeable at runtime (the Bayer phase) turned four compile and
  test cycles into four `devmem` commands.
