#!/usr/bin/env bash
# Compare each core/skills/<name> with its claude.ai copy, which Claude Code
# downloads to ~/.claude/skills/synced/<bucket>/<name>. Reads only.
#
#   scripts/skill-sync-status.sh              one line per skill
#   scripts/skill-sync-status.sh esp-idf      just these
#   scripts/skill-sync-status.sh --diff       plus a diff of each drifted file, claude.ai -> repo
#   scripts/skill-sync-status.sh --quiet      only the skills not in sync, then a summary line
#
#   in-sync            same files, same contents
#   drifted            the files named differ
#   not-on-claude.ai   no synced copy under that name
#
# Before comparing, quotes around the frontmatter name and description values are
# stripped (claude.ai quotes them), a missing final newline is ignored, and
# __pycache__/, *.pyc and .DS_Store are skipped.
#
# Exit 1 if any skill is not in sync. Exit 0 with a note when there is no
# synced/ directory at all (claude.ai skill sync off, or it has not run yet).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_DIR

exec python3 - "$@" <<'PY'
import argparse
import difflib
import os
import re
import sys
from pathlib import Path

SKILLS = Path(os.environ["REPO_DIR"]) / "core" / "skills"
HOME = Path.home()
SYNCED = HOME / ".claude" / "skills" / "synced"

ap = argparse.ArgumentParser(prog="skill-sync-status.sh")
ap.add_argument("skills", nargs="*", help="skill directory names (default: all)")
ap.add_argument("--diff", action="store_true", help="show what differs, claude.ai -> repo")
ap.add_argument("-q", "--quiet", action="store_true", help="only skills not in sync, then a summary")
args = ap.parse_args()

all_skills = sorted(d.name for d in SKILLS.iterdir() if (d / "SKILL.md").is_file())
chosen = args.skills or all_skills
for s in chosen:
    if s not in all_skills:
        sys.exit(f"skill-sync-status: no core/skills/{s}")

if not SYNCED.is_dir():
    print("no ~/.claude/skills/synced: claude.ai skill sync is off or has not run; nothing to compare")
    sys.exit(0)
buckets = sorted(p for p in SYNCED.iterdir() if p.is_dir() and not p.name.startswith("."))


def tree(root):
    out = {}
    for p in root.rglob("*"):
        rel = p.relative_to(root)
        if "__pycache__" in rel.parts or p.name == ".DS_Store" or p.suffix == ".pyc":
            continue
        if p.is_file():
            out[rel.as_posix()] = p
    return out


def norm(rel, data):
    if not data.endswith(b"\n"):
        data += b"\n"
    if rel != "SKILL.md":
        return data
    lines = data.decode("utf-8", "replace").split("\n")
    if lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                break
            m = re.fullmatch(r"(name|description):\s*([\"'])(.*)\2\s*", lines[i])
            if m:
                v = m.group(3)
                v = v.replace("''", "'") if m.group(2) == "'" else re.sub(r'\\(["\\])', r"\1", v)
                lines[i] = f"{m.group(1)}: {v}"
    return "\n".join(lines).encode()


def compare(repo, synced):
    """-> (differing files as labels, diff text)"""
    a, b = tree(repo), tree(synced)
    labels, diff = [], []
    for rel in sorted(set(a) | set(b)):
        if rel not in b:
            labels.append(f"{rel} (repo only)")
            continue
        if rel not in a:
            labels.append(f"{rel} (claude.ai only)")
            continue
        new, old = norm(rel, a[rel].read_bytes()), norm(rel, b[rel].read_bytes())
        if new == old:
            continue
        labels.append(rel)
        if args.diff:
            diff += difflib.unified_diff(
                old.decode("utf-8", "replace").splitlines(True),
                new.decode("utf-8", "replace").splitlines(True),
                f"claude.ai/{repo.name}/{rel}", f"repo/{repo.name}/{rel}")
    return labels, "".join(diff)


tally = {"in-sync": 0, "drifted": 0, "not-on-claude.ai": 0}
for name in chosen:
    copies = [b / name for b in buckets if (b / name / "SKILL.md").is_file()]
    if not copies:
        state, detail, diff = "not-on-claude.ai", "", ""
    else:
        detail, diff = [], ""
        for c in copies:
            labels, d = compare(SKILLS / name, c)
            tag = f"[{c.parent.name[:8]}] " if len(buckets) > 1 and labels else ""
            detail += [tag + l for l in labels]
            diff += d
        state = "drifted" if detail else "in-sync"
        detail = ", ".join(detail)
    tally[state] += 1
    if args.quiet and state == "in-sync":
        continue
    print(f"{state:<17} {name:<24} {detail}".rstrip())
    if diff:
        print(diff.rstrip("\n"))

print(f"skill-sync-status: {len(chosen)} skill{'' if len(chosen) == 1 else 's'}, "
      + ", ".join(f"{v} {k}" for k, v in tally.items()))
if tally["drifted"] or tally["not-on-claude.ai"]:
    print("core/skills is the source: fold in any claude.ai-side edit worth keeping (--diff),\n"
          "then scripts/package-skills.sh <name> and upload the .skill in claude.ai")
    sys.exit(1)
PY
