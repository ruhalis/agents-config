# JLCPCB order (procedure step 7)

Capability numbers verified 2026-09-07 from https://jlcpcb.com/capabilities/pcb-capabilities,
https://jlcpcb.com/capabilities/pcb-assembly-capabilities and https://jlcpcb.com/help/article/pcb-assembly-faqs;
the tier table, via-cost, V-cut and panel rows read 2026-09-22 from the same pages and
https://jlcpcb.com/help/article/pcb-assembly-price. Fab rules change; re-fetch the page before quoting a number in a
finding.

## Design rules to set in KiCad before layout

| | 2-layer 1 oz | 4-layer (inner 0.5 oz) |
|---|---|---|
| Min trace / space | 0.10 / 0.10 mm (use 0.15 / 0.15 unless density forces it) | 0.09 / 0.09 mm |
| Via drill / diameter | 0.15 / 0.25 mm minimum (use 0.3 / 0.6 for hand-checkable boards) | same |
| No-extra-cost vias | drill ≥ 0.3 mm, or 0.2–0.25 mm drill with pad ≥ 0.45 mm (a 0.15 mm drill always costs extra) | same |
| V-cut copper clearance | ≥ 0.4 mm from a V-cut edge | same |
| Impedance control | not offered | available; pick a JLC stackup in board setup |
| Panel | PCBA panel ≤ 250 × 250 mm (bare V-cut panel ≤ 475 × 475 mm) | same |

## Assembly tiers (read 2026-09-22, re-fetch)

| | Economic | Standard |
|---|---|---|
| Smallest passive | 0402 | 0201 |
| Min IC pin pitch / BGA pitch | 0.4 / 0.5 mm | 0.35 / 0.3 mm |
| Min board or panel | 10 × 10 mm | 70 × 70 mm; a smaller board goes on a panel |
| Sides | one side only | one or both sides |
| Delivery format | single board, or panel with mouse bites (no V-cut) | single board, or panel with mouse bites or V-cut |
| Thickness, layers | 0.8–1.6 mm; 2, 4 or 6 layers | wider; read the page |
| Edge plating, rails, fiducials | not available / not required | rails + fiducials required; JLC's panel rails carry them when JLC panelises |
| Feeder fee | ≈ $3 ($3.07) per extended part; basic and preferred-extended free | $1.53 per basic or extended part |

LCSC part numbers look like `C2913202` (that one is ESP32-S3-WROOM-1-N16R8, extended). Basic/extended status and
stock are live data: look them up on jlcpcb.com/parts at order time, never from memory or from this file.

## File set `fab_export.sh` produces

| File | Contents | What to check |
|---|---|---|
| `gerber/*.GTL .GBL .G1 .G2 .GTS .GBS .GTO .GBO .GTP .GBP .GM1` | copper, mask, silk, paste, Edge.Cuts; Protel extensions, X2 off, silkscreen clipped by mask, zones refilled in memory (`--check-zones`) | one file per copper layer of the stackup; Edge.Cuts present; the directory is emptied first and the script fails on any missing or extra file |
| `gerber/*.drl` + drill map | Excellon, mm, decimal, PTH and NPTH merged, absolute origin | drill file present; hole count plausible |
| `gerbers.zip` | the `gerber/` directory | this is what gets uploaded |
| `bom.csv` | `Comment, Designator, Footprint, LCSC Part #, Quantity, MPN`, grouped by value+footprint+LCSC, DNP excluded | designators comma-listed, never ranges (the script fails on a range); no row without an LCSC number unless it is hand-soldered and the note says so |
| `cpl.csv` | `Designator, Val, Package, Mid X, Mid Y, Rotation, Layer` (Top/Bottom), mm, DNP excluded | every BOM designator with an LCSC number has a row (the script fails on a BOM part with an LCSC number and no row, and prints both differences); CPL-only rows (fiducials, logos: excluded from the BOM) are listed and each explained; rows with an LCSC number in the BOM are the assembled parts, the script lists the other BOM parts as hand-soldered |

Rotation caveat: JLC's zero-rotation convention differs from KiCad's for many footprints (diodes, SOT-23,
QFN, connectors). The CPL is a starting point; the user checks every polarised and asymmetric part in JLC's
placement preview after upload and fixes rotations there or via a footprint rotation field. Rotation tables:
Bouni's `kicad-jlcpcb-tools` (KiCad 10 per its README badge), the Fabrication Toolkit (recommended by JLC's
KiCad 10 guide), and kicad-happy's `jlcpcb` skill, read-only.

## Pre-upload table (fill in, all rows must read yes or "accepted by user")

| Item | Evidence |
|---|---|
| ERC exit 0, or every remaining item is a GUI exclusion the user set | `review/erc.json` |
| DRC exit 0 with parity, `unconnected_items` = 0, no stale-fill warning | `review/drc.json`, `review/drc_refilled.json` |
| `pin_diff.py` exit 0 (or no firmware header yet, stated) | script output |
| Copper layer count in `fab_export.sh` output = `fab:` line | script output |
| Edge.Cuts file present, drill file present, gerber set check passed | script output |
| Every BOM designator with an LCSC number is in the CPL, no ranges; BOM-only and CPL-only rows listed and explained | script output |
| BOM rows without LCSC listed and each one explained | script output |
| CPL rows with LCSC = assembled footprints; the other BOM parts listed as hand-soldered | script output |
| Assembly tier (economic/standard) consistent with the smallest package, finest IC/BGA pitch and board or panel size | BOM, note |
| Delivery country offers PCBA (checked on quote page today) | user, quote page |
| Every polarised part's rotation to be checked in the JLC preview | user |
| Quantity, surface finish, thickness, colour, and whether to include the assembled side both ways decided by the user | user |

Then the user uploads `gerbers.zip`, then `bom.csv` and `cpl.csv` in the assembly step. The skill never uploads,
logs in, or drives the site.

## Shipping to Kazakhstan (personal fact)

Bare PCBs and stencils ship to KZ; customs adds 5–7 working days on some routes (JLC shipping help). PCBA delivery
to KZ is blocked: the quote page says assembly is not offered for that delivery country (observed 2026-09-22, per
aquila `ORDER.md`; recheck live on the quote page). Alternatives: a forwarder address in a country JLC assembles
for, Seeed Fusion PCBA, or bare boards plus a stencil and local reflow. Prefer DHL for anything time-critical and
order early; a bad run costs the calendar, not just the money.
