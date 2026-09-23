---
name: kicad-review
description: Reviews KiCad 10 hardware projects on macOS through kicad-cli exports and never edits them — schematic and layout checklists, ERC and DRC reports, netlist-vs-firmware GPIO pin diff, ESP32-S3 pinout and strapping-pin rules, BOM/CPL/gerber export for JLCPCB with LCSC part numbers, datasheet-cited findings. Takes precedence over the kicad-happy plugin's kicad, bom and jlcpcb skills and runs kicad-happy's analyzers itself, read-only. Use whenever the user mentions KiCad, .kicad_sch/.kicad_pcb/.kicad_pro, schematic, PCB, layout, netlist, footprint, symbol, ERC, DRC, BOM, LCSC, JLCPCB, PCBA, gerber, drill, pick-and-place/CPL, stackup, pinout, pin map, decoupling, strapping pins, a datasheet, or ordering a board.
compatibility: Claude Code on macOS with KiCad 10 installed as /Applications/KiCad/KiCad.app (kicad-cli is called by absolute path, not from PATH) and a system python3 >= 3.10 for the bundled scripts. Network only to fetch datasheets. No KiCad Python, no IPC API, no board on USB needed.
---

# KiCad review on this Mac

Personal skill: it applies in every repo and holds the workflow, the KiCad pin, and the boundaries. Project facts (which `.kicad_pro`, which firmware pin header, which fab and layer count, the harness pinouts) come from the repo you are in: its `CLAUDE.md` `## Hardware` section, the pin header, `BOM.md`, the design notes. Read those first; never guess a pin map or a part number.

Bundled files. `${CLAUDE_SKILL_DIR}` is the directory holding this SKILL.md (Claude Code substitutes it; in another tool use that directory's path, the skill is symlinked under the same name). Every script locates its own directory, so only this prose depends on the variable.

| File | Use |
|---|---|
| `kicad-version` | Read. The pinned KiCad for this machine, the only authoritative copy. |
| `scripts/check_kicad.sh` | Run once per session. Read-only: kicad-cli present and at the pinned major, python3, IPC state, kicad-happy version and scripts path, projects under cwd. |
| `scripts/erc_drc.sh` | Run in steps 2 and 5: `erc\|drc <file> [outdir]`, a `.kicad_pro` maps to its sibling. ERC or DRC through kicad-cli; JSON kept in `review/` next to the file, grouped summary and each error and warning printed. DRC also reruns on zones refilled in memory to catch stale fills. |
| `scripts/pin_diff.py` | Run in step 4. Netlist GPIO assignments vs a firmware pin header. |
| `scripts/fab_export.sh` | Run only in step 7: `<pcb> <sch> <outdir>`. Gerbers, drill, BOM, CPL for JLCPCB, then file-set and BOM-vs-CPL checks. |
| `references/esp32-s3-rules.md` | Read in step 1 when the MCU is an ESP32-S3. |
| `references/schematic-review.md` | Read in step 3. |
| `references/layout-review.md` | Read in step 6. |
| `references/jlcpcb-order.md` | Read in step 7. |

Running outside Claude Code. In Cowork, run from the Mac copy at `~/projects/agents-config/core/skills/kicad-review`; the cloud copy is for reading `kicad-version`, `references/` and the scripts' source. `pin_diff.py` (stdlib python3) runs anywhere the netlist and header are reachable, but `check_kicad.sh`, `erc_drc.sh`, `fab_export.sh` and every `kicad-cli` call need `/Applications/KiCad`: run them in a real macOS shell (Desktop Commander's `start_process`; the sandboxed device shell mounts only connected folders) with `CLAUDE_SKILL_DIR=$HOME/projects/agents-config/core/skills/kicad-review;` set first as its own statement (a `VAR=... cmd` prefix does not expand it in cmd). No macOS shell: hand the user the exact command.

## Fixed decisions

