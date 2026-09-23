#!/usr/bin/env bash
# JLCPCB-ready file set from a finished board, through kicad-cli only. Never touches the project files.
#
#   fab_export.sh <board.kicad_pcb> <root.kicad_sch> <outdir>
#
# Writes  <outdir>/gerber/*   gerbers (Protel extensions, zones refilled in memory) + Excellon drill + drill map;
#                             the directory is emptied first, so no stale file reaches the zip
#         <outdir>/gerbers.zip
#         <outdir>/bom.csv    JLC columns: Comment, Designator, Footprint, LCSC Part #, plus Quantity and MPN;
#                             designators comma-listed, never ranges
#         <outdir>/cpl.csv    JLC columns: Designator, Val, Package, Mid X, Mid Y, Rotation, Layer
# then checks the set and prints counts for the pre-order checklist in references/jlcpcb-order.md.
#
# Env: LCSC_FIELD (default LCSC) — the symbol field that holds the LCSC part number.
#      MPN_FIELD  (default MPN)
# Exit 1 on any kicad-cli failure, on misuse, or on a failed check: gerber/ is not exactly the files the job file
# lists plus drill, map and job file, one per requested layer; a BOM cell holds a designator range; a BOM designator
# with an LCSC number has no CPL row. CPL-only designators (fiducials, logos) are listed, not failed.
set -uo pipefail

APP="${KICAD_APP:-/Applications/KiCad/KiCad.app}"
CLI="${APP}/Contents/MacOS/kicad-cli"
LCSC_FIELD="${LCSC_FIELD:-LCSC}"
MPN_FIELD="${MPN_FIELD:-MPN}"

pcb="${1:-}"; sch="${2:-}"; out="${3:-}"
[[ -f "${pcb}" && -f "${sch}" && -n "${out}" ]] || { echo "usage: $(basename "$0") <board.kicad_pcb> <root.kicad_sch> <outdir>" >&2; exit 1; }
[[ -x "${CLI}" ]] || { echo "kicad-cli not found at ${CLI}; run check_kicad.sh" >&2; exit 1; }
# <outdir>/gerber is emptied before plotting, so refuse an outdir that could hold anything else: the board's own
# directory, or a gerber/ with files that are not fab outputs.
mkdir -p "${out}" || exit 1
[[ "$(cd "$(dirname "${pcb}")" && pwd)" != "$(cd "${out}" && pwd)" ]] || { echo "outdir is the board's own directory; use <board>/fab/<date>" >&2; exit 1; }
if [[ -d "${out}/gerber" ]] && find "${out}/gerber" -type f ! -name '*.g[a-z0-9]*' ! -name '*.drl' ! -name '*.pdf' | grep -q .; then
  echo "${out}/gerber holds files that are not fab outputs; move them or use a fresh outdir" >&2; exit 1
fi
rm -rf "${out}/gerber" && mkdir -p "${out}/gerber" || exit 1

fail() { echo "FAILED: $*" >&2; exit 1; }

# Copper layer set from the board's (layers ...) header only, lines like `(4 "In1.Cu" power ["GND"])`: F.Cu, In1.Cu..,
# B.Cu. Pad and zone layer lists elsewhere in the file can name In1..In30 on a 2-layer board, so they are not read.
inner="$(grep -oE '^[[:space:]]*\([0-9]+ "In[0-9]+\.Cu"' "${pcb}" | grep -oE 'In[0-9]+\.Cu' | sort -t n -k2 -n | uniq | tr '\n' ',')"
copper="F.Cu,${inner}B.Cu"
copper_count=$(( $(printf '%s' "${copper}" | tr ',' '\n' | grep -c .) ))
layers="${copper},F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts"

# --check-zones refills zones in memory before plotting (the saved fills may be stale); the board is not saved.
echo "== gerbers (${copper_count} copper layers)"
"${CLI}" pcb export gerbers -o "${out}/gerber/" -l "${layers}" \
  --subtract-soldermask --no-x2 --check-zones "${pcb}" || fail "gerber export"

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

# --ref-range-delimiter '' lists every designator (C10,C11,...): JLC's uploader does not expand C10-C15.
echo "== BOM"
"${CLI}" sch export bom -o "${out}/bom.csv" \
  --fields "Value,Reference,Footprint,${LCSC_FIELD},\${QUANTITY},${MPN_FIELD}" \
  --labels "Comment,Designator,Footprint,LCSC Part #,Quantity,MPN" \
  --group-by "Value,Footprint,${LCSC_FIELD}" --ref-range-delimiter '' --exclude-dnp "${sch}" || fail "bom export"

echo "== zip"
( cd "${out}" && rm -f gerbers.zip && zip -q -r gerbers.zip gerber ) || fail "zip"

echo "== checks and counts"
python3 - "${out}" "$(basename "${pcb}" .kicad_pcb)" "${copper_count}" <<'PY' || fail "file-set checks (FAIL lines above)"
import csv, json, os, re, sys
out, stem, ncu = sys.argv[1], sys.argv[2], int(sys.argv[3])
bad = False

def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]

def show(refs):
    refs = sorted(refs, key=natural)
    return ", ".join(refs) if refs else "none"

