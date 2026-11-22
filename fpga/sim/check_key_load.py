# Checks key_load.log from tb_key_load.v: CTR pixels must match the key that was
# active ("k" lines) and the frame numbers logged by the testbench.
import sys
from Crypto.Cipher import AES

def ks(key, nonce, frame, pix):
    blk = nonce + frame.to_bytes(4, "big") + pix.to_bytes(4, "big")
    return int.from_bytes(AES.new(key, AES.MODE_ECB).encrypt(blk)[:3], "big")

ins, outs = [], []
key = nonce = None
for line in open(sys.argv[1]):
    p = line.split()
    if p[0] == "k":   key, nonce = bytes.fromhex(p[1]), bytes.fromhex(p[2])
    elif p[0] == "i": ins.append((key, nonce, int(p[1]), int(p[2]), int(p[3]), int(p[4], 16)))
    else:             outs.append(int(p[1], 16))
assert len(ins) == len(outs), (len(ins), len(outs))

errors = 0
for (k, n, mode, f, pix, rgb), got in zip(ins, outs):
    c = rgb ^ ks(k, n, f, pix)
    want = c if mode == 0 else rgb
    if got != want:
        errors += 1
        if errors <= 10: print(f"FAIL key {k.hex()[:8]} mode {mode} frame {f} pix {pix}: got {got:06x} want {want:06x}")
print(f"{len(outs)} pixels checked, {errors} errors")
sys.exit(1 if errors else 0)
