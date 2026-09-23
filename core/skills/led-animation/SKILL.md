---
name: led-animation
description: Designs, tunes and verifies animations for an LED matrix panel driven by ESP32 firmware, where a JavaScript reference renderer and its C port must stay one picture. Renders contact sheets and transition strips on the Mac, host-builds the C renderer, checks C/JS parity in driver levels, republishes the live bench page in place, then hands the build (and a flash, only on request) to the esp-idf skill. Use whenever the user mentions the LED face or matrix, an agent state on the panel (idle, listen, think, work, speak, alert, error, sleep), the aura, a contact sheet or the bench, a tween or fade between states, colours, brightness, haze or dither on the panel, or how the panel looks. Not for wiring, pin maps, the HUB75 driver, Wi-Fi, the face protocol or its clients, or a flash on its own; those go to esp-idf and the project docs.
compatibility: Claude Code on macOS with cc (Xcode command line tools), node and python3. The project supplies the renderers and the host tooling; the board side goes through the esp-idf skill.
---

# Animation for an LED matrix panel

Personal skill: the workflow and the boundaries for changing what a low-bit-depth LED panel shows. Everything specific to a project comes from the repo you are in: its `CLAUDE.md` (which states exist, where the per-state table lives, where the host tooling is), the host tooling's own `README.md`, and the memory notes (the bench artifact URL, the user's taste). Read those first; never guess a state list, a table location or a URL. No scripts are bundled here, because the tools compile the project's own C renderer and live next to it.

The shape this skill assumes, because it is the shape the tooling was built for: a **reference renderer in JavaScript** that owns every number (a table with one row per state, a tween between rows), a **C port** that mirrors it field for field and runs on the board, a **host build** of that C on the Mac that dumps frames, a **contact-sheet** tool for each renderer, a **parity check** between them in the driver's levels, and a **bench page**, a published artifact that runs the JS live. In Athena, all under `firmware/athena_matrix/`: `reference/aurora.js`, `main/aura.c`, `host/` (`sheet.py`, `sheet.mjs`, `parity.mjs`, `bench/make_bench.py`), and the Aura Bench artifact. The host scripts find their own files, so every Athena command below runs from the repo root, as its `CLAUDE.md` writes them.

## Fixed decisions

- **The JS owns the numbers, the C mirrors them.** Design in the reference, then port; never tune only one file. The port is proven when parity says `ok`; in Athena that covers the rows and constants as written, each state faded in from dark and each switch from idle. A parity check that compares frames alone misses a small one-file change to a colour, a brightness or a clock; with one, read the changed rows side by side as well. A change that fails is not done.
- **Preview through the driver.** Every sheet is rendered at the panel's bit depth with its dither, with the shader shape the board actually runs (copies, grid, layers), so what you see is what the LEDs will do, banding and blinking included. Never judge a look from a full-precision render.
- **Every state derives from one base state, and a state change is a tween.** The base state (idle in Athena) is the picture; other states are its row with different numbers, and the picture on the panel eases from one row to the next with the animation phases integrated, never reset. A state that looks like it was designed separately is a defect; a hard cut is a defect.
- **Colour fades on its own slower clock, in linear light, with a dip.** Hue jumps read as alarm. Only states that mean alarm change colour outright; the user's palette preference, when recorded in memory, wins over any of this.
- **Look before you build, build before you flash, flash only on an ask.** Sheets and parity on the Mac first; the firmware build proves it compiles; the esp-idf skill's flash rule governs flashing (an explicit ask in the current message, a resolved port).
- **The bench is one artifact.** Rebuild it from the template and republish to the existing URL after any table change; a new artifact splits the history and breaks the link the user has.

## Procedure

### 0. Orient

Read the repo's `CLAUDE.md` section on the renderer and the host tooling's `README.md`. Note the state list, the table's field order, the shader shape the board runs, the bench URL (memory note), and the taste notes in memory (which states may change colour, what the user found too aggressive). Check that `cc`, `node` and `python3` exist. If the ask is about the board rather than the picture (wiring, a port, a build error), load `esp-idf` instead or as well.

### 1. Baseline

Before changing anything, render the current state of things into `<scratchpad>/baseline` and keep it: the C sheets, the JS sheet and the parity output. In Athena:

```bash
python3 firmware/athena_matrix/host/sheet.py all --scale 2 --out <scratchpad>/baseline
node firmware/athena_matrix/host/sheet.mjs --scale 2 --out <scratchpad>/baseline/js-states.png
node firmware/athena_matrix/host/parity.mjs > <scratchpad>/baseline/parity.txt
```

