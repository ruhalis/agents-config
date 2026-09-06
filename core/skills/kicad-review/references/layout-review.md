# Layout-stage checklist (procedure step 5)

Evidence: `stats` = `kicad-cli pcb export stats --format json`, `pdf` = per-layer PDF export you have looked at,
`drc` = `erc_drc.sh drc`, `ds` = fetched datasheet, `note` = the design note. Same report format as the
schematic stage. Layout judgement (placement, routing quality) is the user's; this list is what a reviewer can
verify from exports.

## A. Board and stackup

| # | Check | Closes with |
|---|---|---|
| A1 | Edge.Cuts is one closed outline; board size and mounting holes match the note (hole diameter, pattern, keep-out around them) | pdf, note |
| A2 | Copper layer count matches the note and `fab:` line; stackup set in board setup for a 4-layer board (JLC JLC04161H-7628 or as ordered) | stats, note |
| A3 | Track/clearance/via design rules set to the fab's capability for the chosen layer count and copper weight (see `jlcpcb-order.md`) | drc rules, note |
| A4 | Fiducials (3, asymmetric) when assembling with standard service; none needed for economic | pdf, `jlcpcb-order.md` |

## B. Placement

| # | Check | Closes with |
|---|---|---|
| B1 | Every decoupling cap on the same side as its IC, within a few mm of the pin, via to ground plane next to it | pdf |
| B2 | Regulators: input cap, output cap, and inductor (buck) in the loop the datasheet draws; thermal copper as required | pdf, ds |
| B3 | RF module: antenna at the board edge with the datasheet keepout clear on all layers; nothing tall next to it | pdf, `esp32-s3-rules.md` |
| B4 | Connectors at edges, oriented so cables can be plugged; pin 1 and polarity on silkscreen | pdf |
| B5 | Crystals and high-speed parts close to their IC; no signal routed under a crystal | pdf |
| B6 | Domain placement stated in the note and met: IMU at the vehicle's centre of rotation, away from ESC current paths, with soft-mount holes; mics with the port hole through the PCB per the mic datasheet; class-D amp away from mic inputs | pdf, note, ds |

## C. Routing and planes

| # | Check | Closes with |
|---|---|---|
| C1 | Continuous ground plane under every high-speed or sensitive signal; no plane splits under USB, SPI, I2S, or crystal traces | pdf |
| C2 | Differential pairs (USB) routed as pairs with matched length and no stubs | pdf |
| C3 | Power traces and pours sized for the current (10 mil per amp at 1 oz for short runs is not a rule; use a width calculator and state the number in the note) | note |
| C4 | High-current returns (ESC, panel 5 V, amp) do not flow under the IMU or analog parts; split or routed away as the note describes | pdf, note |
| C5 | Vias: no via-in-pad without the fab option; thermal reliefs on THT pads in planes; stitching vias along plane edges and under the module EPAD | pdf |
| C6 | Silkscreen: refdes readable, not on pads (`--subtract-soldermask` handles the mask overlap, not the placement), polarity marks present | pdf |
| C7 | Courtyards do not overlap; DRC clean including `unconnected_items` and schematic parity | drc |

## D. Test and assembly

| # | Check | Closes with |
|---|---|---|
| D1 | Test points on every rail and bus, accessible with the board mounted | pdf |
| D2 | Programming access (USB-C or UART header) reachable in the enclosure | pdf, note |
| D3 | Footprint pin-1 orientation checked against the datasheet for every polarised or asymmetric part (LGA IMUs, QFN, connectors, electrolytics); rotation stated for the CPL check | ds, pdf |
| D4 | One footprint per part actually printed 1:1 and checked against the physical part for any hand-made footprint | user |
