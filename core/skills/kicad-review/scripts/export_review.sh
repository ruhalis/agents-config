#!/usr/bin/env bash
# Legible review exports through kicad-cli, into <board_dir>/review/ (where erc_drc.sh writes). Never touches the
# project files (kicad-cli itself rewrites <project>.kicad_prl beside them).
#
#   export_review.sh sch <board_dir|project.kicad_pro>
#     review/board.net            netlist, kicadsexpr (pin_diff.py reads it)
#     review/bom.csv              review BOM: Reference, Value, Footprint, QUANTITY, LCSC, MPN, DNP; grouped by value,
#                                 footprint and LCSC; designators listed, never ranges
#     review/schematic.pdf        every sheet
#   export_review.sh pcb <board_dir|project.kicad_pro>
#     review/stats.json           board statistics
#     review/front.pdf            F.Cu, F.Silkscreen, Edge.Cuts on one page, autoscaled (--scale 0: the board's
#                                 longer extent fits the page; a portrait board fills the height and about a
#                                 third of an A4-landscape width, and the crops below carry the detail)
#     review/back.pdf             B.Cu, B.Silkscreen, Edge.Cuts, mirrored (seen from below), autoscaled
#     review/inner_In1.Cu.pdf ... one per inner copper layer in the board's (layers ...) header, with Edge.Cuts
#     review/render_top.png, render_bottom.png   3D renders, frame shaped to the board outline
#   Every PCB PDF plots zones refilled in memory (--check-zones); the board is never saved.
#
# Then every PDF page is rasterised at 200 dpi into review/png/ with pdftoppm (PDFTOPPM, else
# /opt/homebrew/bin/pdftoppm, else PATH): <pdf>-p<N>.png is the whole page, and the drawn area (blank margins
# dropped) is cut into overlapping crops of at most about 1.1 megapixels, <pdf>-p<N>-r<row>c<col>.png, which a
# finding cites. Earlier PNGs of these PDFs (zoom crops included) are removed first, so none is left stale.
# No pdftoppm: says so and stops after the PDFs (never installs it).
# Env: LCSC_FIELD (default LCSC), MPN_FIELD (default MPN), as in fab_export.sh.
# Exit 0: every export written. 1: misuse, not exactly one .kicad_pro in board_dir, kicad-cli missing, or an export
# or rasterisation failed.
set -uo pipefail

APP="${KICAD_APP:-/Applications/KiCad/KiCad.app}"
CLI="${APP}/Contents/MacOS/kicad-cli"
LCSC_FIELD="${LCSC_FIELD:-LCSC}"
MPN_FIELD="${MPN_FIELD:-MPN}"
DPI=200

usage() { echo "usage: $(basename "$0") sch|pcb <board_dir|project.kicad_pro>"; }
fail() { echo "FAILED: $*" >&2; exit 1; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  sch|pcb) mode="$1" ;;
  *) usage >&2; exit 1 ;;
esac
in="${2:-}"
case "${in}" in
  "") usage >&2; exit 1 ;;
  *.kicad_pro)
    [[ -f "${in}" ]] || { echo "no such file: ${in}" >&2; exit 1; }
    dir="$(dirname "${in}")"; stem="$(basename "${in}" .kicad_pro)" ;;
  *)
    [[ -d "${in}" ]] || { echo "no such directory: ${in}" >&2; usage >&2; exit 1; }
    dir="${in%/}"
    pros="$(find "${dir}" -maxdepth 1 -name '*.kicad_pro' | sort)"
    n="$(printf '%s' "${pros}" | grep -c .)"
    [[ "${n}" -ne 0 ]] || { echo "no .kicad_pro in ${dir}: pass the board directory that holds it, or the .kicad_pro" >&2; exit 1; }
    [[ "${n}" -eq 1 ]] || { echo "${dir} holds ${n} .kicad_pro files; pass the one to use: ${pros//$'\n'/ }" >&2; exit 1; }
    stem="$(basename "${pros}" .kicad_pro)" ;;
esac
sch="${dir}/${stem}.kicad_sch"
pcb="${dir}/${stem}.kicad_pcb"
rev="${dir}/review"
[[ -x "${CLI}" ]] || { echo "kicad-cli not found at ${CLI}; run check_kicad.sh" >&2; exit 1; }
mkdir -p "${rev}" || exit 1
pdfs=""

