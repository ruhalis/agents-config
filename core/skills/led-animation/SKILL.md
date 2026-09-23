---
name: led-animation
description: Designs, tunes and verifies animations for an LED matrix panel driven by ESP32 firmware, where a JavaScript reference renderer and its C port must stay one picture. Renders contact sheets and transition strips on the Mac, host-builds the C renderer, checks C/JS parity in driver levels, republishes the live bench page in place, then hands the build (and a flash, only on request) to the esp-idf skill. Use whenever the user mentions the LED face or matrix, an agent state on the panel (idle, listen, think, work, speak, alert, error, sleep), the aura, a contact sheet or the bench, a tween or fade between states, colours, brightness, haze or dither on the panel, or how the panel looks. Not for wiring, pin maps, the HUB75 driver, Wi-Fi, the face protocol or its clients, or a flash on its own; those go to esp-idf and the project docs.
compatibility: Claude Code on macOS with cc (Xcode command line tools), node and python3. The project supplies the renderers and the host tooling; the board side goes through the esp-idf skill.
---

# Animation for an LED matrix panel

Personal skill: the workflow and the boundaries for changing what a low-bit-depth LED panel shows. Everything specific to a project comes from the repo you are in: its `CLAUDE.md` (which states exist, where the per-state table lives, where the host tooling is), the host tooling's own `README.md`, and the memory notes (the bench artifact URL, the user's taste). Read those first; never guess a state list, a table location or a URL. No scripts are bundled here, because the tools compile the project's own C renderer and live next to it.

The shape this skill assumes, because it is the shape the tooling was built for: a **reference renderer in JavaScript** that owns every number (a table with one row per state, a tween between rows), a **C port** that mirrors it field for field and runs on the board, a **host build** of that C on the Mac that dumps frames, a **contact-sheet** tool for each renderer, a **parity check** between them in the driver's levels, and a **bench page**, a published artifact that runs the JS live. In Athena, all under `firmware/athena_matrix/`: `reference/aurora.js`, `main/aura.c`, `host/` (`sheet.py`, `sheet.mjs`, `parity.mjs`, `bench/make_bench.py`), and the Aura Bench artifact. The host scripts find their own files, so every Athena command below runs from the repo root, as its `CLAUDE.md` writes them.

## Fixed decisions

- **The JS owns the numbers, the C mirrors them.** Design in the reference, then port; never tune only one file. The port is proven by two checks together: the changed rows and constants, read side by side, are equal in both files, and parity says `ok`. Parity alone is not proof: it bands per-sample differences at two instants of a fade-in from dark, so a small colour, brightness, fade-clock or dip change made in one file passes it. A change that fails either check is not done.
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
python3 firmware/athena_matrix/host/sheet.py all --out <scratchpad>/baseline
node firmware/athena_matrix/host/sheet.mjs --out <scratchpad>/baseline/js-states.png
node firmware/athena_matrix/host/parity.mjs > <scratchpad>/baseline/parity.txt
```

Every later render goes to a fresh `<scratchpad>/round-N` (N counts up from 1), never to `baseline/` or the tools' default `host/out/`, which each run overwrites (`sheet.py` also deletes its old frames). If parity already fails, say so first; do not build on a port that has drifted. Look at the baseline once so you know what "the same as before" means for the states you are not touching.

### 2. Design in the reference

Change the table row or the shader in the JS. Start from the base state's row and move numbers, not hue, unless the state means alarm. Keep every field's meaning as the file documents it; do not add a field without adding it, in the same change, to every place that lists fields (Athena: the `AURA` row and `AURA_FIELDS` in `aurora.js`; `aura_state_t`, `aura_params_t`, the `states[]` columns and the `init_tables()` copy in `aura.c`; `FIELDS` in `bench.template.html`; the header comments and README). The C mix is generic and needs no edit.

### 3. Look, with a cap

Render the JS sheet (Athena: `node firmware/athena_matrix/host/sheet.mjs --out <scratchpad>/round-N/js-states.png`) and read the PNG. Judge each state at the instants the sheet samples and against the base state beside it. The JS sheet renders each state settled, with no tween; for a tween, fade, dip or shader change, build the bench locally (Athena: `python3 firmware/athena_matrix/host/bench/make_bench.py --out <scratchpad>/bench.html`, not published) and watch the switch in Chrome before porting; for a tween or fade duration change, set the page's tween and fade sliders to the new values first, since it does not read `AURA_TWEEN_S` or `AURA_FADE_S`. Iterate on the numbers, but after **three rounds** without the user, stop and put the sheet in front of them (send the file) with one sentence on what you changed and what you are unsure of. Taste rounds are theirs; the tooling makes a round cheap, not unnecessary.

### 4. Port to C, field for field

Mirror the change in the C table or code. Same numbers, same order, same units as the row holds (in Athena, colour as sRGB hex bytes in `AURA_COL` and the C row's `col[]`, haze as a 0..1 weight; linear RGB and the haze levels are derived by `auraParams()` and `init_tables()` and never typed in). If the change touched the shader or the tween, the C's comments name the JS function each block mirrors; keep them true. If `AURA_RES`, `AURA_COPIES` or `AURA_LAYERS` change, update `sheet.mjs`'s defaults and the bench's shape lines in the same change; only `parity.mjs` reads them from `aura.c`.

### 5. Rows, sheets and parity from the C

Print the changed rows and constants from both files and compare every number (Athena: the `AURA` and `AURA_COL` rows and the `AURA_*` constants in `aurora.js` against `states[]` and the `#define`s in `aura.c`):

