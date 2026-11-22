# Board setup (Angstrom Linux on the DE10-Nano microSD card)

| File | Install to | Purpose |
|---|---|---|
| `de10-crypto.config` | `/var/lib/connman/` | connman gives eth0 the static IP 192.168.10.2/24 (Mac: 192.168.10.1) |
| `de10-crypto-init.sh` | `/usr/local/bin/` (chmod +x) | releases the FPGA-to-SDRAM ports (`devmem 0xFFC25080 32 0x1FF`) |
| `de10-crypto-init.service` | `/etc/systemd/system/` | runs the script at every boot (`systemctl enable de10-crypto-init`) |

The IP is set through connman because it manages eth0 and removes addresses
added by other means when the link comes up.

Copy from the Mac once the board is reachable:
`scp de10-crypto.config root@192.168.10.2:/var/lib/connman/` etc.
