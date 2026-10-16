#!/usr/bin/env bash
# Board geometry for enclosure CAD, through kicad-cli only. Never touches the KiCad project.
#
#   board_export.sh [--filter 'J*,SW*,U*'] <file.kicad_pcb|file.kicad_pro> [outdir]
#
# Writes  <outdir>/board.step       board outline + holes, no components
#         <outdir>/connectors.step  component 3D models matching the filter, no board body
#         <outdir>/positions.csv    placement of every footprint, both sides, mm
#         <outdir>/outline.dxf      Edge.Cuts only, mm
#         <outdir>/README.txt       kicad-cli version, git revision, datum note, filter
# All four share the board's drill/aux origin as datum. Default outdir: cad/board/ next to the pcb file.
# Flags checked against kicad-cli 10.0.5 --help: pcb export step --board-only --no-board-body --component-filter
# --drill-origin; pcb export pos --use-drill-file-origin (not --use-drill-origin); pcb export dxf --use-drill-origin
# --output-units --mode-single (needed so -o is a file path, not a directory).
# Exit 1 on any kicad-cli failure or misuse.
set -euo pipefail

APP="${KICAD_APP:-/Applications/KiCad/KiCad.app}"
CLI="${APP}/Contents/MacOS/kicad-cli"
filter="J*,SW*"

if [[ "${1:-}" == "--filter" ]]; then
  [[ -n "${2:-}" ]] || { echo "--filter needs a value" >&2; exit 1; }
  filter="$2"; shift 2
fi
in="${1:-}"; out="${2:-}"
[[ -f "${in}" ]] || { echo "usage: $(basename "$0") [--filter 'J*,SW*,U*'] <file.kicad_pcb|file.kicad_pro> [outdir]" >&2; exit 1; }
[[ -x "${CLI}" ]] || { echo "kicad-cli not found at ${CLI}; run check_kicad.sh" >&2; exit 1; }

case "${in}" in
  *.kicad_pro) pcb="${in%.kicad_pro}.kicad_pcb" ;;
  *.kicad_pcb) pcb="${in}" ;;
  *) echo "expected a .kicad_pcb or .kicad_pro file" >&2; exit 1 ;;
esac
[[ -f "${pcb}" ]] || { echo "board not found: ${pcb}" >&2; exit 1; }
pcb_dir="$(cd "$(dirname "${pcb}")" && pwd)"
pcb="${pcb_dir}/$(basename "${pcb}")"
out="${out:-${pcb_dir}/cad/board}"

fail() { echo "FAILED: $*" >&2; exit 1; }
mkdir -p "${out}" || fail "cannot create ${out}"

echo "== board.step"
"${CLI}" pcb export step --force --board-only --drill-origin -o "${out}/board.step" "${pcb}" || fail "board step"
echo "== connectors.step (filter: ${filter})"
"${CLI}" pcb export step --force --no-board-body --component-filter "${filter}" --drill-origin \
  -o "${out}/connectors.step" "${pcb}" || fail "connectors step"
echo "== positions.csv"
"${CLI}" pcb export pos --format csv --units mm --use-drill-file-origin --side both \
  -o "${out}/positions.csv" "${pcb}" || fail "pos export"
echo "== outline.dxf"
"${CLI}" pcb export dxf --layers Edge.Cuts --use-drill-origin --output-units mm --mode-single \
  -o "${out}/outline.dxf" "${pcb}" || fail "dxf export"

ver="$("${CLI}" version 2>/dev/null | head -n 1 | tr -d '[:space:]')"
rev="no git repo"
if git -C "${pcb_dir}" rev-parse --git-dir >/dev/null 2>&1; then
  rev="$(git -C "${pcb_dir}" rev-parse --short HEAD 2>/dev/null || echo none)"
  if [[ -n "$(git -C "${pcb_dir}" status --porcelain -- "${pcb}" 2>/dev/null)" ]]; then rev="${rev} (dirty)"; else rev="${rev} (clean)"; fi
fi
cat > "${out}/README.txt" <<TXT
board:       ${pcb}
kicad-cli:   ${ver}
git:         ${rev}
filter:      ${filter}
datum:       all files use the board's drill/aux origin; set it on a mounting hole or a board corner in pcbnew
             before exporting. Confirm the Y axis direction once per project by comparing one known hole
             position between positions.csv and board.step.
TXT

echo "== summary"
for f in board.step connectors.step positions.csv outline.dxf README.txt; do
  [[ -f "${out}/${f}" ]] || fail "missing ${out}/${f}"
  printf '%s  %s bytes\n' "${out}/${f}" "$(wc -c < "${out}/${f}" | tr -d ' ')"
done
