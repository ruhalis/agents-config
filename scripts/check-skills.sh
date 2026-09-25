#!/usr/bin/env bash
# Lint the skills in core/skills. Needs only bash and python3's standard
# library, and changes no file.
#
#   scripts/check-skills.sh                   every skill, then the project references
#   scripts/check-skills.sh esp-idf isaac     just these skills (references too)
#   scripts/check-skills.sh --quiet           only the problems, then a summary line
#   scripts/check-skills.sh --no-refs         skip the project reference scan
#   scripts/check-skills.sh --refs-root DIR   scan DIR instead of ~/projects
#
# A skill FAILs on:
#   - frontmatter outside the Agent Skills spec: a key other than name, description,
#     license, compatibility, metadata, allowed-tools; a name that is not
#     ^[a-z0-9]+(-[a-z0-9]+)*$, is over 64 chars or is not the directory name; a
#     description that is empty, over 1024 chars, or holds < or > (skill-creator's
#     packager rejects those); compatibility over 500 chars; a metadata value that
#     is not a string; a plain value YAML would misread (": " or " #" inside)
#   - more than one SKILL.md
#   - a *.sh that fails bash -n, or a *.py that does not parse (neither is run)
#   - a scripts/*.py using argparse whose --help does not exit 0, or a scripts/*.sh
#     with a "usage:" line whose --help does not print it. These run in an empty
#     temp dir; a script with neither is only syntax-checked, never run.
#   - a bundled path SKILL.md names that does not exist: ${CLAUDE_SKILL_DIR}/<path>,
#     a backticked scripts/, references/, reference/, templates/ or assets/ path
#     when the skill has that directory, or the first column of a | File | table
#   - a file a script reads as ${SKILL_DIR}/<file> (the version pins) that is missing
# and warns, without failing, on __pycache__, *.pyc or .DS_Store inside a skill.
#
# Then every ~/.claude/skills/<name>/<path> in the *.md files under
# ~/projects must resolve in core/skills, since other repos call bundled scripts
# by those paths.
#
# Exit 1 if anything failed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_DIR

exec python3 - "$@" <<'PY'
import argparse
import ast
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(os.environ["REPO_DIR"])
SKILLS = REPO / "core" / "skills"
HOME = Path.home()
SPEC_KEYS = ["name", "description", "license", "compatibility", "metadata", "allowed-tools"]
NAME_RE = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
NOT_PACKAGED = {"__pycache__", "node_modules"}

ap = argparse.ArgumentParser(prog="check-skills.sh", description="Lint core/skills.")
ap.add_argument("skills", nargs="*", help="skill directory names (default: all)")
ap.add_argument("-q", "--quiet", action="store_true", help="print only problems and a summary")
ap.add_argument("--no-refs", action="store_true", help="skip the project reference scan")
ap.add_argument("--refs-root", default=str(HOME / "projects"), help="default: ~/projects")
args = ap.parse_args()


def tilde(p):
    s = str(p)
    return "~" + s[len(str(HOME)):] if s == str(HOME) or s.startswith(str(HOME) + os.sep) else s


# ---- a YAML subset: enough for SKILL.md frontmatter, not a YAML parser ----

KEY_RE = re.compile(r"([^\s:#][^:]*?)\s*:(?:\s+(.*))?$")
NOT_STR = [  # plain values YAML reads as something other than a string
    ("null", r"~|null|Null|NULL"),
    ("bool", r"true|True|TRUE|false|False|FALSE|yes|Yes|YES|no|No|NO|on|On|ON|off|Off|OFF"),
    ("int", r"[-+]?[0-9][0-9_]*|0o[0-7]+|0x[0-9a-fA-F]+"),
    ("float", r"[-+]?([0-9][0-9_]*)?\.[0-9][0-9_]*([eE][-+]?[0-9]+)?|[-+]?[0-9][0-9_]*\."
              r"|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN)"),
    ("date", r"[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}([Tt ].*)?"),
]


def dedent(lines):
    ind = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
    return [l[ind:] for l in lines]


