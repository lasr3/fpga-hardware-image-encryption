# Checks video_crypt.log from tb_video_crypt.v against a pycryptodome model.
import sys
from Crypto.Cipher import AES

KEY   = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
NONCE = bytes.fromhex("494E535045522121")
WRONG = KEY[:-1] + bytes([KEY[-1] ^ 1])

def ks(key, frame, pix):
    blk = NONCE + frame.to_bytes(4, "big") + pix.to_bytes(4, "big")
    return int.from_bytes(AES.new(key, AES.MODE_ECB).encrypt(blk)[:3], "big")

def ecb(key, rgb):
    r, g, b = rgb >> 21 & 7, rgb >> 13 & 7, rgb >> 5 & 7
    q = (r << 6 | g << 3 | b) << 119
    return int.from_bytes(AES.new(key, AES.MODE_ECB).encrypt(q.to_bytes(16, "big"))[:3], "big")

ins, outs = [], []
for line in open(sys.argv[1]):
    p = line.split()
    if p[0] == "i": ins.append((int(p[1]), int(p[2]), int(p[3]), int(p[4], 16)))
    else:           outs.append(int(p[1], 16))
assert len(ins) == len(outs), (len(ins), len(outs))

errors = 0
for (mode, f, n, rgb), got in zip(ins, outs):
    c = rgb ^ ks(KEY, f, n)
    want = [c, c ^ ks(KEY, f, n), c ^ ks(WRONG, f, n), ecb(KEY, rgb), rgb][mode]
    if got != want:
        errors += 1
        if errors <= 10: print(f"FAIL mode {mode} frame {f} pix {n}: got {got:06x} want {want:06x}")
print(f"{len(outs)} pixels checked, {errors} errors")
ecb_left = {o for (m, f, n, r), o in zip(ins, outs) if m == 3 and (n % 16) < 8}
print(f"ECB: flat area -> {len(ecb_left)} distinct ciphertext value(s)")
sys.exit(1 if errors else 0)
