# ESP32-S3 module rules for a schematic review

Verified 2026-09-07 against the ESP32-S3-WROOM-1/1U datasheet v1.8
(https://documentation.espressif.com/esp32-s3-wroom-1_wroom-1u_datasheet_en.pdf, "DS") and the
ESP32-S3 Hardware Design Guidelines, schematic checklist and PCB layout pages
(https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32s3/schematic-checklist.html,
https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32s3/pcb-layout-design.html, "HDG").
Re-fetch the page and cite the section when a finding depends on a number here. Anything marked `unverified` was
not read from the source and must be checked before it becomes a finding.

## Pins that are not free GPIO

| GPIO | Role | Reset-time state | Rule | Source |
|---|---|---|---|---|
| 0 | Strapping: boot mode (with 46) | Weak pull-up = 1 | Boot button to GND is fine; nothing may hold it low at reset | DS Table 4-1 |
| 3 | Strapping: JTAG signal source | Floating, no internal pull | Do not leave it driven by a peripheral at reset; if used, pull deliberately | DS Table 4-1 |
| 45 | Strapping: VDD_SPI 3.3 V / 1.8 V | Weak pull-down = 0 | Never pull up on a 3.3 V-flash module; a high here switches VDD_SPI to 1.8 V | DS Table 4-1 |
| 46 | Strapping: boot mode (with 0), ROM log | Weak pull-down = 0 | Must be low at reset for normal boot (typed I/O/T in DS Table 3-1, so usable after boot with care) | DS Table 4-1, 3-1 |
| 19, 20 | USB D-, D+ (USB-Serial-JTAG and USB OTG) | | Route as a pair to the USB-C connector; series 22–33 Ω per HDG checklist | HDG schematic checklist |
| 43, 44 | UART0 TXD0, RXD0 (ROM console, download mode) | | Keep them for the console unless the design has USB-Serial-JTAG and says so | DS pin table |
| 26–32 | In-package flash SPI | | Not bonded out on WROOM-1/1U (41-pin module has no IO26–IO34) | DS pin table |
| 33, 34 | Octal flash/PSRAM lines | | Not bonded out on WROOM-1/1U | DS pin table |
| 35, 36, 37 | Octal PSRAM (R8 and R16V variants: N4R8, N8R8, N16R8, N16R16V, N16R16VA) | | Unavailable on any module with octal PSRAM (footnote b); free only on quad-PSRAM (R2) and no-PSRAM variants. WROOM-2 modules (e.g. N32R16V) have their own datasheet: `unverified` here | DS pin table note b, Table 1-1 |
| 47, 48 | | | On R16V modules VDD_SPI is 1.8 V and GPIO47/48 run at 1.8 V, not 3.3 V | DS footnote on N16R16VA / R16V |
| 39–42 | JTAG MTCK/MTDO/MTDI/MTMS | | Usable as GPIO; JTAG then moves to USB | DS pin table |
| 1–10 | ADC1 | | Use ADC1 for analog inputs | DS pin table |
| 11–20 | ADC2 | | ADC2 is shared with Wi-Fi; treat as unusable for analog while Wi-Fi is on | DS pin table / HDG |
| 0–21 | RTC GPIO | | Only these can wake from deep sleep | DS pin table |

Strapping pins are latched at reset and must hold their level for the setup/hold window (DS Table 4-2, hold ≥ 3 ms
after EN rises per the guidelines agent's read; re-check the exact figure in DS 4-2 before citing it).

Module variants: the Value field of the symbol must name the exact ordering code (e.g. `ESP32-S3-WROOM-1-N16R8`).
The N/R suffix decides whether IO35–37 exist and whether GPIO47/48 are 1.8 V. A schematic that uses IO35–37 on an
R8 module is an error, not a warning.

Peripheral counts (`unverified` here: taken from the ESP32-S3 Series Datasheet from memory of the peripherals
table; confirm in that datasheet before a finding depends on them): 3 × UART, RMT 4 TX + 4 RX channels, LEDC 8
channels, 2 × I2C, 2 × I2S, SPI2 and SPI3 general-purpose, 1 × TWAI, USB OTG full-speed.

## Power, reset, boot

| Check | Rule | Source |
|---|---|---|
| 3V3 supply | ≥ 500 mA; the module's own transmit peak is 355 mA at 802.11b 20.5 dBm | DS Table (current consumption); HDG power supply |
| 3V3 decoupling | 10 µF at the module's 3V3 entry plus 0.1 µF close to the pin; HDG also lists caps on VDD_SPI and per RF pin, read the checklist for the exact set | HDG schematic checklist |
| EN | 10 kΩ pull-up to 3V3 and 1 µF to GND (RC delay so the strapping pins are stable before EN); never leave EN floating | HDG schematic checklist |
| Boot/reset buttons | Reset: EN to GND. Boot: GPIO0 to GND. Both momentary, both optional on a fully USB-programmed board | HDG |
| Auto-program | Two-transistor DTR/RTS circuit on EN and GPIO0 when a UART bridge is used (DevKitC-1 schematic); with native USB-Serial-JTAG no bridge is needed | https://dl.espressif.com/dl/schematics/SCH_ESP32-S3-DevKitC-1_V1.1_20221130.pdf (transistor part numbers `unverified`) |
| Brown-out | Module has an internal brown-out detector; the 3V3 rail must not sag below its threshold on Wi-Fi bursts, so size the regulator and the bulk cap for the 355 mA step | DS / HDG |

## Layout

| Check | Rule | Source |
|---|---|---|
| Antenna placement | Module antenna hangs off the board edge, or its feed area sits at the edge with copper cleared on all layers under and around it | HDG PCB layout; DS keepout figure |
| Keepout | Datasheet keepout zone under the antenna; ≥ 15 mm clearance from the antenna to enclosure metal and other components in the guidelines | DS pin diagram / HDG |
| WROOM-1U | External antenna variant has no on-board keepout requirement | DS |
| Ground | Solid ground under the module except the antenna area; EPAD (pin 41) tied to GND with a via array (HDG says ≥ 9 vias) | HDG |
| Power traces | Main power trace ≥ 25 mil on a 4-layer board per HDG | HDG |
| USB | D+/D- as a 90 Ω differential pair, short, no stubs | HDG |

## Things a reviewer says out loud

- Which module variant is on the symbol, and which of IO35–37 it frees or consumes.
- Every strapping pin: what is connected, and what its level is at reset.
- Whether UART0 is the console, USB-Serial-JTAG is the console, or both, and how the board is programmed the first time.
- The 3V3 regulator part, its rated current, and the bulk cap after it.
- Where the antenna is and what copper is under it.