def node(first, cont):
    """(value, type) for the text after 'key:' plus its indented continuation lines."""
    if first == "":
        if not any(l.strip() for l in cont):
            return None, "null"
        lines = dedent(cont)
        head = next(l for l in lines if l.strip())
        if head.startswith("- ") or head.strip() == "-":
            return lines, "list"
        return mapping(lines), "map"
    if first[0] in "|>":
        if not re.fullmatch(r"[|>]([-+]?[1-9]?|[1-9][-+])(\s+#.*)?", first):
            raise ValueError(f"bad block scalar header {first!r}")
        lines = dedent(cont) if any(l.strip() for l in cont) else []
        text = "\n".join(lines)
        if first[0] == ">":
            text = re.sub(r"(?<=[^\n])\n(?=[^\n])", " ", text)
        return text.rstrip("\n"), "str"
    text = " ".join(x for x in [first] + [l.strip() for l in cont] if x)
    m = re.fullmatch(r'"((?:[^"\\]|\\.)*)"\s*(#.*)?', text)
    if m:
        esc = {"n": "\n", "t": "\t"}
        return re.sub(r"\\(.)", lambda e: esc.get(e.group(1), e.group(1)), m.group(1)), "str"
    m = re.fullmatch(r"'((?:[^']|'')*)'\s*(#.*)?", text)
    if m:
        return m.group(1).replace("''", "'"), "str"
    if text[0] in "\"'":
        raise ValueError("quoted value does not end with its quote")
    if text[0] == "[":
        return text, "list"
    if text[0] == "{":
        return text, "map"
    if text[0] in "&*!%@`":
        raise ValueError(f"a plain value cannot start with {text[0]}; quote it")
    if ": " in text or text.endswith(":"):
        raise ValueError("plain value holds ': ', which YAML reads as a nested key; quote it or use >")
    if " #" in text:
        raise ValueError("plain value holds ' #', which YAML reads as a comment; quote it")
    for typ, rx in NOT_STR:
        if re.fullmatch(rx, text):
            return text, typ
    return text, "str"


def mapping(lines):
    out, i = {}, 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if line[0] in " \t":
            raise ValueError(f"unexpected indentation at {line.strip()[:40]!r}")
        m = KEY_RE.match(line)
        if not m:
            raise ValueError(f"not 'key: value': {line.strip()[:40]!r}")
        key, first = m.group(1), (m.group(2) or "").strip()
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or lines[j][0] in " \t"):
            j += 1
        if key in out:
            raise ValueError(f"duplicate key {key}")
        try:
            out[key] = node(first, lines[i + 1:j])
        except ValueError as e:
            raise ValueError(f"{key}: {e}") from None
        i = j
    return out


def frontmatter(text):
    lines = text.split("\n")
    if lines[0].rstrip() != "---":
        raise ValueError("SKILL.md does not open with a --- line")
    end = next((i for i in range(1, len(lines)) if lines[i].rstrip() == "---"), None)
    if end is None:
        raise ValueError("no closing --- line")
    return mapping(lines[1:end])


# ---- per-skill checks ----

def packaged(rel):
    """True if package-skills.sh (and skill-creator's packager) would include rel."""
    if any(p in NOT_PACKAGED for p in rel.parts[:-1]):
        return False
    return not (len(rel.parts) > 1 and rel.parts[0] == "evals")


def check_frontmatter(skill, text, fail):
    try:
        fm = frontmatter(text)
    except ValueError as e:
        fail(f"frontmatter: {e}")
        return
    for key in fm:
        if key not in SPEC_KEYS:
            fail(f"frontmatter: {key} is not a spec key (allowed: {', '.join(SPEC_KEYS)})")
    for key in ("name", "description"):
        if key not in fm:
            fail(f"frontmatter: no {key}")
    for key in ("name", "description", "license", "compatibility", "allowed-tools"):
        if key in fm and fm[key][1] != "str":
            fail(f"frontmatter: {key} must be a string, YAML reads it as {fm[key][1]}")
    name = fm.get("name", (None, ""))[0]
    if isinstance(name, str):
        if not NAME_RE.fullmatch(name) or len(name) > 64:
            fail(f"frontmatter: name {name!r} is not lowercase-hyphenated or is over 64 chars")
        if name != skill:
            fail(f"frontmatter: name {name!r} is not the directory name {skill!r}")
    desc = fm.get("description", (None, ""))[0]
    if isinstance(desc, str):
        n = len(desc.strip())
        if not 1 <= n <= 1024:
            fail(f"frontmatter: description is {n} chars (1-1024)")
        if "<" in desc or ">" in desc:
            fail("frontmatter: description holds < or >, which skill-creator's packager rejects")
    comp = fm.get("compatibility", (None, ""))[0]
    if isinstance(comp, str) and not 1 <= len(comp.strip()) <= 500:
        fail(f"frontmatter: compatibility is {len(comp.strip())} chars (1-500)")
    if "metadata" in fm:
        value, typ = fm["metadata"]
        if typ != "map":
            fail(f"frontmatter: metadata must be a string-to-string map, YAML reads it as {typ}")
        else:
            for k, (_, t) in value.items():
                if t != "str":
                    fail(f"frontmatter: metadata.{k} is {t}, must be a string (quote it)")


