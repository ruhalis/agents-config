#!/usr/bin/env bash
# Read-only status of the ESP-IDF toolchain on this Mac. Never installs anything.
# Exit 0: ready to build. Exit 1: ESP-IDF not installed, tools missing, export.sh fails,
# or the skill's idf-version pin file is missing.
# A checkout tag that differs from the pin is reported as a WARNING, not a failure.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${SKILL_DIR}/idf-version"
IDF_DIR="${IDF_PATH:-${HOME}/esp/esp-idf}"
TOOLS_DIR="${IDF_TOOLS_PATH:-${HOME}/.espressif}"
status=0
tools_ok=1

PIN=""
if [[ -r "${PIN_FILE}" ]]; then
  PIN="$(tr -d '[:space:]' < "${PIN_FILE}")"
fi
if [[ -n "${PIN}" ]]; then
  echo "pinned tag:  ${PIN}"
else
  echo "pinned tag:  MISSING — pin file ${PIN_FILE} not found or empty"
  status=1
fi

if [[ -f "${IDF_DIR}/export.sh" ]]; then
  have="$(git -C "${IDF_DIR}" describe --tags --exact-match 2>/dev/null \
    || git -C "${IDF_DIR}" describe --tags --always 2>/dev/null || echo unknown)"
  if [[ -z "${PIN}" || "${have}" == "${PIN}" ]]; then
    echo "esp-idf:     ${have} at ${IDF_DIR}"
  else
    echo "esp-idf:     ${have} at ${IDF_DIR} — WARNING: differs from pin ${PIN} (bump step in setup-macos.md)"
  fi
else
  echo "esp-idf:     NOT INSTALLED at ${IDF_DIR} — see ${SKILL_DIR}/setup-macos.md"
  tools_ok=0
fi

# The chips install.sh was run for, from idf-env.json (install.sh adds to this list).
env_json="${TOOLS_DIR}/idf-env.json"
targets=""
if [[ -r "${env_json}" ]]; then
  targets="$(python3 - "${env_json}" "${IDF_DIR}" 2>/dev/null <<'EOF'
import json, os, sys
records = json.load(open(sys.argv[1])).get("idfInstalled", {}).values()
want = os.path.realpath(sys.argv[2])
for rec in records:
    if os.path.realpath(rec.get("path", "")) == want:
        print(" ".join(sorted(rec.get("targets", []))))
        break
EOF
)"
fi
echo "targets:     ${targets:-unknown (no record for ${IDF_DIR} in ${env_json})}"

# Cross toolchains: xtensa-esp-elf covers ESP32/S2/S3; riscv32-esp-elf covers C2/C3/C5/C6/H2/P4
# but is also installed for the S2/S3 ULP, so its presence does not mean a RISC-V chip was
# installed: the targets line says which were. install.sh only fetches what you asked for.
chains=""
for tc in xtensa-esp-elf riscv32-esp-elf; do
  if ls -d "${TOOLS_DIR}/tools/${tc}"/*/ >/dev/null 2>&1; then
    chains="${chains}${chains:+ }${tc}"
  fi
done
if [[ -n "${chains}" ]]; then
  echo "toolchains:  ${chains} (${TOOLS_DIR}/tools)"
else
  echo "toolchains:  MISSING — cd ${IDF_DIR} && ./install.sh <target,...>   (e.g. esp32,esp32s3 or all)"
  tools_ok=0
fi

# Debuggers, needed for panic decoding. riscv32-esp-elf-gdb comes only with a C/H/P-series target.
gdbs=""
for g in xtensa-esp-elf-gdb riscv32-esp-elf-gdb; do
  if ls -d "${TOOLS_DIR}/tools/${g}"/*/ >/dev/null 2>&1; then
    gdbs="${gdbs}${gdbs:+, }${g}"
  else
    gdbs="${gdbs}${gdbs:+, }${g} missing"
    [[ ${g} == riscv32-* ]] && gdbs="${gdbs} (comes with ./install.sh <C/H/P-series chip>)"
  fi
done
echo "gdb:         ${gdbs}"

if ls -d "${TOOLS_DIR}/python_env"/*/ >/dev/null 2>&1; then
  echo "python env:  $(ls "${TOOLS_DIR}/python_env" | tr '\n' ' ')"
else
  echo "python env:  MISSING — same install.sh"
  tools_ok=0
fi

# The authoritative test: source export.sh, then ask idf.py for its version. When a
# tool or the venv is missing, activation reports it on stderr but export.sh may still
# return 0, so idf.py itself is the check. Capture both streams and show only the last
# line on success (the version) or the tail on failure (the reason).
if [[ ${tools_ok} -eq 1 ]]; then
  if out="$(bash -c ". '${IDF_DIR}/export.sh' >/dev/null && idf.py --version" 2>&1)"; then
    echo "idf.py:      $(printf '%s\n' "${out}" | tail -n 1)"
  else
    echo "idf.py:      export.sh FAILED:"
    printf '%s\n' "${out}" | tail -n 5 | sed 's/^/             /'
    tools_ok=0
  fi
fi
[[ ${tools_ok} -eq 1 ]] || status=1

# Bridge names first (CP210x, FTDI, WCH), then usbmodem: Espressif's native USB-Serial-JTAG
# or a CDC-class bridge such as the CH343 (SKILL.md step 1 tells them apart). macOS: cu.*, never tty.*
ports="$(ls /dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbmodem* 2>/dev/null | tr '\n' ' ')"
echo "boards:      ${ports:-none on USB (use the UART connector)}"

exit "${status}"
