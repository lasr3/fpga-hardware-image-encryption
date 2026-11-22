"""Receive the encrypted camera stream from the DE10-Nano and decrypt it.

    python receiver.py 192.168.10.2 --key <32 hex> --nonce <16 hex>

The key and nonce are the ones printed by crypto_key on the board; they never
travel over the network. Each frame arrives as AES-128-CTR ciphertext
(see sw/frame_server.c for the message format):

    pixel n of frame f  =  RGB  XOR  AES(key, nonce | f | n)[0:3]

so decryption rebuilds that keystream and XORs it again. The window shows the
received ciphertext next to the decrypted image. Keys: q quits, s saves both
images as PNG.

Needs: pip install numpy pycryptodome opencv-python
"""
import argparse
import socket
import struct
import sys
import time

import numpy as np
from Crypto.Cipher import AES

HEADER = struct.Struct(">4sHHHHIII")   # magic, version, w, h, bpp, frame, flags, length
FLAG_INCOMPLETE, FLAG_ECB, FLAG_ARM_KEY = 1, 2, 4


class Decryptor:
    """AES-CTR keystream for whole frames, matching rtl/video_crypt.v."""

    def __init__(self, key: bytes, nonce: bytes, width: int, height: int):
        self.aes = AES.new(key, AES.MODE_ECB)
        n = width * height
        # Counter blocks: nonce (8 bytes) | frame (4, filled per frame) | pixel index (4)
        self.blocks = np.zeros((n, 16), dtype=np.uint8)
        self.blocks[:, :8] = np.frombuffer(nonce, dtype=np.uint8)
        self.blocks[:, 12:] = np.arange(n, dtype=">u4").view(np.uint8).reshape(n, 4)

    def keystream(self, frame: int) -> np.ndarray:
        self.blocks[:, 8:12] = np.frombuffer(struct.pack(">I", frame), dtype=np.uint8)
        ks = np.frombuffer(self.aes.encrypt(self.blocks.tobytes()), dtype=np.uint8)
        return ks.reshape(-1, 16)[:, :3]

    def decrypt(self, frame: int, cipher: bytes) -> np.ndarray:
        c = np.frombuffer(cipher, dtype=np.uint8).reshape(-1, 3)
        return c ^ self.keystream(frame)


def recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = bytearray(n)
    view = memoryview(buf)
    got = 0
    while got < n:
        k = sock.recv_into(view[got:], n - got)
        if k == 0:
            raise ConnectionError("board closed the connection")
        got += k
    return bytes(buf)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("host", help="board IP address, e.g. 192.168.10.2")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--key", required=True, help="32 hex digits, from crypto_key")
    ap.add_argument("--nonce", required=True, help="16 hex digits, from crypto_key")
    args = ap.parse_args()

    key, nonce = bytes.fromhex(args.key), bytes.fromhex(args.nonce)
    if len(key) != 16 or len(nonce) != 8:
        ap.error("key must be 32 hex digits and nonce 16")

    import cv2  # imported here so --help works without OpenCV

    sock = socket.create_connection((args.host, args.port), timeout=10)
    print(f"connected to {args.host}:{args.port}")
    dec = None
    frames, t0, fps = 0, time.time(), 0.0

    while True:
        magic, version, w, h, bpp, frame, flags, length = HEADER.unpack(recv_exact(sock, HEADER.size))
        if magic != b"D10C" or version != 1 or bpp != 3 or length != w * h * 3:
            print("bad header, stopping", file=sys.stderr)
            return 1
        cipher = recv_exact(sock, length)
        if dec is None:
            dec = Decryptor(key, nonce, w, h)

        plain = dec.decrypt(frame, cipher).reshape(h, w, 3)
        enc = np.frombuffer(cipher, dtype=np.uint8).reshape(h, w, 3)

        frames += 1
        if time.time() - t0 >= 1.0:
            fps, frames, t0 = frames / (time.time() - t0), 0, time.time()

        # OpenCV wants BGR
        view = np.hstack([enc[:, :, ::-1], plain[:, :, ::-1]]).copy()
        status = f"frame {frame}  {fps:.1f} fps"
        if flags & FLAG_ECB:
            status += "  [board in ECB view: turn SW1 off]"
        if flags & FLAG_INCOMPLETE:
            status += "  [incomplete frame]"
        if not flags & FLAG_ARM_KEY:
            status += "  [board uses the built-in test key]"
        cv2.putText(view, "received (ciphertext)", (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        cv2.putText(view, "decrypted on the Mac", (w + 10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        cv2.putText(view, status, (10, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
        cv2.imshow("DE10-Nano AES-CTR stream", view)

        k = cv2.waitKey(1) & 0xFF
        if k == ord("q"):
            return 0
        if k == ord("s"):
            cv2.imwrite(f"frame{frame}_cipher.png", enc[:, :, ::-1])
            cv2.imwrite(f"frame{frame}_plain.png", plain[:, :, ::-1])
            print(f"saved frame {frame}")


if __name__ == "__main__":
    sys.exit(main())