def bundled_paths(root, text):
    """Paths relative to the skill directory that SKILL.md names."""
    found = re.findall(r"\$\{CLAUDE_SKILL_DIR\}/([\w./-]+)", text)
    fence = table = False
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            fence = not fence
            continue
        if fence:
            continue
        if s.startswith("|"):
            first = s.strip("|").split("|")[0].strip()
            if re.fullmatch(r"Files?", first):
                table = True
            elif table and re.fullmatch(r"`[^`\s<>*]+`", first):
                found.append(first[1:-1])
        else:
            table = False
        # only for dirs the skill has: `reference/x.js` may be a project path
        found += [p for p in re.findall(r"`((?:scripts|references|reference|templates|assets)/[^`\s<>*]+)`", line)
                  if (root / p.split("/")[0]).is_dir()]
    return sorted({p.rstrip(".,;:") for p in found})


def run(cmd, cwd):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    try:
        r = subprocess.run(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=20)
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return None, "timed out after 20 s"


def check_skill(skill):
    """-> (status, summary, [(level, message)])"""
    root = SKILLS / skill
    problems = []
    fail = lambda m: problems.append(("FAIL", m))
    warn = lambda m: problems.append(("warn", m))
    md = root / "SKILL.md"
    if not md.is_file():
        fail("no SKILL.md")
        return "FAIL", "", problems
    text = md.read_text(errors="replace")
    check_frontmatter(skill, text, fail)

    files = sorted(p for p in root.rglob("*") if p.is_file())
    rels = [p.relative_to(root) for p in files]
    extra = [r for r in rels if r.name == "SKILL.md" and packaged(r) and r != Path("SKILL.md")]
    if extra:
        fail(f"more than one SKILL.md: {', '.join(map(str, extra))}")

    parsed = 0
    for p, r in zip(files, rels):
        if not packaged(r):
            continue
        if p.suffix == ".sh":
            code, out = run(["bash", "-n", str(p)], root)
            parsed += 1
            if code != 0:
                fail(f"{r}: bash -n: {out.strip().splitlines()[0] if out.strip() else code}")
        elif p.suffix == ".py":
            parsed += 1
            try:
                ast.parse(p.read_bytes(), filename=str(r))
            except SyntaxError as e:
                fail(f"{r}:{e.lineno}: does not parse: {e.msg}")

    helped = 0
    scripts = root / "scripts"
    with tempfile.TemporaryDirectory() as tmp:
        for p in sorted(scripts.glob("*")) if scripts.is_dir() else []:
            if not p.is_file():
                continue
            src = p.read_text(errors="replace")
            if p.suffix == ".py" and "argparse" in src:
                code, out = run([sys.executable, "-B", str(p), "--help"], tmp)
                helped += 1
                if code != 0:
                    tail = out.strip()[-120:]
                    fail(f"scripts/{p.name} --help exited {code}" + (f": {tail}" if tail else ""))
            elif p.suffix == ".sh" and re.search(r"\busage:", src, re.I):
                code, out = run(["bash", str(p), "--help"], tmp)
                helped += 1
                if not re.search(r"\busage:", out, re.I):
                    fail(f"scripts/{p.name} --help printed no usage: line (exit {code})")

    paths = bundled_paths(root, text)
    for rel in paths:
        if not (root / rel).exists():
            fail(f"SKILL.md names {rel}, which does not exist")

    pins = set()
    for p in sorted(scripts.glob("*")) if scripts.is_dir() else []:
        if p.is_file():
            for rel in re.findall(r"\$\{?SKILL_DIR\}?/([\w.-][\w./-]*)", p.read_text(errors="replace")):
                pins.add(rel)
                if not (root / rel).exists():
                    fail(f"scripts/{p.name} reads {rel}, which does not exist")

    for p, r in zip(files, rels):
        if p.name == ".DS_Store" or (p.suffix == ".pyc" and "__pycache__" not in r.parts):
            warn(f"stray {r} (git and package-skills.sh skip it; safe to delete)")
    for d in sorted(root.rglob("__pycache__")):
        warn(f"stray {d.relative_to(root)}/ (git and package-skills.sh skip it; safe to delete)")

    summary = f"{parsed} files parsed, {helped} --help runs, {len(paths)} bundled paths, {len(pins)} read by scripts"
    status = "FAIL" if any(l == "FAIL" for l, _ in problems) else "warn" if problems else "ok"
    return status, summary, problems


