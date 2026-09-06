#!/usr/bin/env bash
# ERC or DRC through kicad-cli: the JSON report is kept, a grouped summary is printed.
# Never modifies the project (kicad-cli itself may write <project>.kicad_prl and fp-info-cache beside it).
#
#   erc_drc.sh erc <root.kicad_sch> [outdir]     -> <outdir>/erc.json
#   erc_drc.sh drc <board.kicad_pcb> [outdir]    -> <outdir>/drc.json   (adds --schematic-parity)
#
# outdir defaults to review/ next to the input file.
# Exit codes are kicad-cli's, passed through: 0 clean, 5 violations reported (any severity),
# 3 the file failed to load. 1 = misuse of this script.
set -uo pipefail

APP="${KICAD_APP:-/Applications/KiCad/KiCad.app}"
CLI="${APP}/Contents/MacOS/kicad-cli"

mode="${1:-}"
in="${2:-}"
out="${3:-}"

case "${mode}" in
  erc|drc) ;;
  *) echo "usage: $(basename "$0") erc|drc <file> [outdir]" >&2; exit 1 ;;
esac
[[ -f "${in}" ]] || { echo "no such file: ${in}" >&2; exit 1; }
[[ -x "${CLI}" ]] || { echo "kicad-cli not found at ${CLI}; run check_kicad.sh" >&2; exit 1; }
[[ -n "${out}" ]] || out="$(dirname "${in}")/review"
mkdir -p "${out}" || exit 1
json="${out}/${mode}.json"
rm -f "${json}"

if [[ "${mode}" == erc ]]; then
  "${CLI}" sch erc --format json --severity-all --exit-code-violations -o "${json}" "${in}"
else
  "${CLI}" pcb drc --format json --severity-all --exit-code-violations --schematic-parity -o "${json}" "${in}"
fi
rc=$?

if [[ ! -s "${json}" ]]; then
  echo "kicad-cli exit ${rc}: no report written (load failure? see the lines above)"
  exit "${rc}"
fi

python3 - "${json}" "${mode}" <<'PY'
import json, sys
from collections import Counter, OrderedDict

path, mode = sys.argv[1], sys.argv[2]
d = json.load(open(path))

# Flatten to (category, violation). ERC: sheets[].violations[]. DRC: violations[], unconnected_items[], schematic_parity[].
rows = []
if mode == "erc":
    for sheet in d.get("sheets", []):
        for v in sheet.get("violations", []):
            rows.append(("sheet %s" % sheet.get("path", "/"), v))
else:
    for cat in ("violations", "unconnected_items", "schematic_parity"):
        for v in d.get(cat, []):
            rows.append((cat, v))

sev = Counter(v.get("severity", "?") for _, v in rows)
print("%s of %s (kicad %s)" % (mode.upper(), d.get("source", "?"), d.get("kicad_version", "?")))
print("report: %s" % path)
print("counts: " + (", ".join("%s=%d" % (k, sev[k]) for k in ("error", "warning", "exclusion") if sev[k]) or "clean"))
if mode == "drc":
    print("unconnected_items=%d schematic_parity=%d"
          % (len(d.get("unconnected_items", [])), len(d.get("schematic_parity", []))))

by_type = OrderedDict()
for cat, v in rows:
    key = (v.get("severity", "?"), v.get("type", "?"))
    if key not in by_type:
        by_type[key] = [0, v.get("description", "")]
    by_type[key][0] += 1
if by_type:
    print("by type:")
    for (s, t), (n, desc) in sorted(by_type.items(), key=lambda kv: ({"error": 0, "warning": 1}.get(kv[0][0], 2), -kv[1][0])):
        print("  %-9s %-32s x%-4d %s" % (s, t, n, desc[:90]))

errors = [(cat, v) for cat, v in rows if v.get("severity") == "error"]
if errors:
    print("first %d errors:" % min(20, len(errors)))
    for cat, v in errors[:20]:
        items = "; ".join(i.get("description", "") for i in v.get("items", [])[:3])
        pos = (v.get("items") or [{}])[0].get("pos")
        where = " @(%.2f,%.2f)" % (pos["x"], pos["y"]) if pos else ""
        print("  [%s] %s: %s -- %s%s" % (v.get("type", "?"), cat, v.get("description", ""), items, where))
    if len(errors) > 20:
        print("  ... %d more in the JSON" % (len(errors) - 20))
PY

exit "${rc}"
