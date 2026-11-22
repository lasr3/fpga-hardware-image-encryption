"""Grab one frame from the board and make the documentation images.

    python capture_demo.py 192.168.10.2 --key <32 hex> --nonce <16 hex> [--out ../../docs/images]

Writes:
    plain.png      decrypted on the computer (= the camera image)
    cipher.png     what travels over the cable (AES-CTR ciphertext)
    ecb.png        the same image in ECB mode, computed here with the same
                   function as the FPGA's ECB view (fpga/rtl/video_crypt.v)
    wrong_key.png  CTR decryption with a key that differs in one bit
    demo.png       the four side by side, with labels
"""
import argparse
import os
import socket

import cv2
import numpy as np
from Crypto.Cipher import AES

from receiver import HEADER, Decryptor, recv_exact


def grab(host: str, port: int, skip: int):
    s = socket.create_connection((host, port), timeout=10)
    for _ in range(skip + 1):          # the first frames may predate a scene change
        magic, version, w, h, bpp, frame, flags, length = HEADER.unpack(recv_exact(s, HEADER.size))
        cipher = recv_exact(s, length)
    s.close()
    if flags & 2:
        raise SystemExit("board is in ECB view: turn SW1 off")
    return w, h, frame, cipher


def ecb_view(key: bytes, rgb: np.ndarray) -> np.ndarray:
    """AES(key, colour quantised to 3 bits per channel), first 3 bytes (as in video_crypt)."""
    q = ((rgb[..., 0] >> 5).astype(np.uint32) << 6) | ((rgb[..., 1] >> 5).astype(np.uint32) << 3) | (rgb[..., 2] >> 5)
    aes = AES.new(key, AES.MODE_ECB)
    table = np.zeros((512, 3), dtype=np.uint8)
    for v in range(512):               # only 512 possible inputs: encrypt each once
        block = (v << 119).to_bytes(16, "big")
        table[v] = np.frombuffer(aes.encrypt(block)[:3], dtype=np.uint8)
    return table[q]


def label(img: np.ndarray, text: str) -> np.ndarray:
    bar = np.full((36, img.shape[1], 3), 255, dtype=np.uint8)
    cv2.putText(bar, text, (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1, cv2.LINE_AA)
    return np.vstack([bar, img])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("host")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--key", required=True)
    ap.add_argument("--nonce", required=True)
    ap.add_argument("--skip", type=int, default=30, help="frames to drop first")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "docs", "images"))
    args = ap.parse_args()

    key, nonce = bytes.fromhex(args.key), bytes.fromhex(args.nonce)
    w, h, frame, cipher = grab(args.host, args.port, args.skip)

    plain = Decryptor(key, nonce, w, h).decrypt(frame, cipher).reshape(h, w, 3)
    enc = np.frombuffer(cipher, dtype=np.uint8).reshape(h, w, 3)
    wrong = key[:-1] + bytes([key[-1] ^ 1])
    bad = Decryptor(wrong, nonce, w, h).decrypt(frame, cipher).reshape(h, w, 3)
    ecb = ecb_view(key, plain)

    os.makedirs(args.out, exist_ok=True)
    panels = [(plain, "plain.png", "Decrypted (camera image)"),
              (enc, "cipher.png", "Sent over Ethernet (AES-CTR)"),
              (ecb, "ecb.png", "Same image in ECB mode"),
              (bad, "wrong_key.png", "CTR, wrong key (1 bit off)")]
    for img, name, _ in panels:
        cv2.imwrite(os.path.join(args.out, name), img[:, :, ::-1])
    # Half size per panel, nearest-neighbour so the ciphertext keeps its noise texture
    sep = np.full((h // 2 + 36, 6, 3), 255, dtype=np.uint8)
    row = []
    for img, _, text in panels:
        row += [label(np.ascontiguousarray(img[::2, ::2]), text), sep]
    demo = np.hstack(row[:-1])
    cv2.imwrite(os.path.join(args.out, "demo.png"), demo[:, :, ::-1])
    print(f"frame {frame}: images written to {os.path.abspath(args.out)}")


if __name__ == "__main__":
    main()
