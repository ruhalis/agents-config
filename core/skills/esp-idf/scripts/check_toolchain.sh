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

# Serial ports on USB, each labelled by the USB vendor ID of the device it hangs off in the
# IORegistry (read-only), because the name alone cannot tell a CH343 bridge (usbmodem*) from
# Espressif's native USB-Serial-JTAG. A port is listed if its name looks like a board
# (usbserial, SLAB_USBtoUART, wchusbserial, usbmodem) or ioreg puts it under a USB device;
# Bluetooth and debug-console ports are neither. macOS: cu.*, never tty.*
IFS= read -r -d '' PORTS_PY <<'EOF' || true   # read -d '' returns 1 at the end of the heredoc
import plistlib, re, sys
KNOWN = {0x10C4: "CP210x bridge", 0x1A86: "WCH bridge", 0x0403: "FTDI bridge"}
try:
    roots = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    roots = []
usb = {}
def walk(node, dev):
    if not isinstance(node, dict):
        return
    if isinstance(node.get("idVendor"), int):
        dev = node
    cu = node.get("IOCalloutDevice")
    if isinstance(cu, str) and dev is not None:
        usb.setdefault(cu, dev)
    for child in node.get("IORegistryEntryChildren") or []:
        walk(child, dev)
for root in roots if isinstance(roots, list) else [roots]:
    walk(root, None)
named = re.compile(r"/dev/cu\.(usbserial|SLAB_USBtoUART|wchusbserial|usbmodem)")
for port in sorted({p for p in sys.argv[1:] if named.match(p)} | set(usb)):
    dev = usb.get(port)
    if dev is None:
        print(f"{port}  unknown (no USB device for it in ioreg)")
        continue
    vid, pid = dev["idVendor"], dev.get("idProduct")
    pid = pid if isinstance(pid, int) else 0
    name = dev.get("USB Product Name") or dev.get("kUSBProductString") or dev.get("IORegistryEntryName") or "?"
    if vid == 0x303A:
        label = "native USB-Serial-JTAG" if pid == 0x1001 else "Espressif native USB"
    else:
        label = KNOWN.get(vid, "unknown")
    print(f'{port}  {label}  {vid:04x}:{pid:04x}  "{name}"')
EOF
shopt -s nullglob
cu_ports=(/dev/cu.*)
shopt -u nullglob
if boards="$(ioreg -a -r -c IOUSBHostDevice -l 2>/dev/null \
    | python3 -c "${PORTS_PY}" ${cu_ports[@]+"${cu_ports[@]}"} 2>/dev/null)"; then
  :
else
  # No python3 or no ioreg: fall back to the names alone.
  boards="$(printf '%s\n' ${cu_ports[@]+"${cu_ports[@]}"} \
    | grep -E '^/dev/cu\.(usbserial|SLAB_USBtoUART|wchusbserial|usbmodem)' \
    | sed 's/$/  (type unknown: ioreg lookup failed)/')"
fi
if [[ -n "${boards}" ]]; then
  printf '%s\n' "${boards}" | sed '1s/^/boards:      /; 2,$s/^/             /'
else
  echo "boards:      none on USB (use the UART connector)"
fi

exit "${status}"
