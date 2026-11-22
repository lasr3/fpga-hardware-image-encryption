# Writes aes_vectors.hex for tb_aes.v: per key, one key line then N "pt ct" lines.
# Requires pycryptodome.  Usage: python gen_aes_vectors.py out.hex
import os, sys
from Crypto.Cipher import AES

N = 256
keys = [bytes(range(16)),                                   # FIPS-197 C.1
        bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")]  # FIPS-197 Appendix A
keys += [os.urandom(16) for _ in range(4)]

with open(sys.argv[1], "w") as f:
    for k in keys:
        aes = AES.new(k, AES.MODE_ECB)
        f.write(k.hex() + "\n")
        pts = [bytes.fromhex("00112233445566778899aabbccddeeff")] + [os.urandom(16) for _ in range(N - 1)]
        for p in pts:
            f.write(p.hex() + "\n" + aes.encrypt(p).hex() + "\n")
