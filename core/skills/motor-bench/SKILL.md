---
name: motor-bench
description: Safety rules for any agent command that spins a motor or moves an actuator - ESC and motor bench tests, throttle sweeps, thrust-stand runs, arm/disarm and flight sequences on a flight controller's serial console, and CAN or serial actuator tests on a robot (mode changes, torque, kP/kD, calibration spins). Covers what may be sent, what the user confirms first (props off or robot secured, motor power, a kill path), and how each test is bounded, stopped and reported against limits. Project facts come from the repo's CLAUDE.md Motors section. Use whenever the user mentions a motor, ESC, prop or propeller, throttle, arm or disarm, a spin test, thrust stand, flight sequence or mission, hover, actuator, torque, kP/kD, servo, BLDC, e-stop or kill switch, or asks to run anything that makes hardware move. Load it with esp-idf when flashing or resetting a board wired to ESCs or drivers. Not for wiring or schematics (kicad-review), builds or serial reads alone (esp-idf), or simulation (isaac).
compatibility: Any agent. Sending a command needs the project's own sender tool and the board or bus on this Mac; reading output uses the esp-idf skill's serial_tail.py. No bundled scripts.
---

# Motor bench

Personal skill for every repo with hardware that moves. It owns one boundary: commands that make something spin or move. esp-idf owns building, flashing and reading the serial port; kicad-review owns the board design; the repo owns its facts. Nothing below is a project fact: the commands, limits and kill path come from the project, never from memory or from the examples here.

## What counts as a moving command

Anything that can put current through a motor or change an actuator's target: a console key or line (throttle level, sweep, auto test, arm, mission, ESC calibration), a script that changes a controller's mode, gains, torque or position target, a calibration spin, and a flash or reset of a board wired to powered ESCs or drivers. A "dry run" or motors-off variant counts too while motor power is connected, when it differs from the live command only by an argument: one lost word turns it into the live command. The stop is not a moving command: on the bench it never needs an ask (in flight, rule 8).

## Project facts: the `## Motors` section

Read it first, from `CLAUDE.md` or `CLAUDE.local.md` in the project directory or the repo root:

```bash
for d in "<dir>" "$(git -C "<dir>" rev-parse --show-toplevel 2>/dev/null)"; do for f in CLAUDE.md CLAUDE.local.md; do [ -f "$d/$f" ] && awk '/^##?[ \t]/{p=/^## Motors[[:space:]]*$/} p' "$d/$f"; done; done | awk '!s[$0]++'
```

Put it after `## Hardware` (kicad-review), not straight after `## Boards`: esp-idf reads a fixed 12 lines after that heading. One `key: value` per line. When a value differs per program (bench firmware, flight firmware, a host script), repeat the key and start the value with the program's name.

```
## Motors
rule: agents send a moves command only for a test the user asked for (this message, or the one before the pre-condition question), never a user-only one, and never flash or --reset with motor power on (motor-bench skill)
rig: <what moves, e.g. 4 PWM ESCs + motors on a quad frame, or CAN FOC actuators>
program: <name> <source path> banner /<regex it prints at boot or on help>/
send: <name> <tool an agent may use, with baud or bus> | none (the user types)
probe: <command harmless in every program> -> <line each program prints>
moves: <name> <every command that can move something>
stop: <name> <exact stop command> -> <output line that confirms it>
user-only: <commands no agent sends: flight, arm, hover, walking, full-output calibration>
kill: <physical kill the user holds: battery plug, breaker, RC switch> | none
limits: <caps, slew, dead-man, torque and current limits, each with the file:line that sets it>
watchdog: <dead-man or watchdog and its timeout> | none
supply: <bench supply and its current limit> | <battery, cells>
direction: <expected spin or joint direction per output, and its source>
log: <file for the per-test record> | reply only
```

The `rule:` line matters because CLAUDE.md is always loaded and this skill is not: "run the mission" may not name a motor.

No section: read the program's command parser and the project's docs, draft the section with a file:line behind every value, show it, and write it only after a yes. Until then send nothing whose stop you have not read in the source. Never guess a stop command.

## Rules

1. **Asked, stated, confirmed, then sent.** A moving command goes out only for the specific test the user asked for in their current message, or in the message just before your pre-condition question. First state in one or two lines what moves (which motor or joint), at what level (µs, %, A, Nm, kP/kD), for how long, and what stops it (the command and the physical kill). Never as a side effect of another task (a fix, "check it works"), never chained behind a build, flash or another test, never from a loop, retry, background job or schedule. After a failure, stop, report and wait. The only thing that may follow a moving command in the same call is its stop.

2. **Pre-conditions, answered by the user.** Ask once per bench setup and again after anything changes (props, wiring, power, program, a level above the last one confirmed). An item the user did not answer is not confirmed.
   - Props off, or the rotor guarded; the motor or actuator clamped; a robot on a stand or suspended, with its joints free through the commanded range.
   - Area clear of hands, cables and loose parts.
   - Power: which source, and the supply's current limit.
   - Kill: the physical kill within the user's reach, and the stop command already tried at idle.
   - Motor power disconnected, when a dry run, a flash or a `--reset` comes next.

