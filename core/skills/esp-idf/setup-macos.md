# ESP-IDF on macOS

One toolchain per machine, shared by every project: **pure ESP-IDF**, no Arduino IDE, no PlatformIO. The pinned tag is in `idf-version` next to this file; `scripts/check_toolchain.sh` reports whether the install matches it. Claude Code follows these steps only when asked to install; otherwise they are for you. `${CLAUDE_SKILL_DIR}` below is this skill's directory, the one holding this file. Claude Code fills it in only inside SKILL.md, so in any shell set it first as its own statement, in the same command for a tool call (`CLAUDE_SKILL_DIR=$HOME/projects/agents-config/core/skills/esp-idf; bash "${CLAUDE_SKILL_DIR}/scripts/check_toolchain.sh"`; a `VAR=... cmd` prefix does not work), where every tool's installed copy links, or the path Claude Code showed for this skill.

1. Prerequisites (Apple Silicon and Intel alike, no Rosetta):

   ```bash
   xcode-select --install
   brew install cmake ninja dfu-util ccache
   ```

   Python: ESP-IDF 5.x needs 3.9 or newer, 6.x needs 3.10 or newer. `install.sh` builds its venv from the first `python3` on `PATH`. If it rejects a very new Homebrew Python, put a supported one in front: `brew install python@3.12`, then run `install.sh` as `PATH="$(brew --prefix python@3.12)/bin:$PATH" ./install.sh ...`.

2. Get ESP-IDF at the pinned tag and install the toolchain for the chips you use. Tools land in `~/.espressif/` (large download, done once). `install.sh` takes a comma-separated list of chips, or `all`; a later run with another chip adds it to the list. RISC-V panic decoding needs `riscv32-esp-elf-gdb`, which comes only with a C-, H- or P-series chip in that list.

   ```bash
   mkdir -p ~/esp && cd ~/esp
   git clone -b "$(cat "${CLAUDE_SKILL_DIR}/idf-version")" --recursive https://github.com/espressif/esp-idf.git
   cd ~/esp/esp-idf && ./install.sh esp32,esp32s3
   ```

3. Activate per shell. The export script is sourced, not run, and only in the shell you build in:

   ```bash
   . ~/esp/esp-idf/export.sh
   ```

   Optional alias in `~/.zshrc`: `alias get_idf='. $HOME/esp/esp-idf/export.sh'`. Do not source it from `~/.zshrc` directly: it slows every shell and its venv shadows `python` everywhere.

4. Plug the board into the connector marked **UART** on the devkit, not the one marked USB (the S3-DevKitC-1 and C6-DevKitC-1 have both; the C3 devkits and the classic ESP32 DevKitC have only the bridge). Then:

   ```bash
   ls /dev/cu.* 2>/dev/null | grep -E 'usbserial|SLAB_USBtoUART|wchusbserial|usbmodem'
   ```

   (A multi-glob `ls /dev/cu.usbserial-* ...` fails in zsh as soon as one pattern matches nothing.) One entry per board. On official devkits the suffix is the USB bridge's serial number and stays the same for that board, so record the ports once in the project's `CLAUDE.md`; port names are not secrets, so the committed file is fine:

   ```
   ## Boards
   <board name>: /dev/cu.usbserial-XXXXXXXX
   ```

   macOS ships drivers for CP210x, FTDI and WCH CH340/CH9102 bridges. A CH343 needs none: it is a CDC device and shows up as `/dev/cu.usbmodem<serial>`, like the native USB port (SKILL.md step 1 tells them apart by vendor ID). So nothing appearing usually means a charge-only cable or a bad port. Third-party drivers (Silicon Labs VCP, WCH) are DriverKit extensions enabled under System Settings, and only needed for chips the built-in ones skip.

5. Smoke-test with the stock example, then leave the monitor with `Ctrl+]`:

   ```bash
   cp -r ~/esp/esp-idf/examples/get-started/hello_world ~/esp/hello_world && cd ~/esp/hello_world
   idf.py set-target <chip> && idf.py build
   idf.py -p /dev/cu.usbserial-XXXXXXXX flash monitor
   ```

6. `bash "${CLAUDE_SKILL_DIR}/scripts/check_toolchain.sh"` should now exit 0 and list the board.

7. Editor, optional: clangd with Espressif's esp-clang, in `references/editor-clangd.md`.

Bumping the version later: pick the newest patch of a release line that is still in its service period. The dated chart is <https://dl.espressif.com/dl/esp-idf/support-periods.svg>; the rules behind it are in <https://github.com/espressif/esp-idf/blob/master/SUPPORT_POLICY.md>. Change `idf-version`, then `cd ~/esp/esp-idf && git fetch --tags && git checkout <tag> && git submodule update --init --recursive && ./install.sh <chips>`, and rebuild every project on this machine.

As of 2026-09-23: v5.5 left its service period on 2026-07-21 and gets maintenance fixes until 2028-01-21; the next target is v6.1, in service until 2027-08-25. A major bump (5.x to 6.x) means code changes. Check these:

- esptool 5: the command is `esptool`, not `esptool.py`, and subcommands are kebab-case (`write-flash`).
- esp-idf-monitor 1.10 or newer, so the scripted monitor in SKILL.md step 5 becomes usable. (v5.5's constraints allow 1.10 too; re-running `./install.sh <chips>` on the current tag fetches it.)
- Component manager 3.0 re-solves every `dependencies.lock`; commit the new locks.
- Python 3.10 or newer.
- The legacy I2S, RMT, timer, ADC, PCNT, MCPWM, DAC and sigma-delta drivers are removed (legacy I2C stays, end-of-life, until 7.0), and the `driver` component no longer pulls in `esp_driver_*`: a component that has `driver` in `REQUIRES` must add the `esp_driver_*` components it uses (`~/projects/aquila/firmware/main/CMakeLists.txt` is one).
- Espressif now documents its EIM installer, but `install.sh` and `export.sh` still work, so the steps above stand.
- Check that `esp-sr` builds (`~/projects/athena/firmware/athena_audio`) before committing to the bump.
- Update `clangd.path` for the new esp-clang (`references/editor-clangd.md`).
- Recheck the eFuse grep in SKILL.md step 4. Its keys are the `#if CONFIG_*` guards around eFuse writes in `components/efuse/src/esp_efuse_startup.c`, `esp_security/src/init.c`, `nvs_sec_provider/` and `bootloader_support/`; `grep -rn -i burn ~/esp/esp-idf/components --include='Kconfig*'` finds new ones.
