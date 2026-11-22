# Setup and running the demo

## What you need

- Terasic DE10-Nano (rev. C) and its 5 V supply
- Terasic D8M-GPIO camera
- HDMI monitor
- microSD card (4 GB or more)
- Ethernet cable from the board to the computer (a USB Ethernet adapter works)
- A computer with Python 3 to receive the stream

## 1. Connect the hardware

- **Camera:** D8M-GPIO on **GPIO 1 (JP7)**, pin 1 of the camera on pin 1 of the
  header. Pin mapping: [pinmap_d8m_gpio1.md](pinmap_d8m_gpio1.md).
- **HDMI:** monitor on the board's HDMI port.
- **Ethernet:** cable between the board's Ethernet port and the computer.
- **Serial console (optional):** mini-USB UART port, 115200 baud, user `root`, no password.

## 2. Prepare the microSD card

1. Write Terasic's **DE10-Nano "Linux Console (kernel 4.5)"** image, from the
   DE10-Nano System CD / Terasic website, to the card.
2. On the card's FAT partition, replace two files:
   - `soc_system.rbf` with [`prebuilt/soc_system.rbf`](../prebuilt) (or your own build): U-Boot
     loads it into the FPGA at every boot, so no JTAG cable is needed.
   - `u-boot.scr` with [`software/board/boot/u-boot.scr`](../software/board/boot). It is
     Terasic's boot script with one change: Linux boots with `mem=1008M`, so it
     never touches `0x3F000000-0x3FFFFFFF`, where the FPGA writes frames.
     It is built from `boot.script` by `make_bootscr.py`; Terasic's original is kept next to it.
3. Boot the board. Check: `grep "System RAM" /proc/iomem` should show `00000000-3effffff`.

## 3. Board software

Copy `software/board/` to the board (e.g. `scp -r software/board root@192.168.10.2:`),
then on the board:

```
cd board
make                    # builds crypto_key and frame_server with the board's gcc
```

**Run at every boot** (optional but recommended): install the files in
[`software/board/linux-setup/`](../software/board/linux-setup):

| File | Install to | Purpose |
|---|---|---|
| `de10-crypto.config` | `/var/lib/connman/` | Static IP 192.168.10.2/24 on eth0 |
| `de10-crypto-init.sh` | `/usr/local/bin/` (`chmod +x`) | Releases the FPGA-to-SDRAM ports (`devmem 0xFFC25080 32 0x1FF`) |
| `de10-crypto-init.service` | `/etc/systemd/system/` | Runs the script at boot: `systemctl enable de10-crypto-init` |

Without them, run after each boot:
```
ip addr add 192.168.10.2/24 dev eth0 && ip link set eth0 up
devmem 0xFFC25080 32 0x1FF
```

## 4. Network

Direct cable, static addresses:

- Computer: set the Ethernet adapter to manual IPv4, address `192.168.10.1`, mask `255.255.255.0`
  (macOS: System Settings → Network → the adapter → Details → TCP/IP).
- Board: `192.168.10.2` (step 3).
- Test from the computer: `ping 192.168.10.2`.

## 5. Run

On the board:
```
./crypto_key            # loads a random key and nonce into the FPGA and prints them
./frame_server check    # optional: one test grab
./frame_server          # waits for the receiver on TCP port 5000
```

On the computer:
```
cd software/host
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python receiver.py 192.168.10.2 --key <key> --nonce <nonce>
```

The window shows the received ciphertext next to the decrypted image. Keys: `s`
saves both as PNG, `q` quits.

Keep **SW1 off** while streaming: in ECB view the stream does not carry CTR
ciphertext (the receiver warns about it). The HDMI output is independent: SW0,
SW2 and SW3 can be changed freely, see [encryption](encryption.md#switches-hdmi-output).

## 6. Rebuilding the FPGA

- **From the archive:** open `prebuilt/DE10_NANO_CRYPTO.qar` in Quartus Prime 25.1
  Lite (*Project → Restore Archived Project*) and compile.
- **From the sources:** `fpga/scripts/build.sh` (Quartus on the PATH). It
  regenerates `soc_system` with Platform Designer, compiles, and writes
  `fpga/output_files/soc_system.rbf` for the SD card.
- If you compile from the Quartus GUI instead, create the SD card file yourself:
  ```
  quartus_cpf -c -o bitstream_compression=on output_files/DE10_NANO_CRYPTO.sof output_files/soc_system.rbf
  ```
- **JTAG instead of SD card:** `fpga/scripts/program.sh` (the FPGA is device 2 in
  the JTAG chain). After programming over JTAG with Linux running, run
  `frame_server` again: it resets the FPGA-to-SDRAM ports at startup.
- **Without Linux:** `fpga/scripts/sc_crypto.tcl` loads a key over JTAG with System Console.

## Troubleshooting

| Symptom | Check |
|---|---|
| No image on HDMI | LED4 (HDMI configured) and LED1/LED0 (camera configured) should be on; press KEY0 to reset |
| `frame_server`: buffer not reserved | the card does not have the new `u-boot.scr` (`mem=1008M`) |
| `grab timed out` | FPGA-to-SDRAM ports still in reset: `devmem 0xFFC25080 32 0x1FF` |
| Receiver shows noise | wrong key or nonce, or SW1 (ECB) is on |
| Wrong colours (greens magenta) | `devmem 0xFF203000` must read `0x7F` (or write `3`), see [debugging](debugging.md) |
| Blurry image | press KEY1 for autofocus |