# Gerber set. Layer files are named after the layer's user name (a renamed In1.Cu plots as <stem>-GND.g1), so the
# expected names come from the job file kicad-cli wrote: one file per requested layer by function, and the directory
# holds exactly those plus drill, drill map and job file.
g = sorted(os.listdir(os.path.join(out, "gerber")))
exact = ["%s.drl" % stem, "%s-drl_map.gbr" % stem, "%s-job.gbrjob" % stem]
try:
    attrs = json.load(open(os.path.join(out, "gerber", exact[2])))["FilesAttributes"]
    plotted = [a["Path"] for a in attrs]
    funcs = [a.get("FileFunction", "") for a in attrs]
except (OSError, ValueError, KeyError, TypeError) as e:
    print("FAIL gerber job file %s unreadable: %s" % (exact[2], e))
    plotted, funcs, bad = [], [], True
want = ["Copper,L%d," % i for i in range(1, ncu + 1)] + [
    "SolderPaste,Top", "SolderPaste,Bot", "Legend,Top", "Legend,Bot", "SolderMask,Top", "SolderMask,Bot", "Profile"]
fn_bad = [w.rstrip(",") for w in want if sum(f.startswith(w) for f in funcs) != 1]
if len(funcs) != len(want):
    fn_bad.append("%d layer files for %d requested layers" % (len(funcs), len(want)))
missing = [x for x in plotted + exact if x not in g]
extra = [f for f in g if f not in plotted + exact]
edge = [p for p, f in zip(plotted, funcs) if f.startswith("Profile")]
print("gerber files: %d, expected %d  (copper: %d, drill: %d, edge: %s)"
      % (len(g), len(want) + len(exact), sum(f.startswith("Copper,") for f in funcs),
         sum(x.lower().endswith(".drl") for x in g), ", ".join(edge) or "NONE"))
if fn_bad or missing or extra:
    print("FAIL gerber set: layer functions missing or duplicated: %s; files missing: %s; unexpected: %s"
          % (show(fn_bad), show(missing), show(extra)))
    bad = True

# BOM: comma-listed designators only; a range token (C10-C15) is a failure.
rows = list(csv.DictReader(open(os.path.join(out, "bom.csv"), newline="")))
rng = re.compile(r"^([A-Z]+)([0-9]+)-([A-Z]*)([0-9]+)$")
def members(t):  # a range token counts as its members in the BOM/CPL comparison, so it only fails once
    m = rng.match(t)
    if not m or (m.group(3) and m.group(3) != m.group(1)):
        return [t]
    return ["%s%d" % (m.group(1), i) for i in range(int(m.group(2)), int(m.group(4)) + 1)]
bom_refs, lcsc_refs, ranges = set(), set(), []
for r in rows:
    toks = [t.strip() for t in (r.get("Designator") or "").split(",") if t.strip()]
    ranges += [t for t in toks if rng.match(t)]
    toks = [m for t in toks for m in members(t)]
    bom_refs.update(toks)
    if (r.get("LCSC Part #") or "").strip():
        lcsc_refs.update(toks)
missing_lcsc = [r["Designator"] for r in rows if not (r.get("LCSC Part #") or "").strip()]
print("bom lines: %d, parts: %d  (without LCSC part #: %d%s)"
      % (len(rows), len(bom_refs), len(missing_lcsc), (": " + "; ".join(missing_lcsc)[:200]) if missing_lcsc else ""))
if ranges:
    print("FAIL bom designator ranges (JLC does not expand them): %s" % ", ".join(ranges))
    bad = True

# BOM designator set against CPL designator set, both directions. A BOM designator with an LCSC number and no CPL row
# is a part JLC will not place: failure. CPL-only designators are footprints excluded from the BOM (KiCad's stock
# fiducials carry exclude_from_bom): listed for the user to explain.
cpl = list(csv.DictReader(open(os.path.join(out, "cpl.csv"), newline="")))
cpl_refs = set(r["Designator"] for r in cpl)
print("bom vs cpl designators: in BOM not CPL: %s; in CPL not BOM (board-only, excluded from BOM: fiducials, logos): %s"
      % (show(bom_refs - cpl_refs), show(cpl_refs - bom_refs)))
if lcsc_refs - cpl_refs:
    print("FAIL bom designators with an LCSC number but no CPL row (JLC will not place them): %s"
          % show(lcsc_refs - cpl_refs))
    bad = True

# CPL rows whose designator has an LCSC number in the BOM are the assembled parts; the other BOM parts are
# hand-soldered or unassigned; CPL-only rows are listed above.
hand = (cpl_refs & bom_refs) - lcsc_refs
print("cpl rows: %d  (top: %d, bottom: %d)"
      % (len(cpl), sum(r["Layer"] == "Top" for r in cpl), sum(r["Layer"] == "Bottom" for r in cpl)))
print("  with LCSC in BOM (assembled): %d" % len(cpl_refs & lcsc_refs))
print("  in BOM without LCSC (hand-soldered or unassigned): %d: %s" % (len(hand), show(hand)))
print("  not in BOM (board-only): %d" % len(cpl_refs - bom_refs))
print("zip: %s" % os.path.join(out, "gerbers.zip"))
sys.exit(1 if bad else 0)
PY
