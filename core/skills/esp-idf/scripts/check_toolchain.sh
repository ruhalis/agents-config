#!/usr/bin/env bash
# Read-only status of the ESP-IDF toolchain on this Mac. Never installs anything.
# Exit 0: ready to build. Exit 1: ESP-IDF not installed, tools missing, or export.sh fails.
# A checkout tag that differs from the pin is reported as a WARNING, not a failure.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "${SKILL_DIR}/idf-version" 2>/dev/null || echo unknown)"
IDF_DIR="${IDF_PATH:-${HOME}/esp/esp-idf}"
TOOLS_DIR="${IDF_TOOLS_PATH:-${HOME}/.espressif}"
status=0

echo "pinned tag:  ${PIN}"

if [[ -f "${IDF_DIR}/export.sh" ]]; then
  have="$(git -C "${IDF_DIR}" describe --tags --exact-match 2>/dev/null \
    || git -C "${IDF_DIR}" describe --tags --always 2>/dev/null || echo unknown)"
  if [[ "${have}" == "${PIN}" ]]; then
    echo "esp-idf:     ${have} at ${IDF_DIR}"
  else
    echo "esp-idf:     ${have} at ${IDF_DIR} — WARNING: differs from pin ${PIN} (bump step in setup-macos.md)"
  fi
else
  echo "esp-idf:     NOT INSTALLED at ${IDF_DIR} — see ${SKILL_DIR}/setup-macos.md"
  status=1
fi

# Cross toolchains: xtensa-esp-elf covers ESP32/S2/S3, riscv32-esp-elf covers C2/C3/C5/C6/H2/P4.
# Either one is enough to build for its chips; install.sh only fetches the ones you asked for.
chains=""
for tc in xtensa-esp-elf riscv32-esp-elf; do
  if ls -d "${TOOLS_DIR}/tools/${tc}"/*/ >/dev/null 2>&1; then
    chains="${chains}${chains:+ }${tc}"
  fi
done
if [[ -n "${chains}" ]]; then
  echo "toolchains:  ${chains} (${TOOLS_DIR}/tools)"
else
  echo "toolchains:  MISSING — cd ${IDF_DIR} && ./install.sh <target,...>   (e.g. esp32s3,esp32c6 or all)"
  status=1
fi

if ls -d "${TOOLS_DIR}/python_env"/*/ >/dev/null 2>&1; then
  echo "python env:  $(ls "${TOOLS_DIR}/python_env" | tr '\n' ' ')"
else
  echo "python env:  MISSING — same install.sh"
  status=1
fi

# The authoritative test: source export.sh, then ask idf.py for its version. When a
# tool or the venv is missing, activation reports it on stderr but export.sh may still
# return 0, so idf.py itself is the check. Capture both streams and show only the last
# line on success (the version) or the tail on failure (the reason).
if [[ ${status} -eq 0 ]]; then
  if out="$(bash -c ". '${IDF_DIR}/export.sh' >/dev/null && idf.py --version" 2>&1)"; then
    echo "idf.py:      $(printf '%s\n' "${out}" | tail -n 1)"
  else
    echo "idf.py:      export.sh FAILED:"
    printf '%s\n' "${out}" | tail -n 5 | sed 's/^/             /'
    status=1
  fi
fi

# UART bridge ports first (CP210x, CH34x), then native USB-Serial-JTAG. macOS: cu.*, never tty.*
ports="$(ls /dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbmodem* 2>/dev/null | tr '\n' ' ')"
echo "boards:      ${ports:-none on USB (use the UART connector)}"

exit "${status}"
