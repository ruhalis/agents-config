---
name: esp-idf
description: Builds, flashes, monitors, and debugs Espressif boards (ESP32, ESP32-S3, ESP32-C3, ESP32-C6, and other Espressif chips) with pure ESP-IDF on macOS, never Arduino or PlatformIO. Use whenever the user mentions ESP32, ESP-IDF, idf.py, esptool, sdkconfig, Kconfig, FreeRTOS on an Espressif chip, flashing a board, a serial port, or firmware for an Espressif chip.
compatibility: Claude Code on macOS with Homebrew, git, and Python 3. ESP-IDF itself is installed per setup-macos.md; a board on a USB serial port is needed to flash or monitor.
---

# ESP-IDF on this Mac

Personal skill: it applies in every repo and holds the workflow, the toolchain pin, and the boundaries. Project facts (board and chip, pin map, project layout, the name of the secrets header, shared components) come from the repo you are in: its `CLAUDE.md`, design notes, and existing `sdkconfig.defaults`. Read those first; never guess board facts.

Bundled files. `${CLAUDE_SKILL_DIR}` is the directory holding this SKILL.md (Claude Code substitutes it; in another tool use that directory's path).

| File | Use |
|---|---|
| `idf-version` | Read. The pinned ESP-IDF tag for this machine, the only authoritative copy. |
| `setup-macos.md` | Read only when installing or bumping the toolchain. |
| `scripts/check_toolchain.sh` | Run. Read-only: is IDF installed, does it match the pin, does `export.sh` work, which boards are on USB. |
| `scripts/serial_tail.py` | Run. Bounded serial reader that replaces `idf.py monitor` in tool calls. |

## Fixed decisions

- **Pure ESP-IDF.** No Arduino IDE, no Arduino core, no PlatformIO, no pioarduino. C by default; C++ only where a library forces it, kept behind one wrapper that exposes `extern "C"` functions. If a project needs an Arduino-only library, bring it in as an IDF component; never switch the build system.
- **One toolchain per machine.** Checkout at `~/esp/esp-idf` at the tag in `idf-version`, tools in `~/.espressif/`. Every project on this Mac builds against it. Bumping is a deliberate change: edit `idf-version`, follow the bump step in `setup-macos.md`, rebuild every project that uses it. Never bump to fix one build error.
- **The chip comes from the project.** `idf.py set-target <chip>` with whatever the repo's docs or existing `sdkconfig.defaults` say. If nothing says, ask; never default silently.
- **Installing or changing the toolchain changes the machine** (Homebrew packages, a large download, a Python venv). Do it only when the user asks for it in that message, following `setup-macos.md` step by step. Otherwise report what `check_toolchain.sh` says and point at that file.

## What an IDF project looks like

`CMakeLists.txt` at the project root, `main/` with its own `CMakeLists.txt`, `main/idf_component.yml` for registry dependencies, `sdkconfig.defaults`, and `partitions.csv` when the table is custom. Shared code goes in a `components/` directory added through `EXTRA_COMPONENT_DIRS`.

| Committed | Generated, never committed |
|---|---|
| `sdkconfig.defaults`, `partitions.csv`, `dependencies.lock`, `*.h.example` | `sdkconfig`, `sdkconfig.old`, `build/`, `managed_components/`, the real secrets header |

Before the first commit in a new project, make sure its `.gitignore` covers the right column; add the lines if it does not. Registry dependencies go through the component manager, never copied sources: `idf.py add-dependency "<name>"` from the project directory, then commit the changed `idf_component.yml` and `dependencies.lock`. One exception: a manifest with Kconfig-conditional `rules:` dependencies makes the lock file machine-specific, so leave it out then. Credentials live in a gitignored header with a committed `.example` next to it, named by the project.

## Procedure

### 0. Environment, every command

Environment variables do not persist between Bash calls, so every call that runs `idf.py` or the bundled Python script starts by sourcing the export script. Silence it: its status lines go to stderr. If activation fails, `idf.py` is simply not on `PATH` and the call ends with `command not found`; run `check_toolchain.sh` then, it shows why. The working directory does persist, so run from the project root and pass `-C <dir>` only when the project is somewhere else.

```bash
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && idf.py build
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && idf.py -C /path/to/project build
```

Once per session, before the first `idf.py`:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check_toolchain.sh"
```

Exit 0: go. Exit 1: not installed, tools missing, or `export.sh` fails: stop, quote its output, and offer `setup-macos.md`. A tag that differs from the pin is a warning it prints, not a stop; never switch the checkout yourself.

### 1. Find the board

Ports on macOS are `/dev/cu.*`, never `/dev/tty.*` (that one blocks on open). The ESP32-S3 and ESP32-C6 DevKitC boards have two USB-C connectors: **UART** (a CP210x or CH34x bridge, shows as `/dev/cu.usbserial-<serial>`, `/dev/cu.SLAB_USBtoUART`, or `/dev/cu.wchusbserial*`) and **USB** (native USB-Serial-JTAG, shows as `/dev/cu.usbmodem*`). The C3 devkits and the classic ESP32 DevKitC have one connector, which is the bridge. Prefer the UART one: a bridge with a programmed serial number keeps its name wherever it is plugged in, and it survives a crashing firmware. The native port is named after the physical USB port it sits in, re-enumerates on every reset, and vanishes if the firmware reconfigures USB or sleeps.

Resolve the port in this order:

1. `CLAUDE.local.md` in the project root. Claude Code loads it every session, so if it has a `## Boards` section you already know the ports:

   ```
   ## Boards
   <board name>: /dev/cu.usbserial-XXXXXXXX
   ```

2. A port the user named in this message.
3. `ls /dev/cu.usbserial-* /dev/cu.SLAB_USBtoUART* /dev/cu.wchusbserial* /dev/cu.usbmodem* 2>/dev/null`. Exactly one: use it and offer to record it in `CLAUDE.local.md` (create the file with just that section if it does not exist, and add `CLAUDE.local.md` to `.gitignore` if it is not there; Claude Code does not do that for you). Zero: say no board is on USB, remind them of the UART connector, and stop. More than one: list them and ask which. Never guess, never loop over ports.

A `usbserial-0001` suffix is a generic serial shared by many cheap bridges, so two such boards cannot be told apart by name; say so and ask the user to plug in one at a time.

### 2. Configure

- `idf.py set-target <chip>` once per fresh checkout. It clears `build/` and generates `sdkconfig` from `sdkconfig.defaults`.
- **Never run `idf.py menuconfig`.** It is an interactive TUI and hangs a tool call. Edit `sdkconfig.defaults`, then regenerate with `rm -f sdkconfig && idf.py reconfigure`.
- A misspelled key is not an error. The configure step only prints `warning: unknown kconfig symbol` and carries on, so grep its output for that line, then confirm the keys that matter landed with a `grep` on the generated `sdkconfig`.
- Take Kconfig keys from the project's docs, an Espressif example's `sdkconfig.defaults`, or the IDF Kconfig files for that chip. Never invent keys.

### 3. Build

```bash
idf.py build
```

Read errors from the **first** `error:` line, not the last; the tail is CMake noise. Fix code in the project; never patch `~/esp/esp-idf` or `managed_components/`. If an upstream component needs a change, copy it into the project's `components/` under a new name. Never silence a warning with `-Wno-*` or `-fpermissive`. Use `idf.py size` when flash or RAM is in question.

### 4. Flash, an authorization boundary

Building is free. **Flashing is not.** Flash only when the user asked for it in this message ("flash it", "upload", "put it on the board") and only to a port resolved in step 1. A request to build, fix, or debug does not include flashing. Never flash while a monitor holds the port.

```bash
idf.py -p "<port>" flash
```

`idf.py -p "<port>" erase-flash` wipes NVS, the partition table, and any data partitions (models, filesystems, calibration). Run it only after the user has answered an explicit "erase the flash on <board>?" with yes in this conversation. Never chain it "to be safe".

If esptool cannot connect: report it, suggest holding **BOOT**, tapping **RESET**, releasing **BOOT** to force download mode, then retry once. Never retry in a loop.

### 5. Watch the board

For the user at their own terminal: `idf.py -p "<port>" monitor`, exit with `Ctrl+]`. **Never run it from a tool call**, alone or combined (`idf.py flash monitor`): it never returns.

From a tool call run the bounded reader. It needs the IDF venv's pyserial, so it takes the same export prefix, and `python` there is the venv's:

```bash
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && python "${CLAUDE_SKILL_DIR}/scripts/serial_tail.py" "<port>" --seconds 20 --reset
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && python "${CLAUDE_SKILL_DIR}/scripts/serial_tail.py" "<port>" --seconds 30 --reset --until 'Found 8MB PSRAM'
```

`--reset` pulses the board so the boot log is captured from its first line. `--until <regex>` exits 0 on the first matching line and exits 2 if the deadline passes without one; use it for boot checkpoints (PSRAM size, IP address, a "ready" line). `--seconds` is capped at 60 and `--max-lines` (default 400) stops a chatty firmware from flooding the call. Quote at most 30 lines of log back to the user: the panic or the checkpoint, not the whole boot.

Backtraces come out raw; decode them with the chip's toolchain from the export shell:

- Xtensa (ESP32, S2, S3): `xtensa-esp-elf-addr2line -pfiaC -e build/<project>.elf <addr> ...` on the `Backtrace:` addresses.
- RISC-V (C-, H-, P-series): the panic prints registers and a stack dump, no backtrace. Save the panic text to a file and run `riscv32-esp-elf-gdb --batch -n build/<project>.elf -ex 'target remote | python -m esp_idf_panic_decoder --target <chip> panic.txt' -ex bt`.

Escape hatch: esp-idf-monitor 1.10 and newer takes scripted commands on a piped stdin (`reset`, `expect --timeout <s> <regex>`, `exit`) and decodes backtraces on the way. Use it only after `python -m pip show esp-idf-monitor` in the export shell reports 1.10 or newer; an older monitor ignores the pipe and never returns.

### 6. Report

One short paragraph: what was built, whether it was flashed and to which port, and the one boot line that proves the checkpoint. Full logs stay in the terminal.

## Code rules

- FreeRTOS tasks, `esp_log` with a per-file `TAG`, `vTaskDelay(pdMS_TO_TICKS(n))`. No `setup()`/`loop()`, no `Serial.`, no `delay()`, no `Wire.`, no `millis()`.
- Current driver headers only: `driver/i2s_std.h`, `driver/gptimer.h`, `driver/rmt_tx.h`, `driver/i2c_master.h`. The legacy drivers (`driver/i2s.h`, `driver/timer.h`, `driver/rmt.h`, `driver/i2c.h`) are off limits: deprecated in IDF 5 and removed in IDF 6. Legacy I2C compiles without a warning in IDF 5 and only complains at boot, so grep for the include.
- Wi-Fi via `esp_wifi` + `nvs_flash`; networking clients from the registry (`espressif/esp_websocket_client`, `espressif/mdns`) rather than hand-rolled sockets.
- Credentials come from the project's secrets header only, never from a literal in a source file, never from a commit.
- One `.c` per task, a header per module, and nothing crossing modules except queues and event groups.

## macOS notes

- Toolchain prerequisites are Homebrew `cmake ninja dfu-util ccache` and a Python 3 the pinned IDF supports (see `setup-macos.md`); Apple Silicon runs the arm64 toolchains natively, no Rosetta.
- macOS ships drivers for CP210x and CH34x bridges. If no bridge port appears after plugging the UART connector, try another cable or USB port and tell the user; never install a driver yourself.
- `Resource busy` on open means another process holds the port: an old monitor, VS Code's serial view, Arduino IDE. Name the likely culprit; never `kill` anything unasked.
- macOS has no `timeout`; that is why `serial_tail.py` exists. Do not reach for Homebrew's `gtimeout`.
- `export.sh` puts the IDF venv first on `PATH`, so `python` inside that shell is the IDF venv, not Homebrew's. Never `pip install` into it.

## Degradation

- Toolchain missing: quote `check_toolchain.sh`, offer `setup-macos.md`, stop unless the user asks you to install.
- No board: say so, stop. Never "flash later when it appears".
- Build fails in project code: fix it. Build fails inside a managed component: report the first error and the component version; never edit `managed_components/`.
- Registry fetch fails (no network): say so; `dependencies.lock` plus a warm `managed_components/` still builds offline.
- Port busy or esptool cannot connect: one retry after the manual download-mode step, then report.
