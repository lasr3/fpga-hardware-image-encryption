# Encryption

## AES-128 core

- `fpga/rtl/aes/aes128_enc_pipe.v`: fully pipelined AES-128 encryption: an
  initial AddRoundKey stage plus 10 rounds, one register per stage. It accepts a
  new 128-bit block **every clock** and returns its ciphertext 11 clocks later.
- `fpga/rtl/aes/aes_key_expand.v`: key schedule computed iteratively, one round
  key per clock (10 clocks after a key change). Keys change rarely, so this costs
  4 S-boxes instead of 40.
- Verified against pycryptodome with random keys and blocks (`fpga/sim/tb_aes.v`).

## CTR mode, pixel by pixel

Each pixel gets its own AES block. The 128-bit counter block is:

| Bytes | 0-7 | 8-11 | 12-15 |
|---|---|---|---|
| Content | nonce (64 bits) | frame number | pixel index (row x 640 + column) |

```
keystream = AES(key, nonce || frame || pixel)
cipher    = (R, G, B) XOR keystream[0:3]
```

Decryption is the same XOR, so the receiver only needs the key, the nonce and the
frame number (sent in clear with each frame). Because the counter is unique for
every pixel of every frame, two identical pixels never produce the same
ciphertext, and the encrypted image looks like noise.

Only 3 of the 16 keystream bytes are used per pixel. That is wasteful but keeps
the design simple: one AES block per pixel clock, no buffering.

## ECB view, for comparison

With SW1 on, the HDMI output shows what ECB (Electronic Codebook) mode would
give: each pixel replaced by `AES(key, colour)`. The colour is reduced to 3 bits
per channel first, so similar colours give the same ciphertext.

In ECB, **identical inputs always give identical outputs**, so areas of the same
colour stay areas of the same (random) colour and the outlines of the scene remain
visible. This is the classic reason not to use ECB for images. Only 24 of the 128
output bits are shown, so the ECB view is for comparison only and cannot be decrypted.

## Switches (HDMI output)

| SW0 | SW1 | SW2 | SW3 | HDMI shows |
|---|---|---|---|---|
| off | | | | Plain camera image |
| on | off | off | | CTR ciphertext (noise) |
| on | on | | | ECB view (outlines visible) |
| on | off | on | off | Decrypted on the board by a second AES pipeline (the "receiver") |
| on | off | on | on | Receiver with a wrong key: stays noise |

The Ethernet stream always carries the CTR ciphertext, whatever HDMI shows.

## Key loading

1. `crypto_key` (ARM) reads 16 + 8 random bytes from `/dev/urandom`.
2. It writes them to `crypto_regs` (KEY0..3, NONCE) and sets `COMMIT`.
3. The commit crosses into the video clock domain as a toggle; `video_crypt`
   copies the key and nonce, restarts the key schedule and **resets the frame
   counter to 0**.
4. `crypto_key` prints the key and nonce for the receiver.

Until a key is loaded, the FPGA uses a public test key (the FIPS-197 example key,
nonce `"INSPER!!"`), and the stream header says so.

## Security notes

- **Keystream reuse:** in CTR mode, encrypting two images with the same counter
  leaks their XOR. The frame counter restarts at each commit, so every session
  must use a new nonce. `crypto_key` always draws a fresh random nonce.
- **Confidentiality only:** CTR mode does not detect tampering. Flipping a bit of
  the ciphertext flips the same bit of the decrypted pixel. A real product would
  add authentication (e.g. AES-GCM or a MAC per frame).
- **Key distribution:** the key is shown on the board console and typed on the
  receiver by hand. It never crosses the network, but this is not a key exchange protocol.
- **Access:** the key is written through `/dev/mem`, so only root on the board can set it.
