/*
 * frame_server - stream encrypted camera frames from the FPGA over TCP.
 *
 * For every frame: ask the FPGA (crypto_regs GRAB) to copy the next frame of
 * AES-CTR ciphertext into reserved DDR3 at 0x3F000000, wait for it, copy it out
 * and send it to the connected client (host/receiver.py on the Mac).
 *
 *   frame_server [port]     default port 5000
 *   frame_server check      check the memory reservation and grab one frame
 *
 * Message per frame (all integers big-endian):
 *   "D10C"  u16 version=1  u16 width  u16 height  u16 bytes per pixel (3)
 *   u32 frame number (AES counter)  u32 flags  u32 payload length
 *   payload: width*height pixels in raster order, R G B
 * flags: bit 0 incomplete frame, bit 1 ECB view (not CTR), bit 2 key from ARM
 *
 * The key never goes over the network: the receiver must be given the key and
 * nonce printed by crypto_key.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define LW_BRIDGE_BASE  0xFF200000u
#define CRYPTO_OFFSET   0x6000u
#define FRAME_BUF       0x3F000000u     /* above mem=1008M */
#define SDR_CTRL_PAGE   0xFFC25000u     /* HPS SDRAM controller registers */
#define FPGAPORTRST     (0x080 / 4)     /* 0xFFC25080: FPGA-to-SDRAM port resets */
#define F2SDRAM_PORTS   0x1FFu          /* ports used by soc_system (GHRD) */
#define FRAME_SPAN      0x00100000u

#define WIDTH           640
#define HEIGHT          480
#define FRAME_BYTES     (WIDTH * HEIGHT * 3)

/* crypto_regs word offsets, see ip/crypto_regs/crypto_regs.v */
#define REG_ID          0
#define REG_CTRL        1
#define REG_STATUS      2
#define REG_DMA_ADDR    10
#define REG_FRAME       11

#define CRYPTO_ID       0x43525950u
#define CTRL_GRAB       0x4u
#define ST_HPS_KEY      (1u << 1)
#define ST_GRAB_BUSY    (1u << 2)
#define ST_GRAB_DONE    (1u << 3)
#define ST_OVERFLOW     (1u << 4)
#define ST_ECB          (1u << 5)

static volatile uint32_t *regs;
static const volatile uint8_t *fbuf;

static double now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void *map_phys(int fd, uint32_t addr, size_t span)
{
	void *p = mmap(NULL, span, PROT_READ | PROT_WRITE, MAP_SHARED, fd, addr);
	if (p == MAP_FAILED) {
		fprintf(stderr, "mmap 0x%08x: %s\n", addr, strerror(errno));
		exit(1);
	}
	return p;
}

/* The FPGA writes to FRAME_BUF behind Linux's back: refuse to run unless the
 * kernel was told to leave it alone (mem=1008M in the boot script). */
static int buffer_is_reserved(void)
{
	FILE *f = fopen("/proc/iomem", "r");
	char line[256];
	int ok = 1;

	if (!f)
		return 0;
	while (fgets(line, sizeof line, f)) {
		unsigned long start, end;
		if (line[0] != ' ' && strstr(line, "System RAM") &&
		    sscanf(line, "%lx-%lx", &start, &end) == 2 &&
		    start < FRAME_BUF + FRAME_SPAN && end >= FRAME_BUF)
			ok = 0;
	}
	fclose(f);
	return ok;
}

/* Put the FPGA-to-SDRAM ports through reset and release them. The bootloader
 * leaves them in reset, and if the FPGA is reprogrammed over JTAG after they
 * were released, one of the port's write lanes can stay stuck. */
static void reset_f2sdram_ports(volatile uint32_t *sdr)
{
	sdr[FPGAPORTRST] = 0;
	usleep(1000);
	sdr[FPGAPORTRST] = F2SDRAM_PORTS;
	usleep(1000);
}

/* Ask for the next frame and wait for it; returns the status word, or 0 on timeout */
static uint32_t grab(uint32_t *frame)
{
	regs[REG_DMA_ADDR] = FRAME_BUF;
	regs[REG_CTRL] = CTRL_GRAB;
	double t0 = now();
	for (;;) {
		uint32_t st = regs[REG_STATUS];
		if ((st & ST_GRAB_DONE) && !(st & ST_GRAB_BUSY)) {
			*frame = regs[REG_FRAME];
			return st;
		}
		if (now() - t0 > 0.5)
			return 0;
		usleep(500);
	}
}

