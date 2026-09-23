#!/usr/bin/env bash
# Compare two fab sets written by fab_export.sh. Read-only.
#
#   fab_diff.sh <old_outdir> <new_outdir>     e.g. hardware/<b>/fab/2026-09-22b hardware/<b>/fab/2026-09-22c
#
# bom.csv by designator (value, footprint, LCSC, MPN), cpl.csv by designator and field (a moved or rotated part
# names its old and new Mid X/Mid Y/Rotation), every gerber/ file line by line and the drill tool table, with
# timestamp lines stripped first: G04 comments, %TF.CreationDate, the drill header's date line and TF.CreationDate,
# the job file's CreationDate. When both sets hold a MANIFEST.txt, its source sha256 lines are compared for
# information only (an edit no fab file shows, e.g. a note on an unplotted layer, still changes the hash): the
# fab outputs decide the exit code.
# gerbers.zip is not compared (it is gerber/ zipped, with zip timestamps). Ends with `identical except ...`.
# Exit 0: identical except timestamp lines. 2: the sets differ. 1: misuse or a set it could not read.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { echo "usage: $(basename "$0") <old_fab_outdir> <new_fab_outdir>"; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
[[ $# -eq 2 && -d "$1" && -d "$2" ]] || { usage >&2; exit 1; }
exec python3 -B "${SKILL_DIR}/scripts/fabset.py" diff "$1" "$2"
