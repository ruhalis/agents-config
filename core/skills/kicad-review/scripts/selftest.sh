#!/usr/bin/env bash
# Offline self-test of the bundled scripts on assets/fixtures/. No kicad-cli, no project; writes only a temp dir.
# Run it in step 0 whenever check_kicad.sh reports a kicad-cli other than the pin, and after editing a script.
#
#   selftest.sh
#
# Fixtures, trimmed from aquila-fc exported by kicad-cli 10.0.5:
#   board.net   netlist with U1 = ESP32-S3-WROOM-1-N16R8 and KiCad 10 pin functions NAME_<pad>: IO4_4, IO8_12,
#               IO17_10, USB_D-_13, USB_D+_14, RXD0_36, TXD0_37, EN_3, 3V3_2, GND_1; IO3 and IO35 unconnected
#   pins.h      a flat #define PIN_* header wired to it
#   fab/        bom.csv, cpl.csv and gerber/aquila-fc-job.gbrjob from a fab_export.sh run; the layer, drill and map
#               files are generated here with a timestamp, so fab_diff sees two exports of one board
# Asserts: pin_diff.py exit codes (0 clean, 2 error rows, 1 misuse) and its OK/CAUTION/HEADER-ONLY/RESERVED/
# NAME-MISMATCH/DUPLICATE rows, on KiCad 10 and pre-10 (no _<pad>) pin names; fabset.py check, the file-set and
# BOM/CPL designator-set check fab_export.sh runs, on a good set and broken ones; fabset.py manifest on stand-in
# files (sheets referenced from the root, a missing one, a G85 slot, a pin diff older than board.net, the git line
# clean and then DIRTY with sheets modified in a sub- and a sibling directory); fab_diff.sh
# on a re-stamped set and a changed one; no __pycache__ left in the skill.
# Runs python with PYTHONDONTWRITEBYTECODE=1.
# Exit 0: every assertion passed. 1: at least one failed (each printed as FAIL with its output).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { echo "usage: $(basename "$0")   (no arguments; offline self-test on assets/fixtures)"; }
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; exit 1 ;;
esac

FIX="${SKILL_DIR}/assets/fixtures"
PIN="${SKILL_DIR}/scripts/pin_diff.py"
FAB="${SKILL_DIR}/scripts/fabset.py"
DIFF="${SKILL_DIR}/scripts/fab_diff.sh"
for f in "${FIX}/board.net" "${FIX}/pins.h" "${FIX}/fab/bom.csv" "${FIX}/fab/cpl.csv" \
         "${FIX}/fab/gerber/aquila-fc-job.gbrjob" "${PIN}" "${FAB}" "${DIFF}"; do
  [[ -f "${f}" ]] || { echo "missing ${f}" >&2; exit 1; }
done
T="$(mktemp -d "${TMPDIR:-/tmp}/kicad-review-selftest.XXXXXX")" || exit 1
trap 'rm -rf "${T}"' EXIT

passed=0; failed=0; out=""; rc=0
ok()  { passed=$((passed + 1)); echo "ok    $*"; }
bad() { failed=$((failed + 1)); echo "FAIL  $*"; printf '%s\n' "${out}" | tail -n 25 | sed 's/^/      | /'; }
# expect <exit code> <label> <command...>: runs it, keeps its output in ${out} for the has/lacks checks after it
expect() {
  local want="$1" label="$2"; shift 2
  out="$("$@" 2>&1)"; rc=$?
  if [[ "${rc}" -eq "${want}" ]]; then ok "${label}: exit ${rc}"; else bad "${label}: exit ${rc}, want ${want}"; fi
}
has()   { if printf '%s\n' "${out}" | grep -Eq -- "$2"; then ok "$1"; else bad "$1: no line matching /$2/"; fi; }
lacks() { if printf '%s\n' "${out}" | grep -Eq -- "$2"; then bad "$1: a line matches /$2/"; else ok "$1"; fi; }