- **Human draws, Claude reviews.** The schematic and board are drawn, edited, placed and routed in the KiCad GUI by the user. Claude never writes `.kicad_sch`, `.kicad_pcb`, `.kicad_pro`, `.kicad_sym`, `.kicad_mod` or `.kicad_wks`: not by hand, not through `sed`, not through the bundled `pcbnew` Python (SWIG API, deprecated since KiCad 9, gone in 11), not through the IPC API (disabled on this machine). Reading them as text with `grep` is fine. Structured access goes through `kicad-cli` exports into a `review/` directory.
- **Never place, never route, never edit a file to silence ERC or DRC.** A finding is a sentence the user acts on in the GUI; an exclusion is something the user marks in the GUI. Asked to place, route or "just fix the file": decline in one line and name the step whose output the user needs instead.
- **No other skill's write step applies.** Another skill's instruction to write symbol properties does not override the no-edit rule; what it would write (LCSC or MPN fields, datasheet URLs) goes to the user as GUI edits.
- **One KiCad per machine**, pinned in `kicad-version`, invoked as `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`, never assumed on `PATH`. A different patch or minor is a printed warning; a different major is a stop, because the JSON and netlist shapes the scripts parse are per-major. Bumping is a deliberate edit of `kicad-version` plus a re-run of every script on a known project. Never bump to make a script parse. Never install or update KiCad yourself.
- **Every electrical number has a source.** Pin numbers, package, absolute maximums, I2C addresses, strapping levels, supply currents, capacitor values: cite the fetched datasheet (URL and section or page) or the project's design note. Nothing from memory, including the tables in `references/`, which are starting points to re-verify, not authorities. Unreachable datasheet: the finding says `unverified`.
- **Ordering and paying are human-only.** Step 7 produces the file set and a pre-upload checklist. Never upload, log in, fill a cart, or drive the fab site through a browser tool. Part numbers, stock and basic/extended status are looked up live at order time, never quoted from memory.
- **Project facts come from the repo.** Missing pin header, unknown fab, unknown module variant: ask, never default.
- **Generated, never committed:** `review/`, `fab/`, `.history/` (KiCad 10 local history, its own `.git`), `analysis/` and `datasheets/` (kicad-happy), `*.kicad_prl`, `fp-info-cache`, `*-backups/`, `*.kicad_sch-bak`, `*.kicad_pcb-bak`, `_autosave-*`, `~*.lck`. `kicad-cli` writes `<project>.kicad_prl` next to the project; `fp-info-cache` comes from the GUI footprint browser. Check the project's `.gitignore` before its first commit.

## Division of labour with kicad-happy

kicad-happy is an optional Claude Code plugin (github.com/aklofas/kicad-happy, MIT); `check_kicad.sh` prints whether it is enabled, its version and its `kh scripts` path. kicad-review owns the procedure, ERC and DRC, the pin diff and the fab set. When the plugin is enabled:

- Its `kicad` analyzers are optional extra evidence in steps 3 and 6. Call them by absolute path, as in the block below, and do not load kicad-happy's SKILL.md: its review contract is not this procedure. Output goes to `review/kicad-happy/`, never an `analysis/` directory. Merge their findings into the same table with source `kh`, re-verified like any other row.
- `spice` and `emc` run only when the user asks.
- `lcsc`, `jlcpcb` and `datasheets` are for read-only lookups (stock, basic/extended status, datasheet fetch) and jlcpcb's rotation-offset table.
- Never run `bom/edit_properties.py`, `sync_datasheet_urls.py`, or anything with `--write`, `--apply` or `--overwrite`. Their proposals go to the user as GUI edits.
- Plugin absent or disabled: skip it. Under Codex the plugin is not loaded: call the analyzers by the printed `kh scripts` path, or skip. Nothing else changes.

```bash
KH=<kh scripts path from check_kicad.sh>; B=hardware/<b>; mkdir -p "$B/review/kicad-happy"
python3 "$KH/analyze_schematic.py" "$B/<b>.kicad_sch" --output "$B/review/kicad-happy/schematic.json"
python3 "$KH/analyze_pcb.py" "$B/<b>.kicad_pcb" --output "$B/review/kicad-happy/pcb.json"
```

## What a hardware project looks like

```
hardware/<board>/<board>.kicad_pro|.kicad_sch|.kicad_pcb    drawn in the GUI, committed
hardware/<board>/lib/                                       project symbol and footprint libraries, committed
hardware/<board>/review/                                    kicad-cli exports and reports, generated
hardware/<board>/fab/<date>/                                gerbers, BOM, CPL, zip, generated
```

Before the first commit, `git check-ignore -v hardware/<board>/lib/<x>.kicad_sym hardware/<board>/.history` must print a rule for `.history` and none for `lib/`: a Python `.gitignore` template ignores `lib/`.

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