3. **Know the program before the first byte.** Two boards of one project can give the same key opposite meanings, so the wrong port is the real risk (e.g. aquila: `a` selects all motors on the bench board and arms and takes off on the flight board; `m2000` raises the bench cap and arms the full mission in flight). Match the `program:` banner with esp-idf's `serial_tail.py -C "<dir>" --until '<banner>'` (`-C` picks the project's console baud; `--reset` only with motor power off, rule 2), or send the `probe:` command. Program unknown or unconfirmed: send nothing; give the user the command.

4. **Bounded.** Every test has a level cap and a duration. Prefer the firmware's own caps, slew limits, dead-man and timed tests over holding a level from the host. Lowest level first; one motor or actuator at a time, all together only after each passed alone; step up only after the last step's numbers were reported and the user asked for the next. A command that holds a level until told otherwise (a set point, a script that runs until Ctrl+C) goes out only with its stop in the same bounded call; otherwise the user runs it. Raising a runtime cap needs the new value in the user's message and the program confirmed (rule 3). Send only through the `send:` tool (none: the user types); never improvise a serial or CAN writer.

5. **Always a stop.** Before sending, know this program's stop and the line that confirms it. On the bench, send the stop on every exit path: test done, error, timeout, unexpected output, tool failure, user interruption, or doubt about whether the last command arrived. Stop through the program's own path (its stop command, or SIGINT to a script whose handler switches to damping); never SIGKILL a motor process or close the port as the stop: that skips the handler and leaves the last target in place until a watchdog, if there is one, fires. Then read the state back and quote the confirming line. Stop not confirmed: the first line of the reply tells the user to use the physical kill now.

6. **Safety code is not a test knob.** Never change a cap, slew limit, dead-man or watchdog timeout, arming check, failsafe threshold, motor-cut timer, torque or current limit, or default gain to make a test pass or "for now". Change one only when the user asked for that change; call it out in the reply as old -> new with file:line, keep it out of any other change, and flash it under rule 7.

7. **Flashing or resetting a rig.** esp-idf's flash rule applies (the ask may sit in the message before your motor-power question). A flash or reset of a board wired to ESCs or drivers waits until the user has confirmed motor power is disconnected (rule 2), and the reply says what the new image does to the motors at boot.

8. **Flight, whole-robot motion and full output belong to the user.** Arming for flight, hover, a mission or flight sequence, walking or any policy that moves the whole vehicle or robot, an ESC throttle-range calibration (it outputs full throttle), and any command sent to the vehicle or robot over radio or network: prepare it, explain it, and hand the user the exact command. Never send it, through any tool, script or schedule, even when asked; say why in one line. Its motors-off variant (a dry run) goes out only after the user confirmed, in this or the previous message, that motor power is unplugged; otherwise hand that over too. While the vehicle is armed or airborne every command is the user's, the stop included (a stop drops it, a set-point change moves it): tell them to land or kill it now. This weighs more when the only stops are a tethered console or a timer (e.g. aquila: no wireless kill; the mission ends on a clock, hover only on a tethered `l` or `d`).

## Reading and reporting

Read through bounded tools only: esp-idf's `serial_tail.py` with `--seconds` and `--until`, or a script's own readback with a timeout; never an interactive monitor. If the user's monitor holds the port, don't open it and don't kill it: the user types the commands and pastes the lines.

Report each number against the limit it is checked against: current vs the supply limit and the ESC or driver rating, RPM or eRPM, temperature, torque vs the torque limit, position error, bus voltage sag, error or fault bits, direction vs `direction:`. What was not measured says `not measured`; sound, smell and heat by hand are the user's observations, reported as theirs. One record line per test, appended to the `log:` file (else in the reply):

```
<YYYY-MM-DD HH:MM> <program> <motor/joint> <level> <duration> | <numbers vs limits> | stop: <confirming line>
```

## Code that commands motors

Writing or editing it is fine; running it follows the rules above. It stops or switches to damping on every exit path (exception, SIGINT, timeout), carries a hard duration, and takes its limits from the project's config, never above them (e.g. berkley CLAUDE.md §0: DAMPING on every exit, the firmware watchdog fed, single-actuator tests with small kP/kD).

## Degradation

- No physical kill the user can reach: no moving command from the agent; hand the user the commands.
- Unknown ESC firmware, uncalibrated or mixed ESCs on one frame: assume the throttle maps differ; lowest level, one motor at a time, each at the same level and compared; calibration is the user's (rule 8).
- No current limit (battery only): lowest level, shortest duration, one motor; no cap raise until a current reading or a limited supply exists.
- No telemetry: the stop cannot be confirmed from output, so the user says "stopped" before anything else is sent; never step up by sound.
