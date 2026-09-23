---
name: kicad-review
description: Reviews KiCad 10 hardware projects on macOS through kicad-cli exports and never edits them — schematic and layout checklists, ERC and DRC reports, netlist-vs-firmware GPIO pin diff, ESP32-S3 pinout and strapping-pin rules, BOM/CPL/gerber export for JLCPCB with LCSC part numbers, datasheet-cited findings. Takes precedence over the kicad-happy plugin's kicad, bom and jlcpcb skills and runs kicad-happy's analyzers itself, read-only. Use whenever the user mentions KiCad, .kicad_sch/.kicad_pcb/.kicad_pro, schematic, PCB, layout, netlist, footprint, symbol, ERC, DRC, BOM, LCSC, JLCPCB, PCBA, gerber, drill, pick-and-place/CPL, stackup, pinout, pin map, decoupling, strapping pins, a datasheet, or ordering a board.
compatibility: Claude Code on macOS with KiCad 10 installed as /Applications/KiCad/KiCad.app (kicad-cli is called by absolute path, not from PATH) and a system python3 >= 3.10 for the bundled scripts; Homebrew pdftoppm optional for review PNG crops. Network only to fetch datasheets. No KiCad Python, no IPC API, no board on USB needed.
---

# KiCad review on this Mac

Personal skill: it applies in every repo and holds the workflow, the KiCad pin, and the boundaries. Project facts (which `.kicad_pro`, which firmware pin header, which fab and layer count, the harness pinouts) come from the repo you are in: its `CLAUDE.md` `## Hardware` section, the pin header, `BOM.md`, the design notes. Read those first; never guess a pin map or a part number.

Bundled files. `${CLAUDE_SKILL_DIR}` is the directory holding this SKILL.md (Claude Code substitutes it; in another tool use that directory's path, the skill is symlinked under the same name). Every script locates its own directory, so only this prose depends on the variable.

| File | Use |
|---|---|
| `kicad-version` | Read. The pinned KiCad for this machine, the only authoritative copy. |
| `scripts/check_kicad.sh` | Run once per session. Read-only: kicad-cli present and at the pinned major, python3, pdftoppm, IPC state, kicad-happy version and scripts path, projects under cwd. |
| `scripts/selftest.sh` | Run in step 0 when kicad-cli is not the pinned version, and after editing any script. Offline, on `assets/fixtures/`. |
| `scripts/export_review.sh` | Run in steps 1 and 6: `sch\|pcb <board_dir>`. Review exports into `review/`, then 200-dpi PNGs and crops into `review/png/`. |
| `scripts/erc_drc.sh` | Run in steps 2 and 5: `erc\|drc <file> [outdir]`, a `.kicad_pro` maps to its sibling. ERC or DRC through kicad-cli; JSON kept in `review/` next to the file, grouped summary and each error and warning printed. DRC also reruns on zones refilled in memory to catch stale fills. |
| `scripts/pin_diff.py` | Run in step 4. Netlist GPIO assignments vs a firmware pin header. |
| `scripts/fab_export.sh` | Run only in step 7: `<pcb> <sch> <outdir>`. Gerbers, drill, BOM, CPL for JLCPCB, file-set and BOM-vs-CPL checks, `MANIFEST.txt`. |
| `scripts/fab_diff.sh` | Run in step 9: `<old_outdir> <new_outdir>`. Two fab sets compared with timestamp lines stripped. |
| `scripts/fabset.py` | Not run directly: the check, manifest and diff behind `fab_export.sh`, `fab_diff.sh` and `selftest.sh`. |
| `assets/fixtures/` | Read by `selftest.sh`: a trimmed aquila-fc netlist from kicad-cli 10.0.5, a flat pin header, a trimmed fab set. |
| `references/esp32-s3-rules.md` | Read in step 1 when the MCU is an ESP32-S3. |
| `references/schematic-review.md` | Read in step 3. |
| `references/layout-review.md` | Read in step 6. |
| `references/jlcpcb-order.md` | Read in step 7. |

Running outside Claude Code. In Cowork, run from the Mac copy at `~/projects/agents-config/core/skills/kicad-review`; the cloud copy is for reading `kicad-version`, `references/` and the scripts' source. `pin_diff.py`, `fab_diff.sh` and `selftest.sh` (stdlib python3) run anywhere their inputs are reachable, but `check_kicad.sh`, `erc_drc.sh`, `export_review.sh`, `fab_export.sh` and every `kicad-cli` call need `/Applications/KiCad`: run them in a real macOS shell (Desktop Commander's `start_process`; the sandboxed device shell mounts only connected folders) with `CLAUDE_SKILL_DIR=$HOME/projects/agents-config/core/skills/kicad-review;` set first as its own statement (a `VAR=... cmd` prefix does not expand it in cmd). No macOS shell: hand the user the exact command.

