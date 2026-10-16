---
name: pcb-enclosure
description: Design enclosures, cases, lids, mounts, brackets and standoffs for the user's own PCBs (ESP32 boards for Athena and Aquila) and prepare them for FDM printing. Exports the real board geometry from KiCad with kicad-cli on one shared datum (board outline and holes STEP, connector STEP, placement CSV, outline DXF) and supplies the user's FDM fit tolerances. All modeling is deferred to the text-to-cad plugin's cad skill (build123d through cadgen). Use whenever the user mentions an enclosure, case, housing, box, lid, mount, bracket, standoff, 3D print, STL, 3MF, STEP, build123d, cadgen, fitting a board or printing a part. Not for schematic or PCB review (kicad-review) or firmware (esp-idf).
compatibility: macOS, KiCad 10 app bundle (kicad-cli), uv, the text-to-cad Claude Code plugin v0.7.21 installed. Network only for the first uvx and Playwright download.
---

# PCB enclosure

Personal skill for printed parts around the user's own boards. It does not model anything itself.

## Who owns what

- This skill: board geometry out of KiCad with one datum (`scripts/board_export.sh`), and the FDM fit values (`references/fdm-fits.md`).
- text-to-cad (`text-to-cad:cad`): all modeling, building, snapshots and STEP/STL/3MF export. `text-to-cad:dfam-check`: wall thickness, overhangs, minimum 2.0 mm FDM hole. It has no fit tolerances.
- kicad-review: the board design itself. If the board needs changing, go there.

## Scripts and references

| File | Use |
|---|---|
| `scripts/board_export.sh <file.kicad_pcb\|file.kicad_pro> [outdir]` | Writes `board.step`, `connectors.step`, `positions.csv`, `outline.dxf`, `README.txt` into `cad/board/` next to the pcb (default). `--filter 'J*,SW*,U*'` sets which components go into connectors.step (default `J*,SW*`). |
| `references/fdm-fits.md` | Hole, insert, clearance and wall values to start from. Calibrate on one coupon per printer. |

## What it reads from the project

- `CLAUDE.md` `## Hardware` -> `kicad:` (the path kicad-review also uses to find the board).
- Optional, new: a `## Print` section with `printer:`, `nozzle:`, `material:`. If absent, assume 0.4 mm nozzle, PLA or PETG, and say so.

## Workflow

0. Run `cadgen doctor`. `cadgen` is shorthand for `uvx --no-config --managed-python --python 3.13 --from cadgen==0.7.21 cadgen`; the same prefix with `python` runs model scripts. In zsh use a shell function, not a string variable. Commands run from the project root; layout is `src/<name>.py`, outputs in `STEP/`, `STL/`, `3MF/`, snapshots in `tmp/`.
1. Read the repo `CLAUDE.md` `## Hardware` section for the `kicad:` path.
2. Run `scripts/board_export.sh <that path>`. Set the drill/aux origin on a mounting hole or board corner in pcbnew first; it is the datum for every file. Confirm the Y axis / origin convention of the STEP once per project by comparing one known hole position between `positions.csv` and the STEP. Checked on aquila-fc with kicad-cli 10.0.5: X and Y in `positions.csv` match the STEP `CARTESIAN_POINT` values exactly, Y is negative below the origin (pcbnew's Y-down), Z=0 is the board bottom.
3. Invoke the `text-to-cad:cad` skill and model in `cad/src/<part>.py`:
   - `cadgen.read_step("cad/board/board.step")` gives a build123d Compound.
   - Derive mounting holes from its cylindrical faces (centre and diameter).
   - Check the part against `connectors.step` for interference.
   - Apply the values in `references/fdm-fits.md`.
4. Snapshot: `cadgen step snapshot STEP/<x>.step tmp/review.png`, then Read the PNG. Mandatory, never skip.
5. Run `text-to-cad:dfam-check`.
6. Export STL and 3MF (the `@stl` / `@3mf` outputs of the model script).
7. Report overall dimensions, the fits used, and what to verify after printing (hole fit, board seating, connector access, lid closure).

## Orchestration

CAD runs and snapshots are design iteration. The agent doing the modeling (main session or general-purpose) runs them, never the verifier agent, which cannot load skills.
