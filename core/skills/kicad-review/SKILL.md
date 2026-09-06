---
name: kicad-review
description: Reviews KiCad 10 hardware projects on macOS through kicad-cli exports and never edits them — schematic and layout checklists, ERC and DRC reports, netlist-vs-firmware GPIO pin diff, ESP32-S3 pinout and strapping-pin rules, BOM/CPL/gerber export for JLCPCB with LCSC part numbers, datasheet-cited findings. Use whenever the user mentions KiCad, .kicad_sch/.kicad_pcb/.kicad_pro, schematic, PCB, layout, netlist, footprint, symbol, ERC, DRC, BOM, LCSC, JLCPCB, PCBA, gerber, drill, pick-and-place/CPL, stackup, pinout, pin map, decoupling, strapping pins, a datasheet, or ordering a board.
compatibility: Claude Code on macOS with KiCad 10 installed as /Applications/KiCad/KiCad.app (kicad-cli is called by absolute path, not from PATH) and a system python3 >= 3.10 for the bundled scripts. Network only to fetch datasheets. No KiCad Python, no IPC API, no board on USB needed.
---

# KiCad review on this Mac

Personal skill: it applies in every repo and holds the workflow, the KiCad pin, and the boundaries. Project facts (which `.kicad_pro`, which firmware pin header, which fab and layer count, the harness pinouts) come from the repo you are in: its `CLAUDE.md` `## Hardware` section, the pin header, `BOM.md`, the design notes. Read those first; never guess a pin map or a part number.

