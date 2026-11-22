# D8M-GPIO on DE10-Nano GPIO 1 (JP7)

Header pin numbers from the D8M-GPIO User Manual, table 3-1; FPGA pins from the
DE10-Nano User Manual, figure 3-20. Pin 1 of the D8M must sit on pin 1 of JP7.
Header pins 11/12 (5 V / GND) and 29/30 (3.3 V / GND) are power.

| D8M signal      | Header pin | DE10-Nano GPIO | FPGA pin |
|-----------------|-----------:|----------------|----------|
| MIPI_PIXEL_CLK  | 2          | GPIO_1[1]      | PIN_AC24 |
| MIPI_PIXEL_D[0] | 4          | GPIO_1[3]      | PIN_AD26 |
| MIPI_PIXEL_D[1] | 5          | GPIO_1[4]      | PIN_AG28 |
| MIPI_PIXEL_D[2] | 6          | GPIO_1[5]      | PIN_AF28 |
| MIPI_PIXEL_D[3] | 7          | GPIO_1[6]      | PIN_AE25 |
| MIPI_PIXEL_D[4] | 8          | GPIO_1[7]      | PIN_AF27 |
| MIPI_PIXEL_D[5] | 9          | GPIO_1[8]      | PIN_AG26 |
| MIPI_PIXEL_D[6] | 10         | GPIO_1[9]      | PIN_AH27 |
| MIPI_PIXEL_D[7] | 13         | GPIO_1[10]     | PIN_AG25 |
| MIPI_PIXEL_D[8] | 14         | GPIO_1[11]     | PIN_AH26 |
| MIPI_PIXEL_D[9] | 15         | GPIO_1[12]     | PIN_AH24 |
| MIPI_REFCLK     | 21         | GPIO_1[18]     | PIN_AH21 |
| MIPI_PIXEL_VS   | 23         | GPIO_1[20]     | PIN_AH23 |
| MIPI_PIXEL_HS   | 25         | GPIO_1[22]     | PIN_AF22 |
| MIPI_CS_n       | 26         | GPIO_1[23]     | PIN_AE22 |
| MIPI_RESET_n    | 27         | GPIO_1[24]     | PIN_AG20 |
| CAMERA_PWDN_n   | 28         | GPIO_1[25]     | PIN_AF21 |
| CAMERA_I2C_SCL  | 31         | GPIO_1[26]     | PIN_AG19 |
| CAMERA_I2C_SDA  | 32         | GPIO_1[27]     | PIN_AH19 |
| MIPI_MCLK       | 33         | GPIO_1[28]     | PIN_AG18 |
| MIPI_I2C_SCL    | 35         | GPIO_1[30]     | PIN_AF18 |
| MIPI_I2C_SDA    | 36         | GPIO_1[31]     | PIN_AF20 |

Same header-pin → GPIO index rule as the DE10-Standard build (pins 1–10 → n−1,
13–28 → n−3, 31–40 → n−5), so the mapping matches the camera wiring that
already worked there.