```bash
sed -n '/var AURA_COL = {/,/AURA_WRAP_S = /p' firmware/athena_matrix/reference/aurora.js
sed -n '/#define AURA_BLUR/,/#define TIME_WRAP_S/p;/aura_state_t states\[/,/^};/p' firmware/athena_matrix/main/aura.c
```

Then write the C sheets (states, fades, session) and the parity output into this round's directory, and read the summary, the PNGs and `parity.txt`:

```bash
python3 firmware/athena_matrix/host/sheet.py all --out <scratchpad>/round-N
node firmware/athena_matrix/host/parity.mjs > <scratchpad>/round-N/parity.txt
```

Require `parity: ok`, and divide the two means in each state's last column (`mean level (js / c)`) and compare that ratio with the same sample in `baseline/parity.txt` from step 1: on a sample where both means are 0.3 or more, a shift of more than about 1 % points to a one-file change. Below 0.3 (sleep at 0.475 reads under 0.1) the printed means are too coarse for that. No shift proves nothing either: a small one-file speed change can pass parity and move no ratio, so the row compare decides. A `CUT` in the summary or an `OUT OF BAND` state in parity is a defect to fix before anything else, not a note for the report. When parity fails, compare the rows and constants again first: a one-file speed change can fail with the mean almost unchanged and a rate or freq change can move it 5 % or more, so the mean does not say which. Suspect the tween or phase code only when they match. `node firmware/athena_matrix/host/parity.mjs --states <s> --verbose` isolates one state and prints the worst pixel.

Parity only fades each state in from dark. It never runs a tween between two states, the colour fade or the dip, so it cannot check them. For those changes, rely on the row and constant compare above, compare `fades` with the baseline's, and render a transition strip for each changed switch, each into its own dir because `sheet.py` always writes `custom.png`, e.g. `python3 firmware/athena_matrix/host/sheet.py idle:2 <state>:2 --every 8 --out <scratchpad>/round-N/strip-<state>`.

### 6. Build, then flash on an ask

`idf.py build` for the target the project is set to, through the esp-idf skill (it sources the environment, checks the toolchain, finds the board). Build the other target only when the change touches per-target code. Flash only when the user asked for a flash in the current message, and only as the esp-idf skill's flash rule allows (it governs, and resolves the port); a request to build, fix or debug does not include flashing. Otherwise say the build is ready and stop there. After a flash, watch the boot log for the renderer's draw-time line and report it: the board has a frame budget and a shader change can blow it.

### 7. Bench: rebuild and republish in place

Build the page from the template (in Athena, `python3 firmware/athena_matrix/host/bench/make_bench.py --out <scratchpad>/bench.html`), then `Artifact read` the existing bench URL and publish to it with `url` set, keeping its icon and title. Open it in Chrome once and screenshot: the panel animates, the state buttons switch with a tween, the board/LiveKit toggle changes the picture. The template keeps hand-copied values that `make_bench.py` does not derive and its `--check` does not test (it only checks the inlined JS). In Athena these are the `LOOK` prose per state, the `tweenS`/`fadeS` defaults and the tween and fade sliders' values, and the `iters`/`grid`/`layers` defaults, the shape prose and the board button label. Update every one the change touched; grep the template for the old number.

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