echo "== pin_diff.py on the KiCad 10 fixture"
pd() { python3 "${PIN}" --netlist "${1}" --header "${2}" --mcu U1 "${@:3}"; }
expect 0 "--help" python3 "${PIN}" --help
expect 0 "clean header" pd "${FIX}/board.net" "${FIX}/pins.h"
has   "IO4_4 -> GPIO4 OK"                  '^4 +PIN_MOTOR_FR +/MOTOR_FR +OK +IO4_4$'
has   "IO8_12: pad suffix stripped, GPIO8"  '^8 +PIN_I2C_SDA +/I2C_SDA +OK +IO8_12$'
has   "USB_D-_13 -> GPIO19 OK"             '^19 +PIN_USB_DN +/USB_DN +OK +USB_D-_13$'
has   "USB_D+_14 -> GPIO20 OK"             '^20 +PIN_USB_DP +/USB_DP +OK +USB_D\+_14$'
has   "TXD0_37 -> GPIO43 OK"               '^43 +PIN_UART0_TX +/UART0_TX +OK +TXD0_37$'
has   "RXD0_36 -> GPIO44 OK"               '^44 +PIN_UART0_RX +/UART0_RX +OK +RXD0_36$'
has   "GPIO19 CAUTION (USB)"               '^19 +PIN_USB_DN +/USB_DN +CAUTION '
has   "GPIO43 CAUTION (UART0)"             '^43 +PIN_UART0_TX +/UART0_TX +CAUTION '
has   "GPIO0 /BOOT CAUTION (strapping)"    '^0 +- +/BOOT +CAUTION '
lacks "USB/UART0 pins all mapped"          '^unmapped .*(USB_D|RXD0|TXD0)'
has   "only power pins unmapped"           '^unmapped U1 pins \(no GPIO number\): 3V3_2\(pad 2\), EN_3\(pad 3\), GND_1\(pad 1\), GND_40\(pad 40\), GND_41\(pad 41\)$'
has   "summary"                            '^errors=0 warnings=5 info=1 +\(header pins: 7, U1 GPIO pins in netlist: 10\)$'

sed -E 's/\(pinfunction "(.+)_[0-9]+"\)/(pinfunction "\1")/' "${FIX}/board.net" > "${T}/pre10.net"
expect 0 "pre-10 pin names (no _<pad>)" pd "${T}/pre10.net" "${FIX}/pins.h"
has   "USB_D- alias without suffix"        '^19 +PIN_USB_DN +/USB_DN +OK +USB_D-$'
has   "same summary"                       '^errors=0 warnings=5 info=1 '

{ cat "${FIX}/pins.h"; echo '#define PIN_FLOW_MOT 35'; } > "${T}/io35.h"
expect 2 "define on an unconnected pin (IO35, octal PSRAM on N16R8)" pd "${FIX}/board.net" "${T}/io35.h"
has   "HEADER-ONLY row"                    '^35 +PIN_FLOW_MOT +unconnected-\(U1-IO35-Pad28\) +HEADER-ONLY '
has   "CAUTION row for 35"                 '^35 +PIN_FLOW_MOT .* CAUTION '

{ cat "${FIX}/pins.h"; echo '#define PIN_SPARE 30'; } > "${T}/io30.h"
expect 2 "define on a flash line (GPIO30)" pd "${FIX}/board.net" "${T}/io30.h"
has   "RESERVED row"                       '^30 +PIN_SPARE +- +RESERVED '

sed 's/PIN_BUZZER /PIN_BEEPER /' "${FIX}/pins.h" > "${T}/beeper.h"
expect 0 "renamed define" pd "${FIX}/board.net" "${T}/beeper.h"
has   "NAME-MISMATCH row"                  '^17 +PIN_BEEPER +/BUZZER +NAME-MISMATCH '

{ cat "${FIX}/pins.h"; echo '#define PIN_MOTOR_ALT 4'; } > "${T}/dup.h"
expect 0 "two defines on GPIO4" pd "${FIX}/board.net" "${T}/dup.h"
has   "DUPLICATE row"                      '^4 +PIN_MOTOR_FR,PIN_MOTOR_ALT .* DUPLICATE '

echo '/* no pins */' > "${T}/empty.h"
expect 1 "misuse: --mcu not in netlist" pd "${FIX}/board.net" "${FIX}/pins.h" --mcu U99
has   "names the refs present"             'ref U99 not in netlist'
expect 1 "misuse: unknown option" pd "${FIX}/board.net" "${FIX}/pins.h" --bogus
expect 1 "misuse: header without PIN_ defines" pd "${FIX}/board.net" "${T}/empty.h"
expect 1 "misuse: not a netlist" pd "${FIX}/pins.h" "${FIX}/pins.h"

