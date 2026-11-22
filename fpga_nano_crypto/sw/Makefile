# Build on the board:              make
# Cross-compile from another PC:   make CROSS_COMPILE=arm-linux-gnueabihf-
CROSS_COMPILE ?=
CC     = $(CROSS_COMPILE)gcc
CFLAGS = -O2 -Wall -Wextra -std=gnu99

all: crypto_key frame_server

crypto_key: crypto_key.c
	$(CC) $(CFLAGS) -o $@ $<

frame_server: frame_server.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f crypto_key frame_server
