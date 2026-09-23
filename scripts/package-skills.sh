#!/usr/bin/env bash
# Package skills for upload to claude.ai: core/skills/<name> -> build/skills/<name>.skill
#
#   scripts/package-skills.sh              every skill
#   scripts/package-skills.sh esp-idf      just these
#
# A skill must pass scripts/check-skills.sh first. One that fails is not packaged,
# and any older archive of it is deleted, so build/skills never holds a stale
# upload. The archive root is the skill name. Left out, as skill-creator's
# packager does: __pycache__/, node_modules/, *.pyc, .DS_Store, and evals/ at the
# skill root. Entries are sorted with fixed timestamps and modes, so an unchanged
# skill packages to a byte-identical file.
#
# Uploading is by hand; see "Skills and claude.ai" in README.md.
# Exit 1 if any skill was not packaged.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_DIR/build/skills"

case "${1-}" in
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

if [ $# -gt 0 ]; then
    names=("$@")
    for n in "${names[@]}"; do
        [ -d "$REPO_DIR/core/skills/$n" ] || { echo "no core/skills/$n (try --help)" >&2; exit 2; }
    done
else
    names=()
    for d in "$REPO_DIR"/core/skills/*/; do
        [ -d "$d" ] && names+=("$(basename "$d")")
    done
fi

[ ${#names[@]} -gt 0 ] || { echo "no skills in core/skills" >&2; exit 2; }
mkdir -p "$OUT"
failed=""
done_any=0
for n in "${names[@]}"; do
    [ -d "$REPO_DIR/core/skills/$n" ] || { echo "no core/skills/$n" >&2; exit 2; }
    if ! report=$("$REPO_DIR/scripts/check-skills.sh" --no-refs "$n" 2>&1); then
        rm -f "$OUT/$n.skill"
        printf 'skip  %-24s fails scripts/check-skills.sh; nothing packaged\n' "$n"
        printf '%s\n' "$report" | sed -n 's/^ *FAIL: /        FAIL: /p'
        failed+=" $n"
        continue
    fi
    printf 'ok    %-24s build/skills/%s.skill  ' "$n" "$n"
    python3 - "$REPO_DIR/core/skills/$n" "$OUT/$n.skill" "$n" <<'PY'
import hashlib, os, stat, sys, zipfile
from pathlib import Path

src, dst, name = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]


def packaged(rel):
    if any(p in ("__pycache__", "node_modules") for p in rel.parts[:-1]):
        return False
    if len(rel.parts) > 1 and rel.parts[0] == "evals":
        return False
    return rel.name != ".DS_Store" and rel.suffix != ".pyc"


files = sorted(p.relative_to(src) for p in src.rglob("*") if p.is_file())
files = [r for r in files if packaged(r)]
tmp = dst.with_name(dst.name + ".tmp")
with zipfile.ZipFile(tmp, "w") as z:
    for rel in files:
        path = src / rel
        info = zipfile.ZipInfo(f"{name}/{rel.as_posix()}", date_time=(1980, 1, 1, 0, 0, 0))
        info.create_system = 3  # unix, so the modes below are kept
        mode = 0o755 if os.stat(path).st_mode & stat.S_IXUSR else 0o644
        info.external_attr = (stat.S_IFREG | mode) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, path.read_bytes(), compresslevel=9)
os.replace(tmp, dst)
print(f"{len(files)} file{'' if len(files) == 1 else 's'}, sha256 {hashlib.sha256(dst.read_bytes()).hexdigest()[:12]}")
PY
    done_any=1
done

[ "$done_any" = 0 ] ||
    echo "upload each .skill in claude.ai under Customize > Skills, then run scripts/skill-sync-status.sh"
[ -z "$failed" ] || { echo "not packaged:$failed" >&2; exit 1; }