Every later render goes to a fresh `<scratchpad>/round-N` (N counts up from 1), never to `baseline/` or the tools' default `host/out/`, which each run overwrites (`sheet.py` also deletes its old frames). If parity already fails, say so first; do not build on a port that has drifted. Read the printed summaries and `parity.txt` first, then look at the sheets once so you know what the states you are not touching look like.

### 2. Design in the reference

Change the table row or the shader in the JS. Start from the base state's row and move numbers, not hue, unless the state means alarm. Keep every field's meaning as the file documents it; do not add a field without adding it, in the same change, to every place that lists fields (Athena: the `AURA` row and `AURA_FIELDS` in `aurora.js`; `aura_state_t`, `aura_params_t`, the `states[]` columns and the `init_tables()` copy in `aura.c`, which parity checks against each other; the header comments and README). The C mix is generic and needs no edit.

### 3. Look, with a cap

Render the JS sheet (Athena: `node firmware/athena_matrix/host/sheet.mjs --scale 2 --out <scratchpad>/round-N/js-states.png`) and read the PNG. Judge each state at the instants the sheet samples and against the base state beside it. The JS sheet renders each state settled, with no tween; for a tween, fade, dip or shader change, build the bench locally (Athena: `python3 firmware/athena_matrix/host/bench/make_bench.py --out <scratchpad>/bench.html`, not published) and watch the switch in Chrome before porting. Iterate on the numbers, but after **three rounds** without the user, stop and put the sheet in front of them (send the file) with one sentence on what you changed and what you are unsure of. Taste rounds are theirs; the tooling makes a round cheap, not unnecessary.

### 4. Port to C, field for field