echo "== fabset.py check (fab_export.sh's file-set and BOM/CPL checks)"
# mkset <dir> <timestamp>: the fixture set plus generated layer, drill and map files carrying the timestamp
mkset() {
  mkdir -p "$1/gerber" && cp "${FIX}/fab/bom.csv" "${FIX}/fab/cpl.csv" "$1/" && \
  python3 - "${FIX}/fab/gerber/aquila-fc-job.gbrjob" "$1/gerber" "$2" <<'PY'
import json, os, sys
job, gdir, ts = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(job))
d["Header"]["CreationDate"] = ts
open(os.path.join(gdir, os.path.basename(job)), "w").write(json.dumps(d, indent=2) + "\n")
for a in d["FilesAttributes"]:
    open(os.path.join(gdir, a["Path"]), "w").write(
        "G04 #@! TF.CreationDate,%s*\nG04 #@! TF.FileFunction,%s*\n%%FSLAX46Y46*%%\n"
        "G04 Created by KiCad (PCBNEW 10.0.5) date %s*\n%%MOMM*%%\n%%ADD10C,0.200000*%%\nD10*\n"
        "X10000000Y-10000000D03*\nM02*\n" % (ts, a["FileFunction"], ts))
open(os.path.join(gdir, "aquila-fc.drl"), "w").write(
    "M48\n; DRILL file KiCad 10.0.5 date %s\n; #@! TF.CreationDate,%s\nFMAT,2\nMETRIC\n"
    "; #@! TA.AperFunction,Plated,PTH,ViaDrill\nT1C0.300\n"
    "; #@! TA.AperFunction,NonPlated,NPTH,ComponentDrill\nT2C3.200\n%%\nG90\nG05\n"
    "T1\nX10.0Y-10.0\nX12.0Y-10.0\nT2\nX3.0Y-3.0\nM30\n" % (ts, ts))
open(os.path.join(gdir, "aquila-fc-drl_map.gbr"), "w").write(
    "%%TF.CreationDate,%s*%%\n%%FSLAX45Y45*%%\nG04 Created by KiCad (PCBNEW 10.0.5) date %s*\n%%MOMM*%%\nM02*\n"
    % (ts, ts))
PY
}
chk() { python3 "${FAB}" check "$1" aquila-fc "${2:-4}"; }
mkset "${T}/good" 2026-09-22T16:17:03+05:00 || { echo "cannot build the fixture set" >&2; exit 1; }
expect 0 "--help" python3 "${FAB}" --help
expect 0 "good set" chk "${T}/good"
has   "gerber set"                         '^gerber files: 14, expected 14  \(copper: 4, drill: 1, edge: aquila-fc-Edge_Cuts\.gm1\)$'
has   "bom counts"                         '^bom lines: 5, parts: 8  \(without LCSC part #: 1: J7\)$'
has   "designator sets agree"              '^bom vs cpl designators: in BOM not CPL: none; in CPL not BOM .*: none$'
has   "assembled count"                    '^  with LCSC in BOM \(assembled\): 7$'
has   "hand-soldered listed"               '^  in BOM without LCSC \(hand-soldered or unassigned\): 1: J7$'

cp -R "${T}/good" "${T}/range" && sed -i.bak 's/"C3,C4,C7,C19"/"C3-C4,C7,C19"/' "${T}/range/bom.csv"
expect 1 "designator range" chk "${T}/range"
has   "range named"                        '^FAIL bom designator ranges \(JLC does not expand them\): C3-C4$'

cp -R "${T}/good" "${T}/nocpl" && grep -v '^U1,' "${T}/good/cpl.csv" > "${T}/nocpl/cpl.csv"
expect 1 "LCSC part with no CPL row" chk "${T}/nocpl"
has   "U1 named"                           '^FAIL bom designators with an LCSC number but no CPL row .*: U1$'

cp -R "${T}/good" "${T}/fid" && echo 'FID1,Fiducial,Fiducial_1mm_Mask2mm,2.000000,-2.000000,0.000000,Top' >> "${T}/fid/cpl.csv"
expect 0 "CPL-only fiducial is listed, not failed" chk "${T}/fid"
has   "FID1 listed"                        'in CPL not BOM .*: FID1$'
has   "board-only count"                   '^  not in BOM \(board-only\): 1$'

