# clangd for ESP-IDF projects

For VS Code, or any clangd client, on an IDF project. Without this setup clangd flags every file. The cause is the compile database the build writes, `<app>/build/compile_commands.json`: it carries GCC-only `-f*` and `-m*` flags that clangd rejects (`unknown argument: '-mlongcalls'`, `'-fno-shrink-wrap'`), and clangd finds the newlib headers only when `--query-driver` lets it ask the cross compiler (otherwise `'sys/reent.h' file not found`, `'inttypes.h' file not found`). Build the app once so the database exists.

1. **esp-clang.** Use Espressif's clangd, version-matched to the IDF toolchain. Apple's `/usr/bin/clangd` also parses these files once steps 2 and 3 are in place, but esp-clang is the one Espressif supports. It is an `on_request` tool in IDF's registry, about 270 MB to download and 1.7 GB on disk, installed under `~/.espressif/tools/esp-clang/<ver>/esp-clang/bin/`. Installing it changes the machine, so only when the user asks:

   ```bash
   python3 ~/esp/esp-idf/tools/idf_tools.py install esp-clang
   ```

   `<ver>` is the directory name (`ls ~/.espressif/tools/esp-clang`); with IDF v5.5.5 it is `esp-19.1.2_20250312`. It is part of every clangd path below, so update them after an IDF bump that brings a new esp-clang.

2. **`.clangd`** at the workspace root, committed (it is the same on every machine):

   ```yaml
   CompileFlags:
     Remove: [-f*, -m*]
   ```

3. **`.vscode/settings.json`** of the workspace. It is machine-local: gitignore it, and clangd's `.cache/` index with it.

   ```json
   {
     "clangd.path": "${userHome}/.espressif/tools/esp-clang/esp-19.1.2_20250312/esp-clang/bin/clangd",
     "clangd.arguments": [
       "--background-index",
       "--query-driver=${userHome}/.espressif/tools/**",
       "--compile-commands-dir=${workspaceFolder}/build"
     ],
     "C_Cpp.intelliSenseEngine": "disabled"
   }
   ```

   - The clangd extension expands `${userHome}` and `${workspaceFolder}` but not `$HOME` or `~`, and it starts clangd without a shell, so a literal `$HOME` in `--query-driver` silently breaks header lookup. Write `${userHome}` or an absolute path.
   - `--compile-commands-dir` fits a workspace that is one app. In a repo with several apps (`firmware/<app>/`, each with its own `build/`), leave it out: clangd walks up from each open file and finds that app's `build/compile_commands.json` itself.
   - `C_Cpp.intelliSenseEngine: disabled` stops Microsoft's C/C++ extension from painting a second set of errors.
   - Espressif's ESP-IDF extension (not the clangd extension) has a command, `ESP-IDF: Configure project for ESP-Clang`, that writes the same `.clangd` plus `clangd.path` and `clangd.arguments`, but with the broad `--query-driver=**`. The narrower glob and the `C_Cpp.intelliSenseEngine` line are manual additions.

   Reload the window.

4. **Check without the editor**, from the workspace root. Use the full esp-clang path (outside the export shell a bare `clangd` is Apple's) and the same arguments, leaving out `--compile-commands-dir` in a multi-app repo as above:

   ```bash
   ~/.espressif/tools/esp-clang/<ver>/esp-clang/bin/clangd --query-driver="$HOME/.espressif/tools/**" --compile-commands-dir=<app>/build --check=<app>/main/main.c
   ```

   It should end with `All checks completed, 0 errors`.