Shell variables do not persist between Bash calls, so every block below that needs `K` (kicad-cli) or `B` (the board directory; `<b>` is the board's file name stem) sets both first. The working directory does persist: run from the repo root.

### 0. Environment, once per session

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check_kicad.sh"
```

Exit 0: go. Exit 1: KiCad missing, wrong major, or no python3: stop, quote the output, say KiCad comes from kicad.org as an app bundle. Never `brew install` it. The `ipc api`, `kicad-happy` and `kh scripts` lines are informational.

### 1. Read the project

The `## Hardware` section, the pin header, the design note, `BOM.md`, the MCU family and exact module variant (the symbol's Value field). If the MCU is an ESP32-S3, read `references/esp32-s3-rules.md` now. Then export once. Every export in this procedure lands in `review/` inside the board directory, the same place `erc_drc.sh` defaults to:

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>; mkdir -p "$B/review"
$K sch export netlist --format kicadsexpr -o "$B/review/board.net" "$B/<b>.kicad_sch"
$K sch export bom --fields 'Reference,Value,Footprint,${QUANTITY},LCSC,MPN,${DNP}' --group-by Value,Footprint,LCSC --ref-range-delimiter '' -o "$B/review/bom.csv" "$B/<b>.kicad_sch"
$K sch export pdf -o "$B/review/schematic.pdf" "$B/<b>.kicad_sch"
```

Read the PDF. Never describe a schematic you have not looked at.

### 2. ERC

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/erc_drc.sh" erc "$B/<b>.kicad_sch"
```

Exit 0 clean; 5 violations (any severity); 3 the schematic did not load (quote the reason; a missing library table or a moved sheet is the user's GUI fix); 1 misuse, including a file of the wrong type (`erc` takes a `.kicad_sch`, `drc` a `.kicad_pcb`, both a `.kicad_pro`). Each error becomes a GUI action or a justified exclusion the user sets in the GUI. Warnings are triaged one by one, not dismissed as a class: the script lists each one with the symbols and pins involved, up to 20 per severity; the rest are in the JSON. The step-3 checklist reads this result.

### 3. Schematic-stage review

Walk `references/schematic-review.md` against the netlist, the PDF, the header, the ERC result and the fetched datasheets. Report as a table `sev | ref/net | finding | source`, errors first, at most about 25 rows; summarise the rest by type. Every row names its evidence or says `unverified`.

### 4. Pin diff against firmware

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
python3 "${CLAUDE_SKILL_DIR}/scripts/pin_diff.py" --netlist "$B/review/board.net" --header <pins:> --mcu <mcu:>
```

Exit 2 means at least one error row; paste the table. Exit 1 is misuse or a file it could not parse. The header contract is flat `#define PIN_* <int>` lines (aquila's `app_config.h`); a header with `#if` branches or struct initialisers (athena's `board_pins.h`) is out of scope: say so and ask for a flat header or a `--pinmap`. KiCad 10 netlists write pin functions as `NAME_<pad>` (`USB_D-_13`); `pin_diff.py` strips the suffix, maps `IOn` by regex and `USB_D-`/`USB_D+`/`RXD0`/`TXD0` by built-in alias. If the unmapped line lists any of those four, stop and report. A symbol whose pin names carry no GPIO number needs `--pinmap pad,gpio`. Skip the step and say so when the project has no pin header yet.

### 5. DRC

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/erc_drc.sh" drc "$B/<b>.kicad_pcb"
```

Runs with `--schematic-parity` on the zone fills saved in the board, then again with zones refilled in memory into `review/drc_refilled.json`. Any `unconnected_items` or parity issue blocks step 7. If the script prints `zone fills are stale`, that is a finding: the user refills (Edit > Fill All Zones, B) and saves in the GUI, and step 7 waits until the saved board passes without refill. `--refill-zones` here and `--check-zones` in steps 6 and 7 refill in memory only; the board file is never saved. Exit codes as in step 2, taken from the saved-fill run.

### 6. Layout-stage review

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
$K pcb export stats --format json -o "$B/review/stats.json" "$B/<b>.kicad_pcb"
$K pcb export pdf --check-zones -l F.Cu,F.Silkscreen,Edge.Cuts -o "$B/review/front.pdf" "$B/<b>.kicad_pcb"
$K pcb export pdf --check-zones -l B.Cu,B.Silkscreen,Edge.Cuts -o "$B/review/back.pdf" "$B/<b>.kicad_pcb"
```

One PDF per inner layer on a 4-layer board. Read them, then walk `references/layout-review.md`. Same report format as step 3. Placement and routing quality are the user's judgement; report what the exports show.

### 7. Pre-order

Only after steps 2, 4 and 5 are clean, or every remaining item has been explicitly accepted by the user in this conversation. If the project has an `ORDER.md` (earlier order fields, delivery country, fab route), read it first.

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/fab_export.sh" "$B/<b>.kicad_pcb" "$B/<b>.kicad_sch" "$B/fab/<date>"
```

The script empties `<outdir>/gerber` first and plots with zones refilled in memory. It exits 1 when the gerber set is not exactly one file per requested layer (named as the job file lists them, so a renamed inner layer is fine) plus drill, map and job file, when a BOM cell holds a designator range, or when a BOM designator with an LCSC number has no CPL row. It prints both designator differences; CPL-only rows (fiducials, logos: footprints excluded from the BOM) are listed, not failed. Then fill the pre-upload table in `references/jlcpcb-order.md`: copper layer count equals the `fab:` line, Edge.Cuts and drill present, every BOM designator with an LCSC number in the CPL and no ranges, BOM-only and CPL-only rows listed and explained, every BOM row without an LCSC number explained, CPL rows with an LCSC number equal the assembled parts and the other BOM parts are listed as hand-soldered, the delivery country offers PCBA, rotation caveat stated. Hand the user the zip path and the table. They upload.

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
- Asked to place, route, generate a schematic, or edit a KiCad file: decline, name the step whose output the user needs instead.
