# JLCPCB order (procedure step 7)

Capability numbers verified 2026-09-07 from https://jlcpcb.com/capabilities/pcb-capabilities,
https://jlcpcb.com/capabilities/pcb-assembly-capabilities and https://jlcpcb.com/help/article/pcb-assembly-faqs.
Fab rules change; re-fetch the page before quoting a number in a finding.

## Design rules to set in KiCad before layout

| | 2-layer 1 oz | 4-layer (inner 0.5 oz) |
|---|---|---|
| Min trace / space | 0.10 / 0.10 mm (use 0.15 / 0.15 unless density forces it) | 0.09 / 0.09 mm |
| Via drill / diameter | 0.15 / 0.25 mm minimum (use 0.3 / 0.6 for hand-checkable boards) | same |
| Impedance control | available | available; pick a JLC stackup in board setup |
| Panel | ≤ 250 × 250 mm | same |

## Assembly tiers

| | Economic | Standard |
|---|---|---|
| Smallest passive | 0402 | 0201 |
| Edge plating, rails, fiducials | not available / not required | rails + fiducials required |
| Parts | Basic and preferred-extended free; every other extended part adds a per-unique-part fee (≈ $3) | same |

LCSC part numbers look like `C2913202` (that one is ESP32-S3-WROOM-1-N16R8, extended). Basic/extended status and
stock are live data: look them up on jlcpcb.com/parts at order time, never from memory or from this file.

## File set `fab_export.sh` produces

| File | Contents | What to check |
|---|---|---|
| `gerber/*.GTL .GBL .G1 .G2 .GTS .GBS .GTO .GBO .GTP .GBP .GM1` | copper, mask, silk, paste, Edge.Cuts; Protel extensions, X2 off, silkscreen clipped by mask | one file per copper layer of the stackup; Edge.Cuts present |
| `gerber/*.drl` + drill map | Excellon, mm, decimal, PTH and NPTH merged, absolute origin | drill file present; hole count plausible |
| `gerbers.zip` | the `gerber/` directory | this is what gets uploaded |
| `bom.csv` | `Comment, Designator, Footprint, LCSC Part #, Quantity, MPN`, grouped by value+footprint+LCSC, DNP excluded | no row without an LCSC number unless it is hand-soldered and the note says so |
| `cpl.csv` | `Designator, Val, Package, Mid X, Mid Y, Rotation, Layer` (Top/Bottom), mm, DNP excluded | row count = placed parts; one row per assembled footprint |

Rotation caveat: JLC's zero-rotation convention differs from KiCad's for many footprints (diodes, SOT-23,
QFN, connectors). The CPL is a starting point; the user checks every polarised and asymmetric part in JLC's
placement preview after upload and fixes rotations there or via a footprint rotation field. Bouni's
`kicad-jlcpcb-tools` and the Fabrication Toolkit maintain rotation tables (KiCad 10 support `unverified`).

## Pre-upload table (fill in, all rows must read yes or "accepted by user")

| Item | Evidence |
|---|---|
| ERC exit 0, or every remaining item is a GUI exclusion the user set | `review/erc.json` |
| DRC exit 0 with parity, `unconnected_items` = 0 | `review/drc.json` |
| `pin_diff.py` exit 0 (or no firmware header yet, stated) | script output |
| Copper layer count in `fab_export.sh` output = `fab:` line | script output |
| Edge.Cuts file present, drill file present | script output |
| BOM rows without LCSC listed and each one explained | script output |
| CPL row count = number of assembled footprints | script output |
| Assembly tier (economic/standard) and smallest package are consistent | BOM, note |
| Every polarised part's rotation to be checked in the JLC preview | user |
| Quantity, surface finish, thickness, colour, and whether to include the assembled side both ways decided by the user | user |

Then the user uploads `gerbers.zip`, then `bom.csv` and `cpl.csv` in the assembly step. The skill never uploads,
logs in, or drives the site.

## Shipping to Kazakhstan (personal fact)

JLCPCB ships to KZ; customs adds roughly a week on top of transit (JLC's help page lists 5–7 working days for
customs on some routes). Prefer DHL for anything time-critical and order early; a bad run costs the calendar,
not just the money.