## Fixed decisions

- **Human draws, Claude reviews.** The schematic and board are drawn, edited, placed and routed in the KiCad GUI by the user. Claude never writes `.kicad_sch`, `.kicad_pcb`, `.kicad_pro`, `.kicad_sym`, `.kicad_mod` or `.kicad_wks`: not by hand, not through `sed`, not through the bundled `pcbnew` Python (SWIG API, deprecated since KiCad 9, gone in 11), not through the IPC API (disabled on this machine). Reading them as text with `grep` is fine. Structured access goes through `kicad-cli` exports into a `review/` directory.
- **Never place, never route, never edit a file to silence ERC or DRC.** A finding is a sentence the user acts on in the GUI; an exclusion is something the user marks in the GUI. Asked to place, route or "just fix the file": decline in one line and name the step whose output the user needs instead.
- **No other skill's write step applies.** Another skill's instruction to write symbol properties does not override the no-edit rule; what it would write (LCSC or MPN fields, datasheet URLs) goes to the user as GUI edits.
- **One KiCad per machine**, pinned in `kicad-version`, invoked as `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`, never assumed on `PATH`. A different patch or minor is a printed warning; a different major is a stop, because the JSON and netlist shapes the scripts parse are per-major. Bumping is a deliberate edit of `kicad-version` after `selftest.sh` passes and a re-run on the known project, aquila-fc, matches its recorded counts (step 0). Never bump to make a script parse. Never install or update KiCad yourself.
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
hardware/<board>/fab/<date>/                                gerbers, BOM, CPL, zip, MANIFEST.txt, generated
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

