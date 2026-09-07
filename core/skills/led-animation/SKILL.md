---
name: led-animation
description: Designs, tunes and verifies animations for an LED matrix panel driven by ESP32 firmware, where a JavaScript reference renderer and its C port must stay one picture. Renders contact sheets and transition strips on the Mac, host-builds the C renderer, checks C/JS parity in driver levels, republishes the live bench page in place, then builds and flashes through the esp-idf skill. Use whenever the user mentions the LED face or matrix, an agent state on the panel (idle, listen, think, work, speak, alert, error, sleep), the aura, a contact sheet or the bench, a tween or fade between states, colours, brightness, haze or dither on the panel, or how the panel looks.
compatibility: Claude Code on macOS with cc (Xcode command line tools), node and python3. The project supplies the renderers and the host tooling; the board side goes through the esp-idf skill.
---

# Animation for an LED matrix panel

Personal skill: the workflow and the boundaries for changing what a low-bit-depth LED panel shows. Everything specific to a project comes from the repo you are in: its `CLAUDE.md` (which states exist, where the per-state table lives, where the host tooling is), the host tooling's own `README.md`, and the memory notes (the bench artifact URL, the user's taste). Read those first; never guess a state list, a table location or a URL. No scripts are bundled here, because the tools compile the project's own C renderer and live next to it.

The shape this skill assumes, because it is the shape the tooling was built for: a **reference renderer in JavaScript** that owns every number (a table with one row per state, a tween between rows), a **C port** that mirrors it field for field and runs on the board, a **host build** of that C on the Mac that dumps frames, a **contact-sheet** tool for each renderer, a **parity check** between them in the driver's levels, and a **bench page**, a published artifact that runs the JS live. In Athena: `firmware/athena_matrix/reference/aurora.js`, `main/aura.c`, `host/` (`sheet.py`, `sheet.mjs`, `parity.mjs`, `bench/make_bench.py`), and the Aura Bench artifact.

## Fixed decisions

- **The JS owns the numbers, the C mirrors them.** Design in the reference, then port; never tune only one file. The parity check is the proof that the port happened; a change that passes the sheets but fails parity is not done.
- **Preview through the driver.** Every sheet is rendered at the panel's bit depth with its dither, with the shader shape the board actually runs (copies, grid, layers), so what you see is what the LEDs will do, banding and blinking included. Never judge a look from a full-precision render.
- **Every state derives from one base state, and a state change is a tween.** The base state (idle in Athena) is the picture; other states are its row with different numbers, and the picture on the panel eases from one row to the next with the animation phases integrated, never reset. A state that looks like it was designed separately is a defect; a hard cut is a defect.
- **Colour fades on its own slower clock, in linear light, with a dip.** Hue jumps read as alarm. Only states that mean alarm change colour outright; the user's palette preference, when recorded in memory, wins over any of this.
- **Look before you build, build before you flash, flash only on an ask.** Sheets and parity on the Mac first; the firmware build proves it compiles; the esp-idf skill's boundary governs flashing (an explicit ask, a known port).
- **The bench is one artifact.** Rebuild it from the template and republish to the existing URL after any table change; a new artifact splits the history and breaks the link the user has.

## Procedure

### 0. Orient

Read the repo's `CLAUDE.md` section on the renderer and the host tooling's `README.md`. Note the state list, the table's field order, the shader shape the board runs, the bench URL (memory note), and the taste notes in memory (which states may change colour, what the user found too aggressive). Check that `cc`, `node` and `python3` exist. If the ask is about the board rather than the picture (wiring, a port, a build error), load `esp-idf` instead or as well.

### 1. Baseline

Before changing anything, render the current state of things and keep the images: the JS sheet and the C sheets (in Athena, `node host/sheet.mjs` and `python3 host/sheet.py all`), and run the parity check. If parity already fails, say so first; do not build on a port that has drifted. Look at the baseline once so you know what "the same as before" means for the states you are not touching.

### 2. Design in the reference

Change the table row or the shader in the JS. Start from the base state's row and move numbers, not hue, unless the state means alarm. Keep every field's meaning as the file documents it; do not add a field without adding it to the C struct, the mix function, the bench's live row and the docs in the same change.

### 3. Look, with a cap

Render the JS sheet and read the PNG. Judge each state at the instants the sheet samples and against the base state beside it. Iterate on the numbers, but after **three rounds** without the user, stop and put the sheet in front of them (send the file) with one sentence on what you changed and what you are unsure of. Taste rounds are theirs; the tooling makes a round cheap, not unnecessary.

### 4. Port to C, field for field

Mirror the change in the C table or code. Same numbers, same order, same units (colour as linear RGB if that is what the row holds, haze as whole driver levels, and so on). If the change touched the shader or the tween, the C's comments name the JS function each block mirrors; keep them true.

### 5. Sheets and parity from the C

Run the C sheets (states, fades, session) and read the summary and the PNGs; then run the parity check and require `ok`. A `CUT` in the summary or an `OUT OF BAND` state in parity is a defect to fix before anything else, not a note for the report. Parity outside the band with the mean level off by a few percent is almost always a row changed in one file; a whole region off is the tween or a phase integrated differently.

### 6. Build, then flash on an ask

`idf.py build` for the target the project is set to, through the esp-idf skill (it sources the environment, checks the toolchain, finds the board). Build the other target only when the change touches per-target code. Flash only when the user asked for it in this conversation and the named board is on USB; otherwise say the build is ready and stop there. After a flash, watch the boot log for the renderer's draw-time line and report it: the board has a frame budget and a shader change can blow it.

### 7. Bench: rebuild and republish in place

Build the page from the template (in Athena, `python3 host/bench/make_bench.py --out <scratchpad>/bench.html`), then `Artifact read` the existing bench URL and publish to it with `url` set, keeping its icon and title. Open it in Chrome once and screenshot: the panel animates, the state buttons switch with a tween, the board/LiveKit toggle changes the picture. If the page has hand-written prose per state (Athena's `LOOK` table), update the line for any state whose character changed; it is not derived.

### 8. Docs and memory

Anything the user will meet again goes where they will meet it: the renderer's header comment and the firmware README for how it works; `CLAUDE.md` for the layout and the rules; the memory note for the bench if its URL or build path changed; a feedback memory for a taste the user stated ("too aggressive", "fade, not switch"), with the why. Keep the three docs consistent by hand.

### 9. Report

Lead with what the panel does differently now, one line per state that changed, then the evidence: the sheet (sent as a file), the parity line, the build result, the bench URL, whether anything was flashed or committed (say plainly when not). Numbers that changed go in a small table with before and after. Do not restate the procedure.

## Reading a sheet

- **The first tile of a row is the switch** from the row above, mid-tween. It should look like a blend of the two, never like either one alone and never dark.
- **Banding and speckle** near the dark end are the quantiser; a shape that survives only at its densest part needs more base brightness, not a different shape.
- **A dark ring around anything** (text, a frame) is a halo dimming toward black instead of toward the background level.
- **A flash of white in a fade** is a colour mix passing through its midpoint without the dip.
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
- Never flash without an explicit ask in this conversation; never commit unless asked.
- Never publish the bench as a new artifact while the existing URL works.
- Never tune only the C or only the JS, and never widen the parity band to make a change pass.