cp -R "${T}/good" "${T}/extra" && echo x > "${T}/extra/gerber/stray.gbr"
expect 1 "unexpected gerber file" chk "${T}/extra"
has   "stray named"                        '^FAIL gerber set: .*unexpected: stray\.gbr$'

cp -R "${T}/good" "${T}/missing" && rm "${T}/missing/gerber/aquila-fc-In2_Cu.g2"
expect 1 "missing inner layer file" chk "${T}/missing"
has   "missing named"                      '^FAIL gerber set: .*files missing: aquila-fc-In2_Cu\.g2;'

expect 1 "copper count differs from the job file (fab: says 2 layers)" chk "${T}/good" 2
expect 1 "misuse: no such outdir" chk "${T}/nothing"

echo "== fab_diff.sh"
mkset "${T}/again" 2026-09-23T09:00:00+05:00
expect 0 "--help" bash "${DIFF}" --help
expect 0 "same board exported twice" bash "${DIFF}" "${T}/good" "${T}/again"
has   "timestamps ignored"                 '^identical except timestamps and G04 comments$'

cp -R "${T}/again" "${T}/moved"
# cpl.csv has CRLF line ends, as fab_export.sh writes it
sed -i.bak 's/^U1,\(.*\),22\.000000,-6\.750000,0\.000000,Top/U1,\1,23.500000,-6.750000,90.000000,Top/' "${T}/moved/cpl.csv"
sed -i.bak 's/^T1C0\.300$/T1C0.200/' "${T}/moved/gerber/aquila-fc.drl"
sed -i.bak 's/^X10000000Y-10000000D03\*$/X11000000Y-10000000D03*/' "${T}/moved/gerber/aquila-fc-F_Cu.gtl"
rm -f "${T}"/moved/*.bak "${T}"/moved/gerber/*.bak
expect 2 "moved U1, changed via drill, changed F.Cu" bash "${DIFF}" "${T}/good" "${T}/moved"
has   "U1 move named"                      '^cpl\.csv +1 difference\(s\): U1: Mid X 22\.000000 -> 23\.500000; Rotation 0\.000000 -> 90\.000000$'
has   "drill change by size"               '^  drill 0\.200 mm Plated,PTH,ViaDrill: none -> x2$'
has   "summary names the files"            '^identical except: cpl\.csv, aquila-fc-F_Cu\.gtl, aquila-fc\.drl$'
expect 1 "misuse: one argument" bash "${DIFF}" "${T}/good"

echo "== fabset.py manifest (sheet tree, slots, STALE review counts)"
# Stand-in text files, not KiCad designs: only the Sheetfile properties, the drill file and the mtimes matter here.
R="${T}/repo"; P="${R}/hardware/b"; mkdir -p "${P}/sub" "${P}/review" "${R}/hardware/common" "${T}/mf/gerber"
printf '(kicad_sch\n  (sheet (property "Sheetfile" "sub/child.kicad_sch"))\n  (sheet (property "Sheet file" "gone.kicad_sch"))\n  (sheet (property "Sheetfile" "../common/pwr.kicad_sch"))\n)\n' > "${P}/b.kicad_sch"
printf '(kicad_sch)\n' > "${R}/hardware/common/pwr.kicad_sch"
printf '(kicad_sch\n  (sheet (property "Sheetfile" "grandchild.kicad_sch"))\n)\n' > "${P}/sub/child.kicad_sch"
printf '(kicad_sch)\n' > "${P}/sub/grandchild.kicad_sch"
printf '(kicad_sch)\n' > "${P}/unrelated.kicad_sch"
printf '(kicad_pcb)\n' > "${P}/b.kicad_pcb"
printf 'M48\n; DRILL file KiCad 10.0.5 date 2026-09-23T12:00:00\nMETRIC\n; #@! TA.AperFunction,Plated,PTH,ViaDrill\nT1C0.300\n; #@! TA.AperFunction,Plated,PTH,ComponentDrill\nT2C0.600\n%%\nG90\nG05\nT1\nX1.0Y-1.0\nX2.0Y-1.0\nT2\nX5.0Y-5.0\nX1.91Y-19.28G85X1.31Y-19.28\nG05\nM30\n' > "${T}/mf/gerber/b.drl"
printf '{"sheets":[{"path":"/","violations":[{"severity":"warning","type":"pin_to_pin"}]}]}\n' > "${P}/review/erc.json"
printf 'errors=0 warnings=1 info=2  (header pins: 1, U1 GPIO pins in netlist: 3)\n' > "${P}/review/pin_diff.txt"
printf '(export)\n' > "${P}/review/board.net"
touch -t 202609220900 "${P}/b.kicad_sch" "${P}/sub/child.kicad_sch" "${P}/sub/grandchild.kicad_sch" "${P}/b.kicad_pcb" \
  "${R}/hardware/common/pwr.kicad_sch"
# A git repo around it, so the manifest's git line is exercised: no hooks, no signing, no user config needed.
g() { git -c user.name=selftest -c user.email=selftest@example.invalid -c commit.gpgsign=false -c core.hooksPath="${T}/nohooks" -C "${R}" "$@"; }
have_git=0
if command -v git >/dev/null 2>&1 && g init -q && g add -A && g commit -q -m "board" 2>/dev/null; then have_git=1; else echo "skip  git repo (git missing or cannot commit): git-line checks skipped"; fi
touch -t 202609221000 "${P}/review/erc.json" "${P}/review/pin_diff.txt"
touch -t 202609221100 "${P}/review/board.net"
expect 0 "manifest" python3 "${FAB}" manifest "${T}/mf" --pcb "${P}/b.kicad_pcb" --sch "${P}/b.kicad_sch" \
  --kicad 10.0.5 --copper F.Cu,B.Cu --checks pass
has   "sub-sheet in a subdirectory hashed" '^  [0-9a-f]{64}  sub/child\.kicad_sch$'
has   "its own sub-sheet, relative to it"  '^  [0-9a-f]{64}  sub/grandchild\.kicad_sch$'
has   "missing sheet listed as none"       '^  none +gone\.kicad_sch$'
lacks "unreferenced sheet not hashed"      'unrelated\.kicad_sch'
has   "slot counted apart"                 '^  T2 +0\.600 mm  x1 \+ 1 slots +Plated,PTH,ComponentDrill$'
has   "hole and slot totals"               '^  holes: 3, slots: 1$'
has   "ERC current"                        '^  erc: +warning=1  \(erc\.json, [0-9T:-]+\)$'
has   "pin diff STALE against board.net"   '^  pin_diff: +errors=0 warnings=1 info=2  \(pin_diff\.txt, [0-9T:-]+, STALE: older than review/board\.net\)$'
has   "DRC not run"                        '^  drc: +not run '
if [[ -f "${T}/mf/MANIFEST.txt" ]]; then ok "MANIFEST.txt written"; else bad "MANIFEST.txt not written"; fi
if [[ "${have_git}" -eq 1 ]]; then
  has "git line clean"                     '^git: +[0-9a-f]{12,} clean$'
  echo "; edited" >> "${P}/sub/child.kicad_sch"; echo "; edited" >> "${R}/hardware/common/pwr.kicad_sch"
  touch -t 202609220900 "${P}/sub/child.kicad_sch" "${R}/hardware/common/pwr.kicad_sch"   # keep the review counts current
  expect 0 "manifest on a dirty tree" python3 "${FAB}" manifest "${T}/mf" --pcb "${P}/b.kicad_pcb" --sch "${P}/b.kicad_sch" \
    --kicad 10.0.5 --copper F.Cu,B.Cu --checks pass
  has "sub-sheet in a subdirectory seen"   '^git: +[0-9a-f]{12,} DIRTY: .*sub/child\.kicad_sch \(modified\)'
  has "sheet in a sibling directory seen"  '^git: +[0-9a-f]{12,} DIRTY: .*\.\./common/pwr\.kicad_sch \(modified\)'
  lacks "root sheet not reported"          'DIRTY: .*[ ,]b\.kicad_sch'
fi

echo "== bytecode"
out="$(find "${SKILL_DIR}" -name __pycache__ -o -name '*.pyc')"
if [[ -z "${out}" ]]; then ok "no __pycache__ or .pyc in the skill"; else bad "bytecode in the skill"; fi

echo "selftest: ${passed} passed, ${failed} failed"
[[ "${failed}" -eq 0 ]]