static int send_all(int s, const void *buf, size_t len)
{
	const uint8_t *p = buf;
	while (len) {
		ssize_t n = send(s, p, len, MSG_NOSIGNAL);
		if (n <= 0)
			return -1;
		p += n;
		len -= n;
	}
	return 0;
}

static void put16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }
static void put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }

static int check(uint8_t *local)
{
	uint32_t frame, st;
	double t0, t1, t2;

	printf("frame buffer 0x%08x reserved: %s\n", FRAME_BUF, buffer_is_reserved() ? "yes" : "NO");
	t0 = now();
	st = grab(&frame);
	t1 = now();
	if (!st) {
		printf("grab timed out: status 0x%08x\n", (unsigned)regs[REG_STATUS]);
		return 1;
	}
	memcpy(local, (const void *)fbuf, FRAME_BYTES);
	t2 = now();
	printf("grab ok: frame %u, status 0x%03x%s%s\n", (unsigned)frame, (unsigned)st,
	       st & ST_OVERFLOW ? " (incomplete!)" : "", st & ST_ECB ? " (ECB view)" : "");
	printf("grab %.1f ms, copy %.1f ms\n", (t1 - t0) * 1e3, (t2 - t1) * 1e3);
	printf("first bytes:");
	for (int i = 0; i < 12; i++)
		printf(" %02x", local[i]);
	printf("\n");
	return 0;
}

int main(int argc, char **argv)
{
	int port = 5000;
	int do_check = argc > 1 && !strcmp(argv[1], "check");
	if (argc > 1 && !do_check)
		port = atoi(argv[1]);

	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		fprintf(stderr, "open /dev/mem: %s (run as root)\n", strerror(errno));
		return 1;
	}
	regs = map_phys(fd, LW_BRIDGE_BASE + CRYPTO_OFFSET, 0x1000);
	if (regs[REG_ID] != CRYPTO_ID) {
		fprintf(stderr, "crypto_regs not found (read 0x%08x): is DE10_NANO_CRYPTO loaded?\n",
		        (unsigned)regs[REG_ID]);
		return 1;
	}
	if (!buffer_is_reserved()) {
		fprintf(stderr, "0x%08x is in use by Linux: boot with mem=1008M (new u-boot.scr)\n", FRAME_BUF);
		return 1;
	}
	fbuf = map_phys(fd, FRAME_BUF, FRAME_SPAN);
	reset_f2sdram_ports(map_phys(fd, SDR_CTRL_PAGE, 0x1000));
	close(fd);

	static uint8_t msg[24 + FRAME_BYTES];
	uint8_t *local = msg + 24;
	if (do_check)
		return check(local);

	int ls = socket(AF_INET, SOCK_STREAM, 0);
	int one = 1;
	setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
	struct sockaddr_in a = { .sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = INADDR_ANY };
	if (bind(ls, (struct sockaddr *)&a, sizeof a) || listen(ls, 1)) {
		fprintf(stderr, "port %d: %s\n", port, strerror(errno));
		return 1;
	}
	signal(SIGPIPE, SIG_IGN);

	for (;;) {
		printf("waiting for a receiver on port %d...\n", port);
		int s = accept(ls, NULL, NULL);
		if (s < 0)
			continue;
		setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
		printf("receiver connected\n");

		unsigned frames = 0;
		double t_report = now();
		for (;;) {
			uint32_t frame, st = grab(&frame);
			if (!st) {
				fprintf(stderr, "grab timed out (status 0x%08x)\n", (unsigned)regs[REG_STATUS]);
				break;
			}
			memcpy(local, (const void *)fbuf, FRAME_BYTES);

			memcpy(msg, "D10C", 4);
			put16(msg + 4, 1);
			put16(msg + 6, WIDTH);
			put16(msg + 8, HEIGHT);
			put16(msg + 10, 3);
			put32(msg + 12, frame);
			put32(msg + 16, (st & ST_OVERFLOW ? 1 : 0) | (st & ST_ECB ? 2 : 0) | (st & ST_HPS_KEY ? 4 : 0));
			put32(msg + 20, FRAME_BYTES);
			if (send_all(s, msg, sizeof msg))
				break;

			frames++;
			if (now() - t_report >= 2.0) {
				printf("%.1f frames/s (last frame %u)\n", frames / (now() - t_report), (unsigned)frame);
				frames = 0;
				t_report = now();
			}
		}
		close(s);
		printf("receiver disconnected\n");
	}
}