Mirror the change in the C table or code. Same numbers, same order, same units as the row holds (in Athena, colour as sRGB hex bytes in `AURA_COL` and the C row's `col[]`, haze as a 0..1 weight; linear RGB and the haze levels are derived by `auraParams()` and `init_tables()` and never typed in). If the change touched the shader or the tween, the C's comments name the JS function each block mirrors; keep them true.

### 5. Sheets, parity and the untouched states

Write the C sheets (states, fades, session) and the parity output into this round's directory:

```bash
python3 firmware/athena_matrix/host/sheet.py all --scale 2 --out <scratchpad>/round-N
node firmware/athena_matrix/host/parity.mjs > <scratchpad>/round-N/parity.txt
```

Read the printed summary and `parity.txt` before any PNG, and require `parity: ok`. A `CUT` in the summary, or a `table:` difference or an `OUT OF BAND` line in parity, is a defect to fix before anything else, not a note for the report. When the table is equal and frames still fail, suspect the tween, fade or phase code (a `dip` flag points at the fade); `node firmware/athena_matrix/host/parity.mjs --states <s> --verbose` isolates one state and prints the worst pixel. Parity also switches from idle into every other state; when the change is to a switch out of another state, run it again with `--from <state>` (e.g. `--from error --states idle`).

Then prove the states you did not touch did not move. `sheet.py` writes byte-identical frames from run to run, so compare this round's with the baseline's (the loop runs in zsh and bash):

```bash
for f in <scratchpad>/baseline/ppm/*/*.ppm; do
  cmp -s "$f" "<scratchpad>/round-N/ppm/${f#*/baseline/ppm/}" || echo "changed ${f#*/baseline/ppm/}"
done
```

Each line names `<scenario>/f<frame>_<state>.ppm`, 40 frames a second; a segment's first frame is its lowest-numbered file. A changed frame must belong to a state you changed, or fall in the tween out of one: the first 0.8 s (`AURA_TWEEN_S`) of the segment right after it, or its first 2 s (`AURA_FADE_S`) when the change touched a colour. A change to a state's `speed` or `rate` shifts the phases every later segment inherits, so then only the segments before its first appearance must match. Any other changed frame, above all an idle one, means you moved a state you did not mean to.

To judge a look, open sheets under about 2000 px on the long side (a larger PNG is downscaled on read, which blurs the dither): the `--scale 2` sheets above, or a focused sequence for one state such as `python3 firmware/athena_matrix/host/sheet.py idle:1 think:3 idle:1 --every 20 --out <scratchpad>/round-N/focus-think`. For each changed switch, render a transition strip and look at it, each into its own dir because `sheet.py` always writes `custom.png`: `python3 firmware/athena_matrix/host/sheet.py idle:2 <state>:2 --every 8 --scale 2 --out <scratchpad>/round-N/strip-<state>`.

### 6. Build, then flash on an ask

`idf.py build` for the target the project is set to, through the esp-idf skill (it sources the environment, checks the toolchain, finds the board). Build the other target only when the change touches per-target code. Flash only when the user asked for a flash in the current message, and only as the esp-idf skill's flash rule allows (it governs, and resolves the port); a request to build, fix or debug does not include flashing. Otherwise say the build is ready and stop there. After a flash, watch the log for the renderer's draw-time line and report its average and maximum against the frame budget, the project's frame period; a shader change can blow it. In Athena the budget is `FRAME_MS` in `main/face.c`, 25 ms (40 fps), and the `aura: draw … us avg, … us max` line repeats every `AURA_LOG_US` (5 s), so it first appears 5 s after the first aura frame, which comes only once a state is set (the board boots into the wiring test).

### 7. Bench: rebuild and republish in place

Build the page from the template (in Athena, `python3 firmware/athena_matrix/host/bench/make_bench.py --out <scratchpad>/bench.html`), then `Artifact read` the existing bench URL and publish to it with `url` set, keeping its icon and title. Open it in Chrome once and screenshot: the panel animates, the state buttons switch with a tween, the board/LiveKit toggle changes the picture. In Athena the page takes its numbers from the inlined `aurora.js`, `aura.c` and `face.c`; only the `LOOK` prose per state, the ttl labels and the session script are copied by hand, so update the prose when a state's character changes.

### 8. Docs and memory

Anything the user will meet again goes where they will meet it: the renderer's header comment and the firmware README for how it works; `CLAUDE.md` for the layout and the rules; the memory note for the bench if its URL or build path changed; a feedback memory for a taste the user stated ("too aggressive", "fade, not switch"), with the why. Keep the three docs consistent by hand.

### 9. Report

Lead with what the panel does differently now, one line per state that changed, then the evidence: the sheets before and after (sent as files, from `<scratchpad>/baseline` and the last round), the parity line, the build result, the bench URL, whether anything was flashed or committed (say plainly when not). Numbers that changed go in a small table with before and after. Do not restate the procedure.

## Reading a sheet

- **The first tile of a row** (C sheets only) is the first frame after the switch, so it still looks like the row above. The blend appears in the next tiles: in `fades`, the 0.25 s tiles; in `states`, the +1 s tile, which is halfway through the colour fade. The first tile of a sheet is black because it is a cold start. The JS sheet has no tweens; each tile shows a state on its own.
- **Banding and speckle** near the dark end are the quantiser; a shape that survives only at its densest part needs more base brightness, not a different shape.
- **A dark ring around anything** (text, a frame) is a halo dimming toward black instead of toward the background level.
- **A flash of white in a fade**: first check whether the target state's own pulse or flash peaks at that instant. Only then suspect a colour mix passing through its midpoint without the dip.
- **The summary's `switch` column** says whether the tween restarted from what was on the panel; `max mad` inside a segment is the state's own rhythm (a beat, a flash), and a single sample moving 20+ levels is any bright edge crossing a pixel, so judge `CUT`, look at the rest.
- **Power**: brightness has a current cost on a big panel; the project's design notes give the budget. A state that is much brighter than the base state needs a reason.

## Rules of the medium

Learned on a 64×64 HUB75 panel with 5-bit levels; they hold for any low-bit-depth LED display.

- A background haze lives at level 1 or 2. It cannot fade in linear light; it fades by dithering between two whole levels, so keep haze in levels per channel and mix it as such.
- Black beside a lit pixel reads as a hole. Dim toward the floor, never to zero.
- A linear-light mix of two saturated colours passes through near-white; dip brightness at the midpoint.
- A shape's edge moving one pixel changes that pixel by up to the full range; that is not a jump, a whole picture moving is.
- A hash that is noise in float on the board is not the JS's hash; when the board hashes with integers, the JS must too, or the bench plays a different sequence (and index 0 must not hash to a forced rest).
- Table sines, fast square roots and interpolated gamma put the C one level off here and there; that is the expected band, not drift.

## Degradation

- No `node`: the C sheets (`sheet.py`) stand alone; say the JS sheet and parity were skipped.
- No `cc`: the JS sheet stands alone; say the C was not checked and do not claim parity.
- No board on USB: build and stop; say so.
- Bench URL unreadable or gone: say so, publish a new one only if the user agrees, and update the memory note.
- The user's taste note contradicts the ask: state the conflict in one sentence, follow the ask, and update the note only if they confirm the change of taste.

## Boundaries

- Never change the base state's look unless the user asked for that state by name.
- Never flash without an explicit ask in the current message (a request to build, fix or debug is not one); the esp-idf skill's flash rule governs. Never commit unless asked.
- Never publish the bench as a new artifact while the existing URL works.
- Never tune only the C or only the JS, and never widen the parity band to make a change pass.