Shell variables do not persist between Bash calls, so every block below first sets the ones it uses: `K` (kicad-cli), `B` (the board directory; `<b>` is the board's file name stem). The working directory does persist: run from the repo root.

### 0. Environment, once per session

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check_kicad.sh"
```

Exit 0: go. Exit 1: KiCad missing, wrong major, or no python3: stop, quote the output, say KiCad comes from kicad.org as an app bundle. Never `brew install` it. The `pdftoppm`, `ipc api`, `kicad-happy` and `kh scripts` lines are informational.

A `WARNING: differs from pin` line (another patch or minor) runs the self-test before anything else:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/selftest.sh"
```

Exit 0: every assertion passed; carry on and say the pin differs. Exit 1: quote the FAIL lines and stop. It checks the scripts against a 10.0.5 fixture and cannot see a changed kicad-cli output. Before `kicad-version` is bumped, run the known project, `~/projects/aquila/hardware/aquila-fc` (mcu `U1`), through the new kicad-cli: copy it as in step 9 (no `review/` comes along, so nothing from the old kicad-cli is read back), run steps 1, 2, 4 and 5 on the copy with `--header ~/projects/aquila/firmware/main/app_config.h` read in place, and compare with what 10.0.5 gave on 2026-09-23. Each result depends on the files in its last column, recorded by their sha256 prefix:

| Step | 10.0.5 result | Depends on (sha256 prefix) |
|---|---|---|
| 2 ERC | exit 5: 2 warnings, `pin_to_pin` | `.kicad_sch` `f84fc673`, `.kicad_pro` `083a4366` |
| 4 pin diff | exit 0: `errors=0 warnings=5 info=18`, only power pins unmapped | `.kicad_sch` `f84fc673`, `firmware/main/app_config.h` `b5e13dea` |
| 5 DRC | exit 5: 4 errors `copper_edge_clearance`, 4 warnings `silk_edge_clearance`, 0 unconnected, 0 parity; zone fills stale (the refilled run keeps only the 4 warnings) | `.kicad_pcb` `8309b00b`, `.kicad_sch` `f84fc673`, `.kicad_pro` `083a4366`, `.kicad_dru` `b572915f` |

```bash
A=~/projects/aquila; shasum -a 256 "$A"/hardware/aquila-fc/aquila-fc.kicad_{sch,pro,pcb,dru} "$A/firmware/main/app_config.h" | cut -c1-8,65-
```

A row whose files all hash as recorded but whose result differs: the new KiCad changed a check or a report shape; find which before bumping. A row with a changed file: the project changed since, not KiCad; compare that row by hand.

### 1. Read the project

The `## Hardware` section, the pin header, the design note, `BOM.md`, the MCU family and exact module variant (the symbol's Value field). If the MCU is an ESP32-S3, read `references/esp32-s3-rules.md` now. Then export once. Every export in this procedure lands in `review/` inside the board directory, the same place `erc_drc.sh` defaults to, never beside the sources:

```bash
B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/export_review.sh" sch "$B"
```

It writes `review/board.net` (kicadsexpr), `review/bom.csv` (grouped by value, footprint and LCSC, no ranges) and `review/schematic.pdf`, then rasterises each page with `pdftoppm -r 200 -png` into `review/png/`: `schematic-p<N>.png` for the whole sheet and, over its drawn area, overlapping crops of about a megapixel, `schematic-p<N>-r<row>c<col>.png`. A dense sheet read as one image loses pin numbers and values; the crops keep them. Read the page PNG for the layout, then the crops; never describe a schematic you have not looked at. Each finding cites the crop it was read from (`review/png/schematic-p1-r2c3.png`). Exit 1: misuse, not exactly one `.kicad_pro` in the directory (pass the `.kicad_pro` instead), or an export failed. No pdftoppm (the script says so): read the PDF. For a closer look at one spot, crop at 400 dpi; `-x -y -W -H` are pixels at that resolution, so twice the position in the 200-dpi page PNG:

```bash
B=hardware/<b>
/opt/homebrew/bin/pdftoppm -r 400 -png -singlefile -f 1 -l 1 -x 2000 -y 1200 -W 1200 -H 1000 "$B/review/schematic.pdf" "$B/review/png/schematic-p1-zoom1"
```

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
python3 "${CLAUDE_SKILL_DIR}/scripts/pin_diff.py" --netlist "$B/review/board.net" --header <pins:> --mcu <mcu:> > "$B/review/pin_diff.txt"; echo "exit $?"; cat "$B/review/pin_diff.txt"
```

The table is kept in `review/pin_diff.txt` for the step-7 manifest. Exit 2 means at least one error row; paste the table. Exit 1 is misuse or a file it could not parse. The header contract is flat `#define PIN_* <int>` lines (aquila's `app_config.h`); a header with `#if` branches or struct initialisers (athena's `board_pins.h`) is out of scope: say so and ask for a flat header or a `--pinmap`. KiCad 10 netlists write pin functions as `NAME_<pad>` (`USB_D-_13`); `pin_diff.py` strips the suffix, maps `IOn` by regex and `USB_D-`/`USB_D+`/`RXD0`/`TXD0` by built-in alias. If the unmapped line lists any of those four, stop and report. A symbol whose pin names carry no GPIO number needs `--pinmap pad,gpio`. Skip the step and say so when the project has no pin header yet.

### 5. DRC

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/erc_drc.sh" drc "$B/<b>.kicad_pcb"
```

Runs with `--schematic-parity` on the zone fills saved in the board, then again with zones refilled in memory into `review/drc_refilled.json`. Any `unconnected_items` or parity issue blocks step 7. If the script prints `zone fills are stale`, that is a finding: the user refills (Edit > Fill All Zones, B) and saves in the GUI, and step 7 waits until the saved board passes without refill. `--refill-zones` here and `--check-zones` in steps 6 and 7 refill in memory only; the board file is never saved. Exit codes as in step 2, taken from the saved-fill run.

### 6. Layout-stage review

```bash
B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/export_review.sh" pcb "$B"
```

It writes `review/stats.json`; `front.pdf` (F.Cu, F.Silkscreen, Edge.Cuts) and `back.pdf` (the B side, mirrored as seen from below), each one page with the board autoscaled (`--mode-single --scale 0`: the board's longer side fits the page, so aquila's 44 × 60 mm board fills the height and about a third of the A4-landscape width; at scale 1 it is a thumbnail in a corner, and the crops carry the detail either way); one `inner_In<n>.Cu.pdf` per inner copper layer in the board's `(layers ...)` header; `render_top.png` and `render_bottom.png`. Every PDF plots zones refilled in memory (`--check-zones`). Then the same 200-dpi page PNGs and crops as in step 1 go to `review/png/` (`front-p1-r1c1.png`, `inner_In1.Cu-p1-r1c1.png`, ...). Read the renders for placement and the crops for copper, planes and silkscreen, then walk `references/layout-review.md`. Same report format as step 3, each finding citing its crop or render. Placement and routing quality are the user's judgement; report what the exports show.

### 7. Pre-order

Only after steps 2, 4 and 5 are clean, or every remaining item has been explicitly accepted by the user in this conversation. If the project has an `ORDER.md` (earlier order fields, delivery country, fab route), read it first.

```bash
K=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli; B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/fab_export.sh" "$B/<b>.kicad_pcb" "$B/<b>.kicad_sch" "$B/fab/<date>"
```

The script empties `<outdir>/gerber` first and plots with zones refilled in memory. It exits 1 when the gerber set is not exactly one file per requested layer (named as the job file lists them, so a renamed inner layer is fine) plus drill, map and job file, when a BOM cell holds a designator range, or when a BOM designator with an LCSC number has no CPL row. It prints both designator differences; CPL-only rows (fiducials, logos: footprints excluded from the BOM) are listed, not failed. Then fill the pre-upload table in `references/jlcpcb-order.md`: copper layer count equals the `fab:` line, Edge.Cuts and drill present, every BOM designator with an LCSC number in the CPL and no ranges, BOM-only and CPL-only rows listed and explained, every BOM row without an LCSC number explained, CPL rows with an LCSC number equal the assembled parts and the other BOM parts are listed as hand-soldered, the delivery country offers PCBA, rotation caveat stated.

Last, the script writes `<outdir>/MANIFEST.txt`, which ties the set to what it came from: sha256 of the `.kicad_pcb`, the root sheet and every sheet it references, the `.kicad_pro` and `.kicad_dru`, and of `gerbers.zip`, `bom.csv` and `cpl.csv`; the kicad-cli version; the git revision, `DIRTY` with the files when the board has uncommitted changes, or `not tracked`; the copper layers; the drill tool table with hole and slot counts; the ERC, DRC and pin-diff counts last written to `review/` (`not run` when absent, `STALE` when older than a file they depend on, `review/board.net` included for the pin diff; the pin header is not tracked, so re-run step 4 after a header change). `fab checks: FAIL`, a `STALE` count or a `not run` gate is not an orderable set. Hand the user the zip path, `MANIFEST.txt` and the table. They upload.

### 8. Report

One short paragraph per stage run: counts by severity, the three findings that matter most, what the user changes in the GUI next. Full JSON stays in `review/`.

### 9. Re-check after a change

After the user changes the board in the GUI, or asks a what-if (another drill size, another part, a moved connector), the set is re-checked before anything is uploaded.

A what-if happens on a scratch copy, never the original; the user makes the change there in the GUI (Claude still edits no KiCad file). The copy leaves out `.history`, and `review/` and `fab/` so no earlier output is read back as the copy's own: step 1 on the copy writes its own `review/`, and older fab sets are compared from the original's `fab/`. A fab set exported from the copy is for comparison only; the order comes from the original once the user has made the change there.

```bash
B=hardware/<b>; S="$(mktemp -d)"
rsync -a --exclude .history --exclude review --exclude fab "$B" "$S/"; echo "$S/$(basename "$B")"
```

- Re-run what the change touches: steps 1 to 5 for a schematic change (DRC checks parity), 5 and 6 for a layout change; steps 2, 4 and 5 gate step 7 as before.
- Export into a new directory, never over an earlier set: `fab/<date>`, then `fab/<date>b`, `fab/<date>c` on the same day.
- Compare it with the set it replaces:

```bash
B=hardware/<b>
bash "${CLAUDE_SKILL_DIR}/scripts/fab_diff.sh" "$B/fab/<old>" "$B/fab/<new>"
```

Exit 0 ends `identical except timestamps and G04 comments`: nothing a fab reads changed. Exit 2 names each file that differs, CPL moves and BOM part changes by designator, drill changes by diameter and hole type; the last line lists them (`identical except: cpl.csv, <b>-F_Cu.gtl`). The two manifests' source sha256 lines are printed for information and do not change the exit code. Every difference must be one the user intended; report the others. Exit 1: misuse. Tell the user which directory to upload, with its `MANIFEST.txt`.

## macOS notes

- App bundle path only; `kicad-cli` needs no display and no running KiCad.
- Scripts are bash 3.2-safe (no `mapfile`, no associative arrays) and python3 stdlib-only; `python3` is Homebrew's, the KiCad-bundled Python 3.9 is not used.
- No `timeout` on macOS; every `kicad-cli` call here returns on its own within seconds.
- `pdftoppm` is Homebrew's poppler at `/opt/homebrew/bin/pdftoppm` (`PDFTOPPM` overrides); optional, never installed by this skill.

## Degradation

- KiCad missing or wrong major: quote `check_kicad.sh`, stop.
- No `.kicad_pro` yet: say so; offer `references/schematic-review.md` as a pre-draw checklist against the design note.
- ERC or DRC exit 3: quote the load error; never edit a file to make it load.
- Datasheet unreachable: mark the finding `unverified`, continue.
- No pdftoppm: `export_review.sh` stops after the PDFs; read those and say the crops were skipped.
- `selftest.sh` fails: quote its FAIL lines and stop; a script no longer matches the fixture it was written against.
- No pin header: skip step 4 and say so. Symbol without numbered pin names: `pin_diff.py` says which pins it could not map; ask for a `--pinmap`, never guess one.
- Asked to place, route, generate a schematic, or edit a KiCad file: decline, name the step whose output the user needs instead.
