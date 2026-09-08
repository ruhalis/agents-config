# ESP-IDF on macOS

One toolchain per machine, shared by every project: **pure ESP-IDF**, no Arduino IDE, no PlatformIO. The pinned tag is in `idf-version` next to this file; `scripts/check_toolchain.sh` reports whether the install matches it. Claude Code follows these steps only when asked to install; otherwise they are for you.

1. Prerequisites (Apple Silicon and Intel alike, no Rosetta):

   ```bash
   xcode-select --install
   brew install cmake ninja dfu-util ccache
   ```

   Python: ESP-IDF 5.x needs 3.9 or newer, 6.x needs 3.10 or newer. `install.sh` builds its venv from the first `python3` on `PATH`. If it rejects a very new Homebrew Python, put a supported one in front: `brew install python@3.12`, then run `install.sh` as `PATH="$(brew --prefix python@3.12)/bin:$PATH" ./install.sh ...`.

2. Get ESP-IDF at the pinned tag and install the toolchain for the chips you use. Tools land in `~/.espressif/` (large download, done once). `install.sh` takes a comma-separated list of chips, or `all`.

   ```bash
   mkdir -p ~/esp && cd ~/esp
   git clone -b "$(cat ~/.claude/skills/esp-idf/idf-version)" --recursive https://github.com/espressif/esp-idf.git
   cd ~/esp/esp-idf && ./install.sh esp32s3,esp32c6
   ```

3. Activate per shell. The export script is sourced, not run, and only in the shell you build in:

   ```bash
   . ~/esp/esp-idf/export.sh
   ```

   Optional alias in `~/.zshrc`: `alias get_idf='. $HOME/esp/esp-idf/export.sh'`. Do not source it from `~/.zshrc` directly: it slows every shell and its venv shadows `python` everywhere.

4. Plug the board into the connector marked **UART** on the devkit, not the one marked USB (the S3 and C6 DevKitC boards have both; the C3 devkits and the classic ESP32 DevKitC have only the bridge). Then:

   ```bash
   ls /dev/cu.usbserial-* /dev/cu.SLAB_USBtoUART* /dev/cu.wchusbserial* /dev/cu.usbmodem*
   ```

   One entry per board. On official devkits the suffix is the USB bridge's serial number and stays the same for that board, so record the ports once in the project's `CLAUDE.local.md` (Claude Code loads it every session; add it to the project's `.gitignore` yourself):

   ```
   ## Boards
   <board name>: /dev/cu.usbserial-XXXXXXXX
   ```

   macOS ships drivers for CP210x and CH34x bridges, so nothing appearing usually means a charge-only cable or a bad port. Third-party drivers (Silicon Labs VCP, WCH) are DriverKit extensions enabled under System Settings, and only needed for chips the built-in ones skip.

5. Smoke-test with the stock example, then leave the monitor with `Ctrl+]`:

   ```bash
   cp -r ~/esp/esp-idf/examples/get-started/hello_world ~/esp/hello_world && cd ~/esp/hello_world
   idf.py set-target <chip> && idf.py build
   idf.py -p /dev/cu.usbserial-XXXXXXXX flash monitor
   ```

6. `bash ~/.claude/skills/esp-idf/scripts/check_toolchain.sh` should now exit 0 and list the board.

7. Editor, optional. VS Code's clangd extension needs Espressif's esp-clang for IDF projects: the stock clangd has no Xtensa target and rejects the GCC-only flags in the compile database, so it reports missing `freertos/*.h` and `sys/reent.h` on every file. esp-clang is an `on_request` tool in IDF's registry (about 270 MB, lands in `~/.espressif/tools/esp-clang/<version>/esp-clang/bin/`):

   ```bash
   python3 ~/esp/esp-idf/tools/idf_tools.py install esp-clang
   ```

   Then per project, what the extension's `ESP-IDF: Configure project for ESP-Clang` command writes: a `.clangd` at the workspace root with `CompileFlags: {Remove: [-f*, -m*]}`, and in the workspace `.vscode/settings.json` (machine-local, gitignore it) `clangd.path` pointing at that `clangd` binary, `clangd.arguments` of `--background-index`, `--query-driver=$HOME/.espressif/tools/**` and `--compile-commands-dir=<project>/build`, plus `C_Cpp.intelliSenseEngine` set to `disabled` so cpptools stops painting a second set of errors. Reload the window. Check without the editor: `clangd --check=main/main.c` with the same arguments, run from the workspace root, should end with `All checks completed, 0 errors`.

Bumping the version later: pick the tag after checking which release line Espressif has in service (<https://github.com/espressif/esp-idf/blob/master/SUPPORT_POLICY.md>), change `idf-version`, then `cd ~/esp/esp-idf && git fetch --tags && git checkout <tag> && git submodule update --init --recursive && ./install.sh <chips>`, and rebuild every project on this machine. A major bump (5.x to 6.x) also removes the legacy peripheral drivers and raises the Python floor, so expect code changes.