if [[ "${mode}" == sch ]]; then
  [[ -f "${sch}" ]] || { echo "no such file: ${sch}" >&2; exit 1; }
  echo "== netlist"
  "${CLI}" sch export netlist --format kicadsexpr -o "${rev}/board.net" "${sch}" >/dev/null || fail "netlist export"
  echo "${rev}/board.net"
  echo "== review BOM"
  "${CLI}" sch export bom -o "${rev}/bom.csv" \
    --fields "Reference,Value,Footprint,\${QUANTITY},${LCSC_FIELD},${MPN_FIELD},\${DNP}" \
    --group-by "Value,Footprint,${LCSC_FIELD}" --ref-range-delimiter '' "${sch}" >/dev/null || fail "bom export"
  echo "${rev}/bom.csv"
  echo "== schematic PDF"
  "${CLI}" sch export pdf -o "${rev}/schematic.pdf" "${sch}" >/dev/null || fail "schematic pdf export"
  echo "${rev}/schematic.pdf"
  pdfs="schematic"
else
  [[ -f "${pcb}" ]] || { echo "no such file: ${pcb}" >&2; exit 1; }
  echo "== stats"
  "${CLI}" pcb export stats --format json -o "${rev}/stats.json" "${pcb}" >/dev/null || fail "stats export"
  echo "${rev}/stats.json"

  plot() {  # plot <name> <layers> [extra kicad-cli flags]
    local name="$1" layers="$2"; shift 2
    "${CLI}" pcb export pdf --mode-single --scale 0 --check-zones "$@" -l "${layers}" \
      -o "${rev}/${name}.pdf" "${pcb}" >/dev/null || fail "${name}.pdf export"
    echo "${rev}/${name}.pdf  (${layers}${*:+, $*})"
    pdfs="${pdfs} ${name}"
  }
  echo "== PDFs (one page each, autoscaled, zones refilled in memory)"
  plot front "F.Cu,F.Silkscreen,Edge.Cuts"
  plot back "B.Cu,B.Silkscreen,Edge.Cuts" --mirror
  # Inner copper from the (layers ...) header only, as fab_export.sh reads it; a PDF for a layer the board no
  # longer has is removed first.
  find "${rev}" -maxdepth 1 -name 'inner_In*.Cu.pdf' -delete
  [[ -d "${rev}/png" ]] && find "${rev}/png" -maxdepth 1 -name 'inner_In*.Cu-p*.png' -delete
  inner="$(grep -oE '^[[:space:]]*\([0-9]+ "In[0-9]+\.Cu"' "${pcb}" | grep -oE 'In[0-9]+\.Cu' | sort -t n -k2 -n | uniq)"
  for l in ${inner}; do plot "inner_${l}" "${l},Edge.Cuts"; done

  echo "== 3D renders"
  size="$(python3 - "${rev}/stats.json" <<'PY'
import json, re, sys
try:  # frame shaped to the outline, long side 2000 px
    b = json.load(open(sys.argv[1]))["board"]
    w, h = (float(re.match(r"[0-9.]+", b[k]).group(0)) for k in ("width", "height"))
    assert w > 0 and h > 0
except Exception:
    print("1600 1600")
    sys.exit(0)
print("2000 %d" % max(400, round(2000 * h / w)) if w >= h else "%d 2000" % max(400, round(2000 * w / h)))
PY
)"
  for side in top bottom; do
    "${CLI}" pcb render --side "${side}" --background opaque --width "${size% *}" --height "${size#* }" \
      -o "${rev}/render_${side}.png" "${pcb}" >/dev/null 2>&1 || fail "render ${side}"
    echo "${rev}/render_${side}.png  ($(python3 -c 'import struct, sys; f = open(sys.argv[1], "rb"); f.read(16); print("%dx%d" % struct.unpack(">II", f.read(8)))' "${rev}/render_${side}.png"))"
  done
fi

# PNGs of an earlier export of these PDFs, zoom crops included, no longer match them.
if [[ -d "${rev}/png" ]]; then
  for name in ${pdfs}; do find "${rev}/png" -maxdepth 1 -name "${name}-p*.png" -delete; done
fi

ppm="${PDFTOPPM:-/opt/homebrew/bin/pdftoppm}"
[[ -x "${ppm}" ]] || ppm="$(command -v pdftoppm 2>/dev/null || true)"
if [[ -z "${ppm}" ]]; then
  echo "== PNG crops skipped: no pdftoppm (Homebrew poppler; ask the user before installing anything). Read the PDFs."
  exit 0