# ---- references from other repos ----

REF_RE = re.compile(r"(?:~|\$HOME|\$\{HOME\}|/Users/[^/\s`'\"]+)/\.claude/skills/"
                    r"([\w.-]+)((?:/[\w.@+-]*)*)")
PRUNE = {".git", "node_modules", ".venv", "venv", "__pycache__", "build", "managed_components"}


def scan_refs(root, names):
    ok, bad = 0, []
    files = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in PRUNE)
        for fn in sorted(filenames):
            if not fn.endswith(".md"):
                continue
            p = Path(dirpath) / fn
            try:
                lines = p.read_text(errors="replace").split("\n")
            except OSError:
                continue
            for n, line in enumerate(lines, 1):
                for m in REF_RE.finditer(line):
                    name, rest = m.groups()
                    ref = m.group(0).rstrip(".")
                    rest = rest.rstrip(".").strip("/")
                    if name.startswith(".") or name == "synced":
                        continue
                    if name not in names:
                        bad.append(f"{tilde(p)}:{n} {ref}: no core/skills/{name}")
                        continue
                    files.add(p)
                    if rest and not (SKILLS / name / rest).exists():
                        bad.append(f"{tilde(p)}:{n} {ref}: no {rest} in core/skills/{name}")
                    else:
                        ok += 1
    return ok, bad, len(files)


# ---- main ----

all_skills = sorted(d.name for d in SKILLS.iterdir() if d.is_dir() and not d.name.startswith("."))
chosen = args.skills or all_skills
unknown = [s for s in chosen if s not in all_skills]
if unknown:
    sys.exit(f"check-skills: no core/skills/{unknown[0]}")

counts = {"ok": [], "warn": [], "FAIL": []}
for skill in chosen:
    status, summary, problems = check_skill(skill)
    counts[status].append(skill)
    if args.quiet and status == "ok":
        continue
    print(f"{status:<5} {skill:<24} {summary}")
    for level, msg in problems:
        print(f"        {level}: {msg}")

refs_note = ""
if not args.no_refs:
    root = Path(args.refs_root).expanduser()
    if not root.is_dir():
        refs_note = f"; no {tilde(root)}, references not checked"
    else:
        ok, bad, nfiles = scan_refs(root, set(all_skills))
        if bad:
            counts["FAIL"].append("project refs")
            print(f"{'FAIL':<5} {'project refs':<24} {len(bad)} of {ok + len(bad)} skill paths under {tilde(root)} do not resolve")
            for b in bad:
                print(f"        FAIL: {b}")
        elif not args.quiet:
            print(f"{'ok':<5} {'project refs':<24} {ok} skill paths in {nfiles} files under {tilde(root)} resolve")
        refs_note = f"; project refs {'FAIL' if bad else 'ok'}"

failed = [s for s in counts["FAIL"] if s != "project refs"]
print(f"check-skills: {len(chosen)} skill{'' if len(chosen) == 1 else 's'}, {len(counts['ok'])} ok, {len(counts['warn'])} warn, "
      f"{len(failed)} FAIL{' (' + ', '.join(failed) + ')' if failed else ''}{refs_note}")
sys.exit(1 if counts["FAIL"] else 0)
PY
