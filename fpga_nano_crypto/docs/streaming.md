# Encrypted stream: DE10-Nano → Mac

```
camera → video_crypt (AES-128-CTR) → frame_writer → FPGA-to-SDRAM → DDR3 @ 0x3F000000
      ARM: frame_server (GRAB, copy, TCP :5000) → Ethernet → Mac: host/receiver.py (decrypt, show)
```

The key and nonce stay on the two ends: `crypto_key` prints them on the board and
they are typed into `receiver.py`. Only ciphertext crosses the cable.

## 1. Reserve the frame buffer (SD card, once)
Replace `u-boot.scr` on the card's FAT partition with `sw/boot/u-boot.scr`
(built from `sw/boot/boot.script` by `make_bootscr.py`). The only change from
Terasic's script: Linux boots with `mem=1008M`, so it never uses
0x3F000000–0x3FFFFFFF, where the FPGA writes frames. Check on the board:
`grep "System RAM" /proc/iomem` → `00000000-3effffff`.

## 2. Network (direct cable, static addresses)
- Mac: System Settings → Network → the USB/Thunderbolt Ethernet adapter →
  Details → TCP/IP → Configure IPv4: Manually, IP `192.168.10.1`, mask `255.255.255.0`.
- Board (after each boot):
  `ip addr add 192.168.10.2/24 dev eth0 && ip link set eth0 up`
- Test from the Mac: `ping 192.168.10.2`

## 3. Run
Board:
```
./crypto_key            # prints key and nonce
./frame_server check    # one test grab
./frame_server          # waits for the receiver
```
Mac:
```
python3 receiver.py 192.168.10.2 --key <key> --nonce <nonce>
```
SW1 (ECB view) must be off: the stream only carries CTR ciphertext then.
The HDMI view on the board is independent (SW0/SW2/SW3 still work).
