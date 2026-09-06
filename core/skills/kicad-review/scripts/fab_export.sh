#!/usr/bin/env bash
# JLCPCB-ready file set from a finished board, through kicad-cli only. Never touches the project files.
#
#   fab_export.sh <board.kicad_pcb> <root.kicad_sch> <outdir>
#
# Writes  <outdir>/gerber/*   gerbers (Protel extensions) + Excellon drill + drill map
#         <outdir>/gerbers.zip
#         <outdir>/bom.csv    JLC columns: Comment, Designator, Footprint, LCSC Part #, plus Quantity and MPN
#         <outdir>/cpl.csv    JLC columns: Designator, Val, Package, Mid X, Mid Y, Rotation, Layer
# then prints counts for the pre-order checklist in references/jlcpcb-order.md.
#
# Env: LCSC_FIELD (default LCSC) — the symbol field that holds the LCSC part number.
#      MPN_FIELD  (default MPN)
# Exit 1 on any kicad-cli failure or misuse.
set -uo pipefail

APP="${KICAD_APP:-/Applications/KiCad/KiCad.app}"
CLI="${APP}/Contents/MacOS/kicad-cli"
LCSC_FIELD="${LCSC_FIELD:-LCSC}"
MPN_FIELD="${MPN_FIELD:-MPN}"

pcb="${1:-}"; sch="${2:-}"; out="${3:-}"
[[ -f "${pcb}" && -f "${sch}" && -n "${out}" ]] || { echo "usage: $(basename "$0") <board.kicad_pcb> <root.kicad_sch> <outdir>" >&2; exit 1; }
[[ -x "${CLI}" ]] || { echo "kicad-cli not found at ${CLI}; run check_kicad.sh" >&2; exit 1; }
mkdir -p "${out}/gerber" || exit 1

fail() { echo "FAILED: $*" >&2; exit 1; }

# Copper layer set from the board header: F.Cu, In1.Cu.., B.Cu. A board defines only its enabled copper layers.
inner="$(grep -o '"In[0-9]*\.Cu"' "${pcb}" | tr -d '"' | sort -t n -k2 -n | uniq | tr '\n' ',')"
copper="F.Cu,${inner}B.Cu"
copper_count=$(( $(printf '%s' "${copper}" | tr ',' '\n' | grep -c .) ))
layers="${copper},F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts"

echo "== gerbers (${copper_count} copper layers)"
"${CLI}" pcb export gerbers -o "${out}/gerber/" -l "${layers}" \
  --subtract-soldermask --no-x2 "${pcb}" || fail "gerber export"

echo "== drill"
"${CLI}" pcb export drill -o "${out}/gerber/" --format excellon --drill-origin absolute \
  --excellon-zeros-format decimal --excellon-units mm --generate-map --map-format gerberx2 "${pcb}" || fail "drill export"

echo "== position (CPL)"
raw="${out}/pos_kicad.csv"
"${CLI}" pcb export pos -o "${raw}" --format csv --units mm --side both --exclude-dnp "${pcb}" || fail "pos export"
# kicad-cli columns: Ref,Val,Package,PosX,PosY,Rot,Side  ->  JLC: Designator,Val,Package,Mid X,Mid Y,Rotation,Layer
python3 - "${raw}" "${out}/cpl.csv" <<'PY' || fail "cpl rewrite"
import csv, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, newline="") as f, open(dst, "w", newline="") as g:
    r = csv.reader(f); w = csv.writer(g)
    header = next(r)
    want = ["Ref", "Val", "Package", "PosX", "PosY", "Rot", "Side"]
    if header[:7] != want:
        sys.exit("unexpected pos columns: %r" % header)
    w.writerow(["Designator", "Val", "Package", "Mid X", "Mid Y", "Rotation", "Layer"])
    n = 0
    for row in r:
        if not row: continue
        row[6] = {"top": "Top", "bottom": "Bottom"}.get(row[6].lower(), row[6])
        w.writerow(row[:7]); n += 1
print("cpl rows: %d" % n)
PY
rm -f "${raw}"

echo "== BOM"
"${CLI}" sch export bom -o "${out}/bom.csv" \
  --fields "Value,Reference,Footprint,${LCSC_FIELD},\${QUANTITY},${MPN_FIELD}" \
  --labels "Comment,Designator,Footprint,LCSC Part #,Quantity,MPN" \
  --group-by "Value,Footprint,${LCSC_FIELD}" --exclude-dnp "${sch}" || fail "bom export"

echo "== zip"
( cd "${out}" && rm -f gerbers.zip && zip -q -r gerbers.zip gerber ) || fail "zip"

echo "== counts"
python3 - "${out}" <<'PY'
import csv, os, sys
out = sys.argv[1]
g = sorted(os.listdir(os.path.join(out, "gerber")))
drl = [x for x in g if x.lower().endswith(".drl")]
edge = [x for x in g if x.lower().endswith((".gko", ".gm1")) or "edge" in x.lower()]
print("gerber files: %d  (drill: %d, edge: %s)" % (len(g), len(drl), ", ".join(edge) or "NONE"))
rows = list(csv.DictReader(open(os.path.join(out, "bom.csv"), newline="")))
missing = [r["Designator"] for r in rows if not (r.get("LCSC Part #") or "").strip()]
print("bom lines: %d  (without LCSC part #: %d%s)" % (len(rows), len(missing), (": " + "; ".join(missing)[:200]) if missing else ""))
cpl = list(csv.DictReader(open(os.path.join(out, "cpl.csv"), newline="")))
print("cpl rows: %d  (top: %d, bottom: %d)" % (len(cpl), sum(r["Layer"] == "Top" for r in cpl), sum(r["Layer"] == "Bottom" for r in cpl)))
print("zip: %s" % os.path.join(out, "gerbers.zip"))
PY
