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
| `references/editor-clangd.md` | Read when the user mentions clangd, VS Code, IntelliSense or editor errors in an IDF project. |
| `scripts/check_toolchain.sh` | Run. Read-only: is IDF installed, does it match the pin, which chips and debuggers are installed, does `export.sh` work, which boards are on USB. |
| `scripts/serial_tail.py` | Run. Bounded serial reader that replaces `idf.py monitor` in tool calls. |

Running outside Claude Code. The installed copy for Claude Code, Codex and Cursor is a symlink to `~/projects/agents-config/core/skills/esp-idf`. In Cowork, the cloud copy of this skill is for reading `idf-version`, `setup-macos.md` and the scripts' source: `check_toolchain.sh`, `idf.py` and `serial_tail.py` need the Mac's toolchain and serial ports, and the sandboxed shell mounts only connected folders, with no `~/esp` and no `/dev/cu.*`. Run them in a real macOS shell (Desktop Commander's `start_process`) with `CLAUDE_SKILL_DIR=$HOME/projects/agents-config/core/skills/esp-idf;` set first as its own statement (a `VAR=... cmd` prefix does not expand `${CLAUDE_SKILL_DIR}` in cmd), so the commands below work unchanged. If no macOS shell is available, hand the user the exact command.

## Fixed decisions

- **Pure ESP-IDF.** No Arduino IDE, no Arduino core, no PlatformIO, no pioarduino. C by default; C++ only where a library forces it, kept behind one wrapper that exposes `extern "C"` functions. If a project needs an Arduino-only library, bring it in as an IDF component; never switch the build system.
- **One toolchain per machine.** Checkout at `~/esp/esp-idf` at the tag in `idf-version`, tools in `~/.espressif/`. Every project on this Mac builds against it. Bumping is a deliberate change: edit `idf-version`, follow the bump step in `setup-macos.md`, rebuild every project that uses it. Never bump to fix one build error.
- **The chip comes from the project.** Set it with `set-target` (step 2) to whatever the repo's docs or existing `sdkconfig.defaults` say. If nothing says, ask; never default silently.
- **Installing or changing the toolchain changes the machine** (Homebrew packages, a large download, a Python venv). Do it only when the user asks for it in that message, following `setup-macos.md` step by step. Otherwise report what `check_toolchain.sh` says and point at that file.
- **eFuses are one-way.** Never run `idf.py efuse-*` or an `espefuse` burn, protect or set-flash-voltage command, and never put `CONFIG_SECURE_BOOT*`, `CONFIG_SECURE_FLASH_ENC*`, another key from the step-4 check, or any key whose Kconfig help says it burns or sets an eFuse, into `sdkconfig.defaults`, unless the user has answered yes to an explicit "this permanently burns eFuses on <board>, proceed?". A flash request does not cover a build that burns eFuses on boot.

## What an IDF project looks like

`CMakeLists.txt` at the project root, `main/` with its own `CMakeLists.txt`, `main/idf_component.yml` for registry dependencies, `sdkconfig.defaults`, and `partitions.csv` when the table is custom. A `components/` directory at the project root is found automatically; `EXTRA_COMPONENT_DIRS` is only for shared component directories outside the project, such as a `../components` that several apps use.

| Committed | Generated, never committed |
|---|---|
| `sdkconfig.defaults`, `partitions.csv`, `dependencies.lock`, `*.h.example` | `sdkconfig`, `sdkconfig.old`, `build/`, `managed_components/`, `.cache/` (clangd index), the real secrets header |

Before the first commit in a new project, make sure its `.gitignore` covers the right column; add the lines if it does not. Registry dependencies go through the component manager, never copied sources: `idf.py -C "<dir>" add-dependency "<name>"` (`<dir>` is the project's absolute path, step 0), then commit the changed `idf_component.yml` and `dependencies.lock`. One exception: a manifest with Kconfig-conditional `rules:` dependencies makes the lock file machine-specific, so leave it out then. Credentials live in a gitignored header with a committed `.example` next to it, named by the project.

## Procedure

### 0. Environment, every command

Neither environment variables nor the working directory can be relied on between Bash calls (a subagent's or another tool's shell starts each call afresh). So every call that runs `idf.py` or the bundled Python script starts by sourcing the export script, and every `idf.py` names the project as `-C "<dir>"`, its absolute path. `-C` also ties a flash to the project whose board you resolved, never to whatever app the shell happens to sit in. Silence the export script: it prints status on both stdout and stderr. If activation fails, `idf.py` is simply not on `PATH` and the call ends with `command not found`; run `check_toolchain.sh` then, it shows why.

```bash
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && idf.py -C "<dir>" build
```

Never run from a foreground tool call, alone or chained: `idf.py menuconfig | monitor | gdb | gdbtui | gdbgui | openocd | confserver`. They wait on a terminal or run until killed. Step 2 replaces `menuconfig`; step 5 replaces `monitor` and has the one scripted exception.

Once per session, before the first `idf.py`:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check_toolchain.sh"
```

Exit 0: go. Exit 1: not installed, tools missing, `export.sh` fails, or the `idf-version` pin file is missing: stop, quote its output, and offer `setup-macos.md` for a toolchain problem. A tag that differs from the pin is a warning it prints, not a stop; never switch the checkout yourself. Its `targets:` line lists the chips `install.sh` was run for, and its `gdb:` line the debuggers present (step 5).

### 1. Find the board

Only for flash and monitor; skip it for build, configure, size and fixes.

Ports on macOS are `/dev/cu.*`, never `/dev/tty.*` (that one blocks on open). The S3-DevKitC-1 (Micro-USB on the official board, USB-C on clones) and the C6-DevKitC-1 (USB-C) have two connectors: **UART**, through a USB-to-UART bridge chip, and **USB**, the chip's native USB-Serial-JTAG. The C3 devkits and the classic ESP32 DevKitC have one connector, which is the bridge. Prefer the UART one: a bridge with a programmed serial number keeps its name wherever it is plugged in, and it survives a crashing firmware. The native port is named after the physical USB port it sits in, re-enumerates on every reset, and vanishes if the firmware reconfigures USB or sleeps.

The device name does not reliably tell the two apart. CP210x and FTDI bridges show as `/dev/cu.usbserial-<serial>` (CP210x as `/dev/cu.SLAB_USBtoUART` under Silicon Labs' driver), WCH CH340 and CH9102 as `usbserial-*` or `wchusbserial*`, but a CDC-class bridge such as WCH's CH343 appears as `/dev/cu.usbmodem<serial>`, the same shape as the native port. Identify by vendor ID:

```bash
ioreg -p IOUSB -l -w0 | grep -E '"(USB Product Name|idVendor|idProduct|USB Serial Number)"'
```

ioreg prints decimal IDs: 12346 (0x303a) is the native USB-Serial-JTAG, 4292 (0x10c4) CP210x, 6790 (0x1a86) WCH, 1027 (0x0403) FTDI.

Resolve the port in this order:

1. A `## Boards` section in `CLAUDE.md`, `CLAUDE.local.md` or `AGENTS.md`, in the project directory or the repo root. Not every tool loads these files, so read them:

   ```bash
   for d in "<dir>" "$(git -C "<dir>" rev-parse --show-toplevel 2>/dev/null)"; do grep -hA12 '^## Boards' "$d"/{CLAUDE.md,CLAUDE.local.md,AGENTS.md} 2>/dev/null; done | awk '!s[$0]++'
   ```

   The `awk` drops the second copy when `<dir>` is the repo root. No output means no section.

   One line per board:

   ```
   ## Boards
   <board name>: /dev/cu.usbserial-XXXXXXXX
   ```

   Confirm a recorded port with `ls <port>` before using it. If it is missing and the listing in 3 shows a port recorded nowhere, show both and ask whether it is that board; after a yes, offer to update its line. A native-USB name changes whenever the board moves to another Mac USB port.

2. A port the user named in this message.
3. The ports on USB. This form works in zsh and bash alike (a multi-glob `ls` aborts on the first unmatched pattern under zsh); the `boards:` line of `check_toolchain.sh` gives the same list.

   ```bash
   ls /dev/cu.* 2>/dev/null | grep -E 'usbserial|SLAB_USBtoUART|wchusbserial|usbmodem' || true
   ```

   Exactly one: use it and offer to record it under `## Boards` in whichever of those files already has the section, else in the project's committed `CLAUDE.md` (port names are not secrets). Zero: say no board is on USB, remind them of the UART connector, and stop. More than one: list them and ask which. Never guess, never loop over ports.

A `usbserial-0001` suffix is a generic serial shared by many cheap bridges, so two such boards cannot be told apart by name; say so and ask the user to plug in one at a time.

### 2. Configure

- `idf.py -C "<dir>" set-target <chip>` once per fresh checkout. It clears `build/` and generates `sdkconfig` from `sdkconfig.defaults`.
- No `menuconfig` (step 0): edit `sdkconfig.defaults`, then regenerate. While `build/` exists: `rm -f "<dir>/sdkconfig" && idf.py -C "<dir>" reconfigure`. Without `build/`, `reconfigure` silently falls back to target `esp32`, so run `idf.py -C "<dir>" set-target <chip>` instead. After either, confirm the chip with `grep '^CONFIG_IDF_TARGET=' "<dir>/sdkconfig"`. A single-target project can pin it with `CONFIG_IDF_TARGET="<chip>"` in `sdkconfig.defaults`.
- A misspelled key is not an error. The configure step only prints `warning: unknown kconfig symbol` and carries on, so grep its output for that line, then confirm the keys that matter landed with a `grep` on the generated `sdkconfig`.
- Take Kconfig keys from the project's docs, an Espressif example's `sdkconfig.defaults`, or the IDF Kconfig files for that chip. Never invent keys.

### 3. Build

```bash
idf.py -C "<dir>" build
```

Read errors from the **first** `error:` line, not the last; the tail is CMake noise. Fix code in the project; never patch `~/esp/esp-idf` or `managed_components/`. If an upstream component needs a change, copy it into the project's `components/` under the same name to override it (project components win over IDF and managed ones), and note the override in the project docs. Never silence a warning with `-Wno-*` or `-fpermissive`. Use `idf.py -C "<dir>" size` when flash or RAM is in question.

### 4. Flash, an authorization boundary

Building is free. **Flashing is not.** Flash only when the user asked for it in this message ("flash it", "upload", "put it on the board") and only to a port resolved in step 1. A request to build, fix, or debug does not include flashing. Never flash while a monitor holds the port.

First check the build for eFuse burns on boot (Fixed decisions). The pattern holds every `sdkconfig` key that makes IDF v5.5 burn an eFuse at boot or on update: secure boot, signed apps, flash and NVS encryption, app anti-rollback, the ROM console and ROM log, the ECC and ECDSA modes. It does not see project code that calls the `esp_efuse_write*` API. It must print nothing unless the user has confirmed the burn:

```bash
grep -E '^CONFIG_(SECURE_(BOOT|SIGNED_APPS_NO_SECURE_BOOT|FLASH_ENC_ENABLED)|NVS_ENCRYPTION|BOOTLOADER_APP_ANTI_ROLLBACK|ESP32_DISABLE_BASIC_ROM_CONSOLE|BOOT_ROM_LOG_(ALWAYS_OFF|ON_GPIO_(LOW|HIGH))|ESP_CRYPTO_FORCE_ECC_CONSTANT_TIME_POINT_MUL|ESP_ECDSA_ENABLE_P192_CURVE)=y' "<dir>/sdkconfig"
```

```bash
idf.py -C "<dir>" -p "<port>" flash
```

`idf.py -C "<dir>" -p "<port>" erase-flash` wipes NVS, the partition table, and any data partitions (models, filesystems, calibration). Run it only after the user has answered an explicit "erase the flash on <board>?" with yes in this conversation. Never chain it "to be safe".

If esptool cannot connect: report it, suggest holding **BOOT**, tapping **RESET**, releasing **BOOT** to force download mode, then retry once. Never retry in a loop.

### 5. Watch the board

For the user at their own terminal: `idf.py -C "<dir>" -p "<port>" monitor`, exit with `Ctrl+]`. **Never run it from a tool call**, alone or chained (`idf.py flash monitor`): esp-idf-monitor 1.9 or older exits at once with a TTY error (after `flash` has already flashed), and 1.10 or newer on empty stdin watches until killed.

From a tool call run the bounded reader. It needs the IDF venv's pyserial, so it takes the same export prefix, and `python` there is the venv's. Match the console baud first: `grep -E '^CONFIG_ESPTOOLPY_MONITOR_BAUD=' "<dir>/sdkconfig"`; if it is not 115200, pass `--baud <value>`.

```bash
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && python "${CLAUDE_SKILL_DIR}/scripts/serial_tail.py" "<port>" --seconds 20 --reset
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && python "${CLAUDE_SKILL_DIR}/scripts/serial_tail.py" "<port>" --seconds 30 --reset --until 'Found 8MB PSRAM'
. "$HOME/esp/esp-idf/export.sh" >/dev/null 2>&1 && python "${CLAUDE_SKILL_DIR}/scripts/serial_tail.py" "<port>" --seconds 20 --reset --baud 921600
```

`--reset` pulses the board so the boot log is captured from its first line. On a native USB-Serial-JTAG port (vendor 0x303a, step 1) omit it: a reset makes that port re-enumerate, and the read ends in a port error. You then get runtime output, not the boot log; for the boot log, use the UART connector. `--until <regex>` stops on the first matching line; use it for boot checkpoints (PSRAM size, IP address, a "ready" line). `--seconds` is capped at 60 and `--max-lines` (default 400) stops a chatty firmware from flooding the call. Exit codes: 0 done or `--until` matched, 1 port error (cannot open, or lost mid-read), 2 deadline passed without an `--until` match, 3 usage or environment error (bad arguments or regex, no pyserial), 4 `--max-lines` reached before an `--until` match. Quote at most 30 lines of log back to the user: the panic or the checkpoint, not the whole boot.

Backtraces come out raw; decode them with the chip's toolchain from the export shell:

- Xtensa (ESP32, S2, S3): `xtensa-esp-elf-addr2line -pfiaC -e "<dir>/build/<project>.elf" <addr> ...` on the `Backtrace:` addresses.
- RISC-V (C-, H-, P-series): the panic prints registers and a stack dump, no backtrace. Save the panic text to `<dir>/build/panic.txt` and check `command -v riscv32-esp-elf-gdb`. If it is there, run `riscv32-esp-elf-gdb --batch -n "<dir>/build/<project>.elf" -ex 'target remote | python -m esp_idf_panic_decoder "<dir>/build/panic.txt"' -ex bt`. If not (it comes only with a C-, H- or P-series chip in `install.sh`; see the `gdb:` line of `check_toolchain.sh`), say so, decode `MEPC` and `RA` from the register dump with `riscv32-esp-elf-addr2line -pfiaC -e "<dir>/build/<project>.elf" <MEPC> <RA>`, and tell the user that `./install.sh <chip>` adds the gdb; that is a toolchain change, so only when they ask.

Escape hatch: esp-idf-monitor 1.10 and newer takes scripted commands on a piped stdin (`reset`, `expect --timeout <s> <regex>`, `exit`) and decodes backtraces on the way. Use it only after `python -m pip show esp-idf-monitor` in the export shell reports 1.10 or newer (1.9 and older exit with the TTY error above), and end the piped script in `exit` or an `expect --timeout`: on empty stdin 1.10 watches until killed.

### 6. Report

One short paragraph: what was built, whether it was flashed and to which port, and the one boot line that proves the checkpoint. Full logs stay in the terminal.

## Code rules

- FreeRTOS tasks, `esp_log` with a per-file `TAG`, `vTaskDelay(pdMS_TO_TICKS(n))`. No `setup()`/`loop()`, no `Serial.`, no `delay()`, no `Wire.`, no `millis()`.
- Current driver headers only: `driver/i2s_std.h`, `driver/gptimer.h`, `driver/rmt_tx.h`, `driver/i2c_master.h`. Legacy `driver/{i2s,timer,rmt,adc,pcnt,mcpwm,dac,sigmadelta}.h` are deprecated in IDF 5 and removed in 6.0; legacy `driver/i2c.h` is end-of-life in 6.x (a compile-time message) and goes in 7.0. All are off limits. Legacy I2C compiles without a warning in IDF 5 and only complains at boot, so grep for the include.
- Wi-Fi via `esp_wifi` + `nvs_flash`; networking clients from the registry (`espressif/esp_websocket_client`, `espressif/mdns`) rather than hand-rolled sockets.
- Credentials come from the project's secrets header only, never from a literal in a source file, never from a commit.
- One `.c` per task, a header per module, and nothing crossing modules except queues and event groups.

## macOS notes

- Toolchain prerequisites are Homebrew `cmake ninja dfu-util ccache` and a Python 3 the pinned IDF supports (see `setup-macos.md`); Apple Silicon runs the arm64 toolchains natively, no Rosetta.
- macOS ships drivers for CP210x, FTDI and WCH CH340/CH9102 bridges, and a CH343 runs on the built-in CDC driver (as `usbmodem`, step 1). If no bridge port appears after plugging the UART connector, try another cable or USB port and tell the user; never install a driver yourself.
- `Resource busy` on open means another process holds the port: an old monitor, VS Code's serial view, Arduino IDE. Name the likely culprit; never `kill` anything unasked.
- macOS has no `timeout`; that is why `serial_tail.py` exists. Do not reach for Homebrew's `gtimeout`.
- `export.sh` puts the IDF venv first on `PATH`, so `python` inside that shell is the IDF venv, not Homebrew's. Never `pip install` into it.

## Degradation

- Toolchain missing: quote `check_toolchain.sh`, offer `setup-macos.md`, stop unless the user asks you to install.
- No board (flash or monitor request): say so, stop. Never "flash later when it appears".
- Build fails in project code: fix it. Build fails inside a managed component: report the first error and the component version; never edit `managed_components/`.
- Registry fetch fails (no network): say so; `dependencies.lock` plus a warm `managed_components/` still builds offline.
- Port busy or esptool cannot connect: one retry after the manual download-mode step, then report.
- `serial_tail.py` exits 1 right after `--reset` on a native USB port: rerun once without `--reset`.
