# Schematic-stage checklist (procedure step 2)

Walk every row. Each row names the evidence that closes it: `net` = the netlist export, `pdf` = the schematic
PDF export you have looked at, `ds` = a fetched datasheet (cite URL and page), `note` = the project's design
note or `## Hardware` section. A row with no evidence is reported as `unverified`, never as pass. Report as a
table `sev | ref/net | finding | source`, errors first, at most ~25 rows, the rest summarised by type.

## A. Power tree

| # | Check | Closes with |
|---|---|---|
| A1 | Every rail has one source; input range, output voltage, rated current are written next to it | pdf, ds of the regulator |
| A2 | Rail budget: sum of consumers per rail (peak, not average) ≤ 80 % of the regulator rating; the note states the numbers | note, ds of each consumer |
| A3 | Input protection: reverse polarity or ideal-diode, TVS on any rail that meets a connector, fuse where a battery can source > 5 A | pdf, ds |
| A4 | Bulk capacitance at each regulator input and output per its datasheet (value, voltage rating ≥ 2× rail, ESR type) | ds, pdf |
| A5 | Decoupling per IC per its datasheet: value, count, and placed on the same sheet next to the pin | ds, pdf |
| A6 | Ground: one ground net, or deliberately split grounds joined at one point named in the note (analog/audio, ESC power return) | net, note |
| A7 | Every power input pin on every symbol is on a net driven by a power output or a PWR_FLAG | net, ERC |

## B. MCU (ESP32-S3: also walk `esp32-s3-rules.md`)

| # | Check | Closes with |
|---|---|---|
| B1 | Module ordering code on the symbol value; pins that variant consumes are unconnected in the netlist | net, ds |
| B2 | Strapping pins: reset-time level for each, nothing fights the default | net, ds |
| B3 | EN RC and reset button; boot button if the note asks for one | pdf |
| B4 | Programming path: USB-Serial-JTAG on 19/20 or a UART bridge on 43/44 with auto-program; the first flash procedure is described in the note | pdf, note |
| B5 | Console path exists and does not collide with a peripheral (UART0 pins reused → USB console must be stated) | net, note |
| B6 | Every GPIO in the firmware pin header is a named net on the MCU; `pin_diff.py` exit 0 | script |
| B7 | Peripheral counts are not exceeded (UARTs, RMT channels, SPI hosts, I2S ports) for what the note lists | note, ds |

## C. Sensors and buses

| # | Check | Closes with |
|---|---|---|
| C1 | I2C: pull-ups on SDA and SCL, one pair per bus, value stated (4.7 kΩ typical at 400 kHz), no two devices at one address; address straps (SDO/CSB/AD0) wired to give the address the firmware header expects | net, ds, header |
| C2 | SPI: one CS per device, MISO not shared with a push-pull device that lacks tri-state, clock ≤ each device's max (BMI270 10 MHz, PMW3901 2 MHz), mode stated | net, ds |
| C3 | Interrupt/data-ready lines routed to the MCU where the firmware uses them (IMU INT1) | net, header |
| C4 | Supply and I/O voltages match each device (PMW3901 core VDD 1.8–2.1 V needs its own LDO; VDDIO 1.8–3.6 V) | ds |
| C5 | Series resistors on lines that leave the board (ESC signal ≤ 100 Ω, LED data), ground return in the same connector | pdf, note |
| C6 | Unused input pins tied per datasheet; unused outputs left open; no floating enables | ds, net |

## D. Connectors and harness

| # | Check | Closes with |
|---|---|---|
| D1 | Every off-board signal has a connector with pin-1 marked and the pinout written in the note; mates with what is on the other end (JST-GH/SH/XH, servo lead, HUB75 IDC) | pdf, note |
| D2 | Power connectors rated for the current (XT30/XT60 for battery, not a pin header) | ds |
| D3 | USB-C: 5.1 kΩ CC pull-downs when the board is a device; ESD on D+/D- | pdf, ds |
| D4 | Test points on every rail, the console, and each bus | pdf |

## E. Manufacturability

| # | Check | Closes with |
|---|---|---|
| E1 | Every symbol has a footprint and an LCSC (or MPN) field; DNP parts are flagged DNP, not deleted | BOM export |
| E2 | Passives are 0402 or larger for economic assembly; 0201 only with standard assembly declared in the note | BOM, `jlcpcb-order.md` |
| E3 | Polarised parts (electrolytics, diodes, LEDs, connectors) have their polarity visible in the symbol and the footprint has a silkscreen mark | pdf, footprint |
| E4 | ERC clean or every remaining item is a justified exclusion the user set in the GUI | `erc_drc.sh erc` |

## F. Domain rows the note must state (the skill asks; the note answers)

- Flight controller: IMU on its own SPI bus with INT routed, IMU supply low-noise (own LDO or filtered), ESC signal
  series resistor and common ground, battery-voltage divider and current sense if the firmware reads them, a kill
  path (RC receiver or hardware switch). Betaflight's manufacturer design guidelines are the public reference:
  https://betaflight.com/docs/development/manufacturer/manufacturer-design-guidelines
- Audio: mic supply 0.1 µF at each VDD, mic spacing 4–6.5 cm for a 2-mic AFE, amp bulk cap per its datasheet,
  amp SD/enable pin driven, star ground between mic and class-D returns. Espressif microphone guidelines:
  https://docs.espressif.com/projects/esp-sr/en/latest/esp32s3/audio_front_end/Espressif_Microphone_Design_Guidelines.html
- LED matrix (HUB75): 5 V distribution sized for the panel's peak current, bulk caps at the connector, level
  buffering decision stated (3.3 V direct on a short cable or 74HCT245).