fi

echo "== PNG at ${DPI} dpi and crops of the drawn area (${ppm})"
# shellcheck disable=SC2086  # pdfs is a space-separated list of plain names
python3 - "${ppm}" "${rev}" "${DPI}" ${pdfs} <<'PY' || fail "rasterisation"
import math, os, re, struct, subprocess, sys, tempfile

ppm, rev, dpi, names = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
png = os.path.join(rev, "png")
os.makedirs(png, exist_ok=True)
LO = 20                    # dpi of the grey probe that finds the drawn area
PAD, OVER = 20, 40         # px at dpi: margin kept around the drawn area, overlap between neighbouring crops
SIDE, AREA = 1400, 1150000 # crop limits: longest side and pixel count stay under common image-reader downscaling
WHITE = bytes(range(245, 256))


def run(*args):
    subprocess.run([ppm] + list(args), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def drawn(path):
    """(x0, y0, x1, y1) of the non-white pixels of a P5 PGM, or None for a blank page."""
    data = open(path, "rb").read()
    m = re.match(rb"P5\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    w, h = int(m.group(1)), int(m.group(2))
    pix = data[m.end():]
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = pix[y * w:(y + 1) * w]
        left = w - len(row.lstrip(WHITE))
        if left < w:
            x0, x1 = min(x0, left), max(x1, len(row.rstrip(WHITE)) - 1)
            y0, y1 = min(y0, y), y
    return None if x1 < 0 else (x0, y0, x1 + 1, y1 + 1)


def grid(bw, bh):
    nx, ny = max(1, math.ceil(bw / (SIDE - 2 * OVER))), max(1, math.ceil(bh / (SIDE - 2 * OVER)))
    while True:
        tw, th = math.ceil(bw / nx), math.ceil(bh / ny)
        if (tw + 2 * OVER) * (th + 2 * OVER) <= AREA:
            return nx, ny, tw, th
        if tw >= th:
            nx += 1
        else:
            ny += 1


with tempfile.TemporaryDirectory() as tmp:
    for name in names:
        pdf = os.path.join(rev, name + ".pdf")
        run("-r", str(LO), "-gray", pdf, os.path.join(tmp, name))
        probes = sorted((f for f in os.listdir(tmp) if f.startswith(name + "-") and f.endswith(".pgm")),
                        key=lambda f: int(re.search(r"-(\d+)\.pgm$", f).group(1)))
        for i, probe in enumerate(probes, 1):
            page = os.path.join(png, "%s-p%d" % (name, i))
            run("-r", str(dpi), "-png", "-singlefile", "-f", str(i), "-l", str(i), pdf, page)
            W, H = png_size(page + ".png")
            box = drawn(os.path.join(tmp, probe))
            if box is None:
                print("%s.png  %dx%d, blank page" % (page, W, H))
                continue
            s = dpi / LO
            x0, y0 = max(0, int(box[0] * s) - PAD), max(0, int(box[1] * s) - PAD)
            x1, y1 = min(W, int(math.ceil(box[2] * s)) + PAD), min(H, int(math.ceil(box[3] * s)) + PAD)
            nx, ny, tw, th = grid(x1 - x0, y1 - y0)
            for r in range(ny):
                for c in range(nx):
                    cx0, cy0 = max(0, x0 + c * tw - OVER), max(0, y0 + r * th - OVER)
                    cx1, cy1 = min(W, x0 + (c + 1) * tw + OVER), min(H, y0 + (r + 1) * th + OVER)
                    run("-r", str(dpi), "-png", "-singlefile", "-f", str(i), "-l", str(i), "-x", str(cx0),
                        "-y", str(cy0), "-W", str(cx1 - cx0), "-H", str(cy1 - cy0), pdf,
                        "%s-r%dc%d" % (page, r + 1, c + 1))
            last = "" if nx * ny == 1 else " .. r%dc%d" % (ny, nx)
            print("%s.png  %dx%d; drawn area %dx%d at (%d,%d): %d crop(s) %s-p%d-r1c1%s, about %dx%d px"
                  % (page, W, H, x1 - x0, y1 - y0, x0, y0, nx * ny, name, i, last, tw + 2 * OVER, th + 2 * OVER))
PY
exit 0
