#!/usr/bin/env bash
# Runs every testbench with Icarus Verilog and checks the results against the
# Python (pycryptodome) reference models.
#   Needs: iverilog, python3 with pycryptodome
#   Usage: fpga/sim/run_all.sh
set -euo pipefail
cd "$(dirname "$0")"
RTL=../rtl
IV="iverilog -g2012 -I $RTL/aes"
PY="${PYTHON:-python3}"

echo "== AES-128 core vs. pycryptodome (random keys and blocks)"
[ -f aes_vectors.hex ] || "$PY" gen_aes_vectors.py aes_vectors.hex
$IV -o tb_aes.vvp tb_aes.v $RTL/aes/aes_key_expand.v $RTL/aes/aes_round.v $RTL/aes/aes128_enc_pipe.v
vvp -n tb_aes.vvp | grep -v "\$finish" | tail -1

echo "== video_crypt: CTR, decrypt, wrong key, ECB, plain"
$IV -o tb_video_crypt.vvp tb_video_crypt.v $RTL/video_crypt.v \
	$RTL/aes/aes_key_expand.v $RTL/aes/aes_round.v $RTL/aes/aes128_enc_pipe.v
vvp -n tb_video_crypt.vvp | grep -v "\$finish" | tail -1
"$PY" check_video_crypt.py video_crypt.log

echo "== key loading: ARM registers -> video clock domain"
$IV -o tb_key_load.vvp tb_key_load.v ../ip/crypto_regs/crypto_regs.v $RTL/toggle_sync.v $RTL/video_crypt.v \
	$RTL/aes/aes_key_expand.v $RTL/aes/aes_round.v $RTL/aes/aes128_enc_pipe.v
vvp -n tb_key_load.vvp | grep -v "\$finish" | tail -1
"$PY" check_key_load.py key_load.log

echo "== cam_frame_buffer: double buffering, no tearing"
$IV -o tb_cam_frame_buffer.vvp tb_cam_frame_buffer.v $RTL/cam_frame_buffer.v
vvp -n tb_cam_frame_buffer.vvp | grep -v "\$finish" | tail -1

echo "== frame_writer: FPGA -> DDR3 writes with random wait states"
$IV -o tb_frame_writer.vvp tb_frame_writer.v $RTL/frame_writer.v $RTL/async_fifo.v $RTL/toggle_sync.v
vvp -n tb_frame_writer.vvp | grep -v "\$finish" | tail -2

rm -f ./*.vvp