Bundled files. `${CLAUDE_SKILL_DIR}` is the directory holding this SKILL.md (Claude Code substitutes it; in another tool use that directory's path, the skill is symlinked under the same name). Every script locates its own directory, so only this prose depends on the variable.

| File | Use |
|---|---|
| `kicad-version` | Read. The pinned KiCad for this machine, the only authoritative copy. |
| `scripts/check_kicad.sh` | Run once per session. Read-only: kicad-cli present and at the pinned major, python3, IPC state, kicad-happy, projects under cwd. |
| `scripts/erc_drc.sh` | Run: `erc\|drc <file> [outdir]`. ERC or DRC through kicad-cli; JSON kept in `review/` next to the file, grouped summary printed. |
| `scripts/pin_diff.py` | Run. Netlist GPIO assignments vs a firmware pin header. |
| `scripts/fab_export.sh` | Run only in step 7: `<pcb> <sch> <outdir>`. Gerbers, drill, BOM, CPL for JLCPCB. |
| `references/esp32-s3-rules.md` | Read in step 1 when the MCU is an ESP32-S3. |
| `references/schematic-review.md` | Read in step 2. |
| `references/layout-review.md` | Read in step 5. |
| `references/jlcpcb-order.md` | Read in step 7. |

## Fixed decisions

- **Human draws, Claude reviews.** The schematic and board are drawn, edited, placed and routed in the KiCad GUI by the user. Claude never writes `.kicad_sch`, `.kicad_pcb`, `.kicad_pro`, `.kicad_sym`, `.kicad_mod` or `.kicad_wks`: not by hand, not through `sed`, not through the bundled `pcbnew` Python (SWIG API, deprecated since KiCad 9, gone in 11), not through the IPC API (disabled on this machine). Reading them as text with `grep` is fine. Structured access goes through `kicad-cli` exports into a `review/` directory.
- **Never place, never route, never edit a file to silence ERC or DRC.** A finding is a sentence the user acts on in the GUI; an exclusion is something the user marks in the GUI. Asked to place, route or "just fix the file": decline in one line and name the step whose output the user needs instead.
- **One KiCad per machine**, pinned in `kicad-version`, invoked as `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`, never assumed on `PATH`. A different patch or minor is a printed warning; a different major is a stop, because the JSON and netlist shapes the scripts parse are per-major. Bumping is a deliberate edit of `kicad-version` plus a re-run of every script on a known project. Never bump to make a script parse. Never install or update KiCad yourself.
- **Every electrical number has a source.** Pin numbers, package, absolute maximums, I2C addresses, strapping levels, supply currents, capacitor values: cite the fetched datasheet (URL and section or page) or the project's design note. Nothing from memory, including the tables in `references/`, which are starting points to re-verify, not authorities. Unreachable datasheet: the finding says `unverified`.
- **Ordering and paying are human-only.** Step 7 produces the file set and a pre-upload checklist. Never upload, log in, fill a cart, or drive the fab site through a browser tool. Part numbers, stock and basic/extended status are looked up live at order time, never quoted from memory.
- **Project facts come from the repo.** Missing pin header, unknown fab, unknown module variant: ask, never default.
- **Generated, never committed:** `review/`, `fab/`, `*.kicad_prl`, `fp-info-cache`, `*-backups/`, `*.kicad_sch-bak`, `*.kicad_pcb-bak`, `_autosave-*`, `~*.lck`. `kicad-cli` itself writes `.kicad_prl` and `fp-info-cache` next to the project, so check the project's `.gitignore` before its first commit.

## What a hardware project looks like

```
hardware/<board>/<board>.kicad_pro|.kicad_sch|.kicad_pcb    drawn in the GUI, committed
hardware/<board>/lib/                                       project symbol and footprint libraries, committed
hardware/<board>/review/                                    kicad-cli exports and reports, generated
hardware/<board>/fab/<date>/                                gerbers, BOM, CPL, zip, generated
```

The `## Hardware` section sits next to `## Boards` in the project's `CLAUDE.md` (or `CLAUDE.local.md`), one `key: value` per line so it can be grepped:

```
## Hardware
kicad: hardware/aquila-fc/aquila-fc.kicad_pro
pins: firmware/main/app_config.h
mcu: U1                          # reference designator of the MCU or module symbol
fab: jlcpcb, 4 layers, economic assembly
note: hardware/aquila-fc/DESIGN.md
```

Resolve the project the way esp-idf resolves ports: the section, else a path named in this message, else exactly one `*.kicad_pro` in the repo (use it and offer to record the section), else zero: say so and stop, else several: ask.

## Procedure

### 0. Environment, once per session

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check_kicad.sh"
```

Exit 0: go. Exit 1: KiCad missing, wrong major, or no python3: stop, quote the output, say KiCad comes from kicad.org as an app bundle. Never `brew install` it. The `ipc api` and `kicad-happy` lines are informational.

### 1. Read the project

The `## Hardware` section, the pin header, the design note, `BOM.md`, the MCU family and exact module variant (the symbol's Value field). If the MCU is an ESP32-S3, read `references/esp32-s3-rules.md` now. Then export once. Every export in this procedure lands in `review/` inside the board directory, the same place `erc_drc.sh` defaults to; `B` below is that directory:

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>; mkdir -p "$B/review"
$K sch export netlist --format kicadsexpr -o "$B/review/board.net" "$B/<b>.kicad_sch"
$K sch export bom --fields 'Reference,Value,Footprint,${QUANTITY},LCSC,MPN,${DNP}' --group-by Value,Footprint,LCSC -o "$B/review/bom.csv" "$B/<b>.kicad_sch"
$K sch export pdf -o "$B/review/schematic.pdf" "$B/<b>.kicad_sch"
```

Read the PDF. Never describe a schematic you have not looked at.

### 2. Schematic-stage review

Walk `references/schematic-review.md` against the netlist, the PDF, the header and the fetched datasheets. Report as a table `sev | ref/net | finding | source`, errors first, at most about 25 rows; summarise the rest by type. Every row names its evidence or says `unverified`.

### 3. ERC

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/erc_drc.sh" erc "$B/<b>.kicad_sch"
```

Exit 0 clean; 5 violations (any severity); 3 the schematic did not load (quote the reason; a missing library table or a moved sheet is the user's GUI fix). Each error becomes a GUI action or a justified exclusion the user sets in the GUI. Warnings are triaged one by one, not dismissed as a class.

### 4. Pin diff against firmware

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/pin_diff.py" --netlist "$B/review/board.net" --header <pins:> --mcu <mcu:>
```

Exit 2 means at least one error row; paste the table. The header contract is flat `#define PIN_* <int>` lines (aquila's `app_config.h`); a header with `#if` branches or struct initialisers (athena's `board_pins.h`) is out of scope: say so and ask for a flat header or a `--pinmap`. KiCad's `RF_Module:ESP32-S3-WROOM-1` names pins `IO4`, `USB_D-`, `USB_D+`, `RXD0`, `TXD0`; the four unnumbered ones are built-in aliases. A symbol whose pin names carry no GPIO number needs `--pinmap pad,gpio`. Skip the step and say so when the project has no pin header yet.

### 5. Layout-stage review

```bash
$K pcb export stats --format json -o "$B/review/stats.json" "$B/<b>.kicad_pcb"
$K pcb export pdf -l F.Cu,F.Silkscreen,Edge.Cuts -o "$B/review/front.pdf" "$B/<b>.kicad_pcb"
$K pcb export pdf -l B.Cu,B.Silkscreen,Edge.Cuts -o "$B/review/back.pdf" "$B/<b>.kicad_pcb"
```

One PDF per inner layer on a 4-layer board. Read them, then walk `references/layout-review.md`. Same report format as step 2. Placement and routing quality are the user's judgement; report what the exports show.

### 6. DRC

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/erc_drc.sh" drc "$B/<b>.kicad_pcb"
```

Runs with `--schematic-parity`. Any `unconnected_items` or parity issue blocks step 7. Exit codes as in step 3.

### 7. Pre-order

Only after steps 3, 4 and 6 are clean, or every remaining item has been explicitly accepted by the user in this conversation.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/fab_export.sh" "$B/<b>.kicad_pcb" "$B/<b>.kicad_sch" "$B/fab/<date>"
```

Then fill the pre-upload table in `references/jlcpcb-order.md`: copper layer count equals the `fab:` line, Edge.Cuts and drill present, every BOM row without an LCSC number explained, CPL row count equals placed parts, rotation caveat stated. Hand the user the zip path and the table. They upload.

### 8. Report

One short paragraph per stage run: counts by severity, the three findings that matter most, what the user changes in the GUI next. Full JSON stays in `review/`.

## macOS notes

- App bundle path only; `kicad-cli` needs no display and no running KiCad.
- Scripts are bash 3.2-safe (no `mapfile`, no associative arrays) and python3 stdlib-only; `python3` is Homebrew's, the KiCad-bundled Python 3.9 is not used.
- No `timeout` on macOS; every `kicad-cli` call here returns on its own within seconds.

## Degradation

- KiCad missing or wrong major: quote `check_kicad.sh`, stop.
- No `.kicad_pro` yet: say so; offer `references/schematic-review.md` as a pre-draw checklist against the design note.
- ERC or DRC exit 3: quote the load error; never edit a file to make it load.
- Datasheet unreachable: mark the finding `unverified`, continue.
- No pin header: skip step 4 and say so. Symbol without numbered pin names: `pin_diff.py` says which pins it could not map; ask for a `--pinmap`, never guess one.
- kicad-happy installed (a Claude Code plugin from github.com/aklofas/kicad-happy, MIT): run its `kicad` skill's review too and merge the findings into the same table, marking their source. Absent: nothing changes.
- Asked to place, route, generate a schematic, or edit a KiCad file: decline, name the step whose output the user needs instead.
