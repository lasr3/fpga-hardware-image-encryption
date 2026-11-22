/*
 * crypto_key - load the AES-128 video encryption key from the ARM (HPS).
 *
 * Talks to the crypto_regs component in the FPGA through the lightweight
 * HPS-to-FPGA bridge (base 0xFF200000, component at offset 0x6000).
 *
 *   crypto_key                    random key and nonce from /dev/urandom
 *   crypto_key set KEY [NONCE]    KEY = 32 hex digits, NONCE = 16 (random if omitted)
 *   crypto_key default            back to the built-in test key
 *   crypto_key status             show the registers
 *
 * Must run as root (uses /dev/mem). The printed key and nonce are what a
 * receiver needs to decrypt the HDMI stream.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define LW_BRIDGE_BASE  0xFF200000u
#define CRYPTO_OFFSET   0x6000u
#define MAP_SPAN        0x1000u

/* Word offsets, see fpga/ip/crypto_regs/crypto_regs.v */
#define REG_ID          0
#define REG_CTRL        1
#define REG_STATUS      2
#define REG_KEY0        4
#define REG_NONCE_HI    8
#define REG_NONCE_LO    9

#define CRYPTO_ID       0x43525950u     /* "CRYP" */
#define CTRL_COMMIT     0x1u
#define CTRL_DEFAULT    0x2u
#define ST_KEYS_READY   0x1u
#define ST_HPS_KEY      0x2u

static volatile uint32_t *regs;

static int parse_hex(const char *s, uint8_t *out, size_t len)
{
	if (strlen(s) != 2 * len)
		return -1;
	for (size_t i = 0; i < len; i++) {
		unsigned int b;
		if (sscanf(s + 2 * i, "%2x", &b) != 1)
			return -1;
		out[i] = (uint8_t)b;
	}
	return 0;
}

static uint32_t be32(const uint8_t *p)
{
	return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static void print_hex(const char *label, const uint8_t *p, size_t len)
{
	printf("%s", label);
	for (size_t i = 0; i < len; i++)
		printf("%02x", p[i]);
	printf("\n");
}

static int random_bytes(uint8_t *p, size_t len)
{
	int fd = open("/dev/urandom", O_RDONLY);
	if (fd < 0)
		return -1;
	ssize_t n = read(fd, p, len);
	close(fd);
	return n == (ssize_t)len ? 0 : -1;
}

static void show_status(void)
{
	uint32_t st = regs[REG_STATUS];
	uint8_t key[16], nonce[8];

	for (int i = 0; i < 4; i++) {
		uint32_t w = regs[REG_KEY0 + i];
		key[4 * i] = w >> 24; key[4 * i + 1] = w >> 16; key[4 * i + 2] = w >> 8; key[4 * i + 3] = w;
	}
	for (int i = 0; i < 2; i++) {
		uint32_t w = regs[REG_NONCE_HI + i];
		nonce[4 * i] = w >> 24; nonce[4 * i + 1] = w >> 16; nonce[4 * i + 2] = w >> 8; nonce[4 * i + 3] = w;
	}
	printf("keys ready : %s\n", st & ST_KEYS_READY ? "yes" : "no");
	printf("key in use : %s\n", st & ST_HPS_KEY ? "loaded from the ARM" : "built-in test key");
	printf("switches   : SW3..SW0 = %u%u%u%u\n",
	       (st >> 11) & 1, (st >> 10) & 1, (st >> 9) & 1, (st >> 8) & 1);
	print_hex("key regs   : ", key, sizeof key);
	print_hex("nonce regs : ", nonce, sizeof nonce);
}

static int load_key(const uint8_t key[16], const uint8_t nonce[8])
{
	for (int i = 0; i < 4; i++)
		regs[REG_KEY0 + i] = be32(key + 4 * i);
	regs[REG_NONCE_HI] = be32(nonce);
	regs[REG_NONCE_LO] = be32(nonce + 4);
	regs[REG_CTRL] = CTRL_COMMIT;

	/* The key schedule takes a few hundred ns; wait for the status bits */
	for (int i = 0; i < 100; i++) {
		uint32_t st = regs[REG_STATUS];
		if ((st & (ST_KEYS_READY | ST_HPS_KEY)) == (ST_KEYS_READY | ST_HPS_KEY))
			return 0;
		usleep(1000);
	}
	return -1;
}

static void usage(const char *prog)
{
	fprintf(stderr,
	        "usage: %s                    load a random key and nonce\n"
	        "       %s set KEY [NONCE]    KEY: 32 hex digits, NONCE: 16 hex digits\n"
	        "       %s default            use the built-in test key\n"
	        "       %s status             show the registers\n",
	        prog, prog, prog, prog);
}

int main(int argc, char **argv)
{
	uint8_t key[16], nonce[8];
	const char *cmd = argc > 1 ? argv[1] : "random";

	if (strcmp(cmd, "random") && strcmp(cmd, "set") && strcmp(cmd, "default") && strcmp(cmd, "status")) {
		usage(argv[0]);
		return 2;
	}
	if (!strcmp(cmd, "set") && (argc < 3 || parse_hex(argv[2], key, sizeof key) ||
	                            (argc > 3 && parse_hex(argv[3], nonce, sizeof nonce)))) {
		usage(argv[0]);
		return 2;
	}

	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		fprintf(stderr, "open /dev/mem: %s (run as root)\n", strerror(errno));
		return 1;
	}
	void *map = mmap(NULL, MAP_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
	                 LW_BRIDGE_BASE + CRYPTO_OFFSET);
	close(fd);
	if (map == MAP_FAILED) {
		fprintf(stderr, "mmap: %s\n", strerror(errno));
		return 1;
	}
	regs = map;

	if (regs[REG_ID] != CRYPTO_ID) {
		fprintf(stderr, "crypto_regs not found at 0x%08x (read 0x%08x): is DE10_NANO_CRYPTO programmed?\n",
		        LW_BRIDGE_BASE + CRYPTO_OFFSET, (unsigned)regs[REG_ID]);
		return 1;
	}

	if (!strcmp(cmd, "status")) {
		show_status();
		return 0;
	}
	if (!strcmp(cmd, "default")) {
		regs[REG_CTRL] = CTRL_DEFAULT;
		usleep(1000);
		show_status();
		return 0;
	}

	if (!strcmp(cmd, "random") && random_bytes(key, sizeof key)) {
		fprintf(stderr, "cannot read /dev/urandom\n");
		return 1;
	}
	/* A fresh nonce every session, so no keystream is ever reused */
	if (argc <= 3 && random_bytes(nonce, sizeof nonce)) {
		fprintf(stderr, "cannot read /dev/urandom\n");
		return 1;
	}

	if (load_key(key, nonce)) {
		fprintf(stderr, "key written but the FPGA did not confirm it\n");
		return 1;
	}
	print_hex("key   = ", key, sizeof key);
	print_hex("nonce = ", nonce, sizeof nonce);
	printf("loaded; frame counter restarted at 0\n");
	return 0;
}
