#!/usr/bin/env python3
"""Check, record and compare JLCPCB fab sets written by fab_export.sh. Stdlib only; never writes a project file.

    fabset.py check <outdir> <stem> <copper_count>
    fabset.py manifest <outdir> --pcb <board.kicad_pcb> --sch <root.kicad_sch> --kicad <version>
                       --copper <F.Cu,...,B.Cu> --checks pass|FAIL
    fabset.py diff <old_outdir> <new_outdir>

check     The file-set checks fab_export.sh runs after plotting, here so scripts/selftest.sh can run them without
          kicad-cli: gerber/ holds exactly the layer files the job file lists (one per requested layer function)
          plus drill, drill map and job file; no BOM designator range; every BOM designator with an LCSC number
          has a CPL row. CPL-only designators (fiducials, logos) are listed, not failed. Prints the counts for the
          pre-order table in references/jlcpcb-order.md.
manifest  Writes <outdir>/MANIFEST.txt: sha256 of the board, schematic sheets, .kicad_pro and .kicad_dru and of the
          uploaded files, the kicad-cli version, the git revision and dirty flag when the board is tracked, the
          copper layers, the drill tool table (slots apart from round holes), and the ERC/DRC/pin_diff counts found
          in <board>/review/ ("not run" when absent, "STALE" when older than a file they depend on, board.net
          included for the pin diff). Sheets are the root sheet and every sheet it references. Nothing is re-run.
diff      Compares two fab sets: bom.csv by designator (ranges expanded, a range-format change reported on its
          own), cpl.csv by designator and field, every gerber/ file line by line with timestamp lines stripped (G04
          comments, %TF.CreationDate, the drill header's date, the job file's CreationDate), drill holes by
          diameter and function (tool numbers shift). When both sets hold a MANIFEST.txt its source sha256 lines
          are compared for information; they do not change the exit code. Ends with `identical except ...`.

Exit: check 0 every check passed, 1 a check failed. manifest 0 written. diff 0 identical except timestamp lines,
2 the sets differ. Any subcommand: 1 on misuse or input it could not read.
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter, OrderedDict


class Parser(argparse.ArgumentParser):
    def error(self, message):  # argparse exits 2, which diff uses for "the sets differ"; misuse is 1
        self.print_usage(sys.stderr)
        sys.exit("%s: error: %s" % (self.prog, message))


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


def show(refs):
    refs = sorted(refs, key=natural)
    return ", ".join(refs) if refs else "none"


# ---------------------------------------------------------------- check
def cmd_check(out, stem, ncu):
    bad = False
    try:
        # Gerber set. Layer files are named after the layer's user name (a renamed In1.Cu plots as <stem>-GND.g1),
        # so the expected names come from the job file kicad-cli wrote: one file per requested layer by function,
        # and the directory holds exactly those plus drill, drill map and job file.
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
            "SolderPaste,Top", "SolderPaste,Bot", "Legend,Top", "Legend,Bot", "SolderMask,Top", "SolderMask,Bot",
            "Profile"]
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
              % (len(rows), len(bom_refs), len(missing_lcsc),
                 (": " + "; ".join(missing_lcsc)[:200]) if missing_lcsc else ""))
        if ranges:
            print("FAIL bom designator ranges (JLC does not expand them): %s" % ", ".join(ranges))
            bad = True

        # BOM designator set against CPL designator set, both directions. A BOM designator with an LCSC number and
        # no CPL row is a part JLC will not place: failure. CPL-only designators are footprints excluded from the
        # BOM (KiCad's stock fiducials carry exclude_from_bom): listed for the user to explain.
        cpl = list(csv.DictReader(open(os.path.join(out, "cpl.csv"), newline="")))
        cpl_refs = set(r["Designator"] for r in cpl)
        print("bom vs cpl designators: in BOM not CPL: %s; in CPL not BOM (board-only, excluded from BOM: fiducials, "
              "logos): %s" % (show(bom_refs - cpl_refs), show(cpl_refs - bom_refs)))
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
    except (OSError, KeyError, csv.Error) as e:
        print("FAIL fab set unreadable: %s" % e)
        return 1
    return 1 if bad else 0


# ---------------------------------------------------------------- shared readers
def drill_tools(path):
    """OrderedDict tool -> [diameter, holes, slots, function] from a KiCad Excellon file; units from the header.
    A slot (an oval hole) is one G85 line, or one M15 of a routed slot, and is counted apart from round holes."""
    tools, func, cur, header, units = OrderedDict(), "", None, True, "mm"
    for line in open(path, errors="replace"):
        s = line.strip()
        if header:
            if s.startswith("; #@! TA.AperFunction,"):
                func = s.split(",", 1)[1]
            elif s.startswith("INCH"):
                units = "in"
            m = re.match(r"^T(\d+)C([0-9.]+)", s)
            if m:
                tools["T" + m.group(1)] = [float(m.group(2)), 0, 0, func]
                func = ""
            if s in ("%", "M95"):
                header = False
            continue
        m = re.match(r"^T(\d+)$", s)
        if m:
            cur = "T" + m.group(1)
        elif cur in tools and (s == "M15" or "G85" in s):
            tools[cur][2] += 1
        elif cur in tools and re.match(r"^X-?[0-9.]+Y-?[0-9.]+", s):
            tools[cur][1] += 1
    return tools, units


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 16), b""):
            h.update(block)
    return h.hexdigest()


# ---------------------------------------------------------------- manifest
def git_state(board_dir, files):
    """The board's git revision, and DIRTY with the files when any of `files` (the board and every sheet it
    references, wherever they sit) is modified or untracked. Paths go to git relative to the work-tree root, so a
    sheet in a subdirectory or a sibling directory of the board counts too; they print as the board directory
    sees them (`sub/child.kicad_sch`, `../common/pwr.kicad_sch`). A sheet outside the work tree is named, not
    judged."""
    def git(cwd, *args):
        try:
            r = subprocess.run(["git", "-C", cwd, "--no-optional-locks"] + list(args),
                               capture_output=True, text=True)
        except OSError:
            return None, ""
        return r.returncode, r.stdout.rstrip("\n")  # porcelain lines start with a meaningful space
    rc, top = git(board_dir, "rev-parse", "--show-toplevel")
    if rc is None:
        return "git not found"
    if rc != 0:
        return "not a git work tree"
    # git resolves symlinks in --show-toplevel (/tmp is /private/tmp on macOS); resolve the files the same way.
    inside, outside = {}, []
    for f in files:
        p = os.path.relpath(os.path.realpath(f), top)
        name = os.path.relpath(f, board_dir)
        if p == os.pardir or p.startswith(os.pardir + os.sep):
            outside.append(name)
        else:
            inside[p] = name
    note = "; outside this work tree: %s" % ", ".join(outside) if outside else ""
    tracked = [p for p in inside if git(top, "ls-files", "--error-unmatch", "--", p)[0] == 0]
    if not tracked:
        first = next(iter(inside.values()), outside[0] if outside else "the board")
        return "not tracked (repo %s does not track %s)%s" % (top, first, note)
    _, rev = git(top, "rev-parse", "--short=12", "HEAD")
    _, st = git(top, "status", "--porcelain", "--untracked-files=all", "--", *inside)
    dirty = []
    for ln in st.splitlines():
        if len(ln) <= 3:
            continue
        p = ln[3:].split(" -> ")[-1].strip('"')  # work-tree relative; a rename prints old -> new
        dirty.append(inside.get(p, p) + (" (untracked)" if ln.startswith("??") else " (modified)"))
    if dirty:
        return "%s DIRTY: %s; this set is from the working copy, not %s%s" % (rev, ", ".join(dirty), rev, note)
    return "%s clean%s" % (rev, note)


def review_counts(review, sheets, pcb, settings):
    """Counts from review/, each stamped STALE when a file it depends on is newer: ERC on the sheets and project
    settings, DRC on the board, the sheets (parity) and settings, the pin diff on the sheets and review/board.net
    (the pin header is not known here)."""
    netlist = os.path.join(review, "board.net")
    deps = {"erc": sheets + settings, "drc": [pcb] + sheets + settings, "pin": sheets + [netlist]}

    def stamp(path, sources):
        t = os.path.getmtime(path)
        when = datetime.datetime.fromtimestamp(t).isoformat(timespec="seconds")
        newer = [os.path.relpath(s, os.path.dirname(review)) for s in sources
                 if os.path.exists(s) and os.path.getmtime(s) > t]
        return "%s, %s%s" % (os.path.basename(path), when,
                             ", STALE: older than %s" % ", ".join(newer) if newer else "")

    def sev(rows):
        c = Counter(v.get("severity", "?") if isinstance(v, dict) else "?" for v in rows)
        order = ["error", "warning", "exclusion"] + sorted(k for k in c if k not in ("error", "warning", "exclusion"))
        return " ".join("%s=%d" % (k, c[k]) for k in order if c[k]) or "clean"

    lines = []
    p = os.path.join(review, "erc.json")
    try:
        d = json.load(open(p))
        rows = [v for s in d.get("sheets", []) for v in s.get("violations", [])]
        lines.append("  erc:          %s  (%s)" % (sev(rows), stamp(p, deps["erc"])))
    except FileNotFoundError:
        lines.append("  erc:          not run (no %s)" % p)
    except (OSError, ValueError, AttributeError, TypeError) as e:
        lines.append("  erc:          unreadable %s: %s" % (p, e))
    for name in ("drc.json", "drc_refilled.json"):
        p = os.path.join(review, name)
        label = "drc:" if name == "drc.json" else "drc refilled:"
        try:
            d = json.load(open(p))
            rows = [v for k in ("violations", "unconnected_items", "schematic_parity") for v in d.get(k, [])]
            lines.append("  %-13s %s, unconnected=%d, parity=%d  (%s)"
                         % (label, sev(rows), len(d.get("unconnected_items", [])),
                            len(d.get("schematic_parity", [])), stamp(p, deps["drc"])))
        except FileNotFoundError:
            lines.append("  %-13s not run (no %s)" % (label, p))
        except (OSError, ValueError, AttributeError, TypeError) as e:
            lines.append("  %-13s unreadable %s: %s" % (label, p, e))
    p = os.path.join(review, "pin_diff.txt")
    try:
        m = None
        for line in open(p, errors="replace"):
            m = re.match(r"errors=\d+ warnings=\d+ info=\d+", line) or m
        lines.append("  pin_diff:     %s  (%s)" % (m.group(0) if m else "no summary line", stamp(p, deps["pin"])))
    except FileNotFoundError:
        lines.append("  pin_diff:     not run (no %s)" % p)
    except OSError as e:
        lines.append("  pin_diff:     unreadable %s: %s" % (p, e))
    return lines


def sheet_tree(root, project_dir):
    """(sheets found, sheets referenced but missing): the root sheet and every sheet it references, recursively.
    A (property "Sheetfile" ...) path ("Sheet file" in older files) is taken relative to the sheet that holds it,
    as kicad-happy reads it, else relative to the project directory."""
    found, missing, todo = [], [], [os.path.abspath(root)]
    prop = re.compile(r'\(property\s+"Sheet ?file"\s+"((?:[^"\\]|\\.)*)"')
    while todo:
        s = todo.pop(0)
        if s in found:
            continue
        found.append(s)
        try:
            text = open(s, errors="replace").read()
        except OSError:
            continue
        for ref in prop.findall(text):
            ref = ref.replace("\\\\", "\\").replace('\\"', '"')
            cands = [os.path.normpath(os.path.join(os.path.dirname(s), ref)),
                     os.path.normpath(os.path.join(project_dir, ref))]
            hit = next((c for c in cands if os.path.isfile(c)), None)
            if hit:
                todo.append(hit)
            elif cands[0] not in missing:
                missing.append(cands[0])
    return found, missing


def cmd_manifest(out, pcb, sch, kicad, copper, checks):
    board_dir = os.path.dirname(os.path.abspath(pcb))
    stem = os.path.splitext(os.path.basename(pcb))[0]
    sheets, lost = sheet_tree(sch, board_dir)
    extra = [os.path.join(board_dir, stem + ext) for ext in (".kicad_pro", ".kicad_dru")]
    sources = [os.path.abspath(pcb)] + sheets + lost + extra
    uploads = [os.path.join(out, f) for f in ("gerbers.zip", "bom.csv", "cpl.csv")]

    lines = ["%s fab set" % stem,
             "written:      %s by fab_export.sh" % datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
             "board:        %s" % os.path.abspath(pcb),
             "kicad-cli:    %s" % kicad,
             "git:          %s" % git_state(board_dir, [s for s in sources if os.path.exists(s)]),
             "fab checks:   %s" % ("pass" if checks == "pass" else "FAIL: do not upload this set"),
             "sha256, sources:"]
    for s in sources:
        rel = os.path.relpath(s, board_dir)
        lines.append("  %s  %s" % (sha256(s) if os.path.exists(s) else "%-64s" % "none", rel))
    lines.append("sha256, uploads:")
    for u in uploads:
        lines.append("  %s  %s" % (sha256(u) if os.path.exists(u) else "%-64s" % "none", os.path.basename(u)))
    cu = [c for c in copper.split(",") if c]
    lines.append("copper layers: %d (%s)" % (len(cu), ", ".join(cu)))
    drl = os.path.join(out, "gerber", stem + ".drl")
    try:
        tools, units = drill_tools(drl)
        lines.append("drill tools (gerber/%s):" % os.path.basename(drl))
        for t, (dia, holes, slots, func) in tools.items():
            n = " + ".join(x for x in ("%d" % holes if holes else "", "%d slots" % slots if slots else "") if x)
            lines.append("  %-4s %6.3f %s  x%-9s %s" % (t, dia, units, n or "0", func))
        lines.append("  holes: %d, slots: %d" % (sum(v[1] for v in tools.values()), sum(v[2] for v in tools.values())))
    except OSError as e:
        lines.append("drill tools: unreadable %s" % e)
    review = os.path.join(board_dir, "review")
    lines.append("review (%s, as last written there; fab_export.sh does not re-run them):" % review)
    lines += review_counts(review, sheets, os.path.abspath(pcb), extra)
    dst = os.path.join(out, "MANIFEST.txt")
    with open(dst, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("manifest: %s" % dst)
    return 0


# ---------------------------------------------------------------- diff
def strip_stamps(name, text):
    """(kept lines, stripped count): lines that only carry a timestamp or a G04 comment are dropped."""
    kept, n = [], 0
    for line in text.splitlines():
        s = line.strip()
        if name.endswith(".drl"):
            drop = s.startswith("; DRILL file") or "TF.CreationDate" in s
        elif name.endswith(".gbrjob"):
            drop = '"CreationDate"' in s
        else:
            drop = s.startswith("G04") or s.startswith("%TF.CreationDate")
        if drop:
            n += 1
        else:
            kept.append(line)
    return kept, n


RANGE = re.compile(r"^([A-Z]+)([0-9]+)-([A-Z]*)([0-9]+)$")


def by_designator(path, bom):
    """(designator -> row dict, range tokens). A BOM row is split into its designators, a range (C10-C15, as an
    older export wrote them) into its members, so a set that only changed its designator format compares equal
    by content and the format change is reported on its own."""
    out, ranges = OrderedDict(), []
    for r in csv.DictReader(open(path, newline="")):
        refs = [t.strip() for t in (r.get("Designator") or "").split(",") if t.strip()] if bom else [r.get("Designator", "")]
        for ref in refs:
            m = RANGE.match(ref) if bom else None
            if m and (not m.group(3) or m.group(3) == m.group(1)):
                ranges.append(ref)
                members = ["%s%d" % (m.group(1), i) for i in range(int(m.group(2)), int(m.group(4)) + 1)]
            else:
                members = [ref]
            for x in members:
                out[x] = {k: v for k, v in r.items() if k not in ("Designator", "Quantity")}
    return out, ranges


def diff_rows(name, a, b):
    notes = []
    gone, new = [k for k in a if k not in b], [k for k in b if k not in a]
    if gone:
        notes.append("removed %s" % show(gone))
    if new:
        notes.append("added %s" % show(new))
    for k in sorted(set(a) & set(b), key=natural):
        ch = ["%s %s -> %s" % (f, a[k].get(f, ""), b[k].get(f, "")) for f in sorted(set(a[k]) | set(b[k]))
              if a[k].get(f, "") != b[k].get(f, "")]
        if ch:
            notes.append("%s: %s" % (k, "; ".join(ch)))
    return notes


def cmd_diff(old, new):
    for d in (old, new):
        if not os.path.isdir(os.path.join(d, "gerber")) and not os.path.isfile(os.path.join(d, "bom.csv")):
            sys.exit("%s is not a fab set (no gerber/ and no bom.csv)" % d)
    print("fab_diff: %s -> %s" % (old, new))
    differ, same, stripped = [], 0, 0
    for name in ("bom.csv", "cpl.csv"):
        pa, pb = os.path.join(old, name), os.path.join(new, name)
        if not (os.path.exists(pa) and os.path.exists(pb)):
            if os.path.exists(pa) or os.path.exists(pb):
                differ.append(name)
                print("%-34s only in %s" % (name, old if os.path.exists(pa) else new))
            continue
        try:
            (ra, xa), (rb, xb) = by_designator(pa, name == "bom.csv"), by_designator(pb, name == "bom.csv")
        except (OSError, csv.Error) as e:
            sys.exit("cannot read %s: %s" % (name, e))
        notes = diff_rows(name, ra, rb)
        if xa != xb:
            notes.append("designator ranges (JLC does not expand them) %s -> %s" % (show(xa), show(xb)))
        if notes:
            differ.append(name)
            print("%-34s %d difference(s): %s" % (name, len(notes), " | ".join(notes)[:1500]))
        else:
            same += 1

    ga, gb = os.path.join(old, "gerber"), os.path.join(new, "gerber")
    fa = set(os.listdir(ga)) if os.path.isdir(ga) else set()
    fb = set(os.listdir(gb)) if os.path.isdir(gb) else set()
    for name in sorted(fa | fb, key=natural):
        if name not in fa or name not in fb:
            differ.append(name)
            print("%-34s only in %s" % (name, old if name in fa else new))
            continue
        try:
            ka, na = strip_stamps(name, open(os.path.join(ga, name), errors="replace").read())
            kb, nb = strip_stamps(name, open(os.path.join(gb, name), errors="replace").read())
        except OSError as e:
            sys.exit("cannot read %s: %s" % (name, e))
        stripped += na + nb
        if ka == kb:
            same += 1
            continue
        differ.append(name)
        ca, cb = Counter(ka), Counter(kb)
        print("%-34s %d line(s) only in old, %d only in new (%d vs %d lines)"
              % (name, sum((ca - cb).values()), sum((cb - ca).values()), len(ka), len(kb)))
        if name.endswith(".drl"):
            # by diameter and hole function, not tool number: KiCad renumbers tools when a diameter comes or goes
            def by_size(path):
                tools, units = drill_tools(path)
                c = Counter()
                for dia, holes, slots, func in tools.values():
                    c["%.3f %s %s" % (dia, units, func)] += holes
                    c["%.3f %s %s, slots" % (dia, units, func)] += slots
                return +c
            sa, sb = by_size(os.path.join(ga, name)), by_size(os.path.join(gb, name))
            for k in sorted(set(sa) | set(sb)):
                if sa.get(k) != sb.get(k):
                    print("  drill %s: %s -> %s" % (k, "x%d" % sa[k] if k in sa else "none",
                                                  "x%d" % sb[k] if k in sb else "none"))

    ma, mb = os.path.join(old, "MANIFEST.txt"), os.path.join(new, "MANIFEST.txt")
    if os.path.exists(ma) and os.path.exists(mb):
        def src(p):
            rows, on = {}, False
            for line in open(p, errors="replace"):
                if line.startswith("sha256, "):
                    on = line.startswith("sha256, sources")
                elif on and line.startswith("  "):
                    h, _, f = line.strip().partition("  ")
                    rows[f.strip()] = h
            return rows
        sa, sb = src(ma), src(mb)
        ch = [f for f in sorted(set(sa) | set(sb)) if sa.get(f) != sb.get(f)]
        # information only: an edit no fab file shows (a note on an unplotted layer) still changes the hash
        print("%-34s %s" % ("sources (MANIFEST.txt sha256)",
                            "differ: %s (information; the outputs above decide)" % ", ".join(ch) if ch else "same"))

    print("same: %d file(s); ignored %d G04-comment and timestamp line(s) (%%TF.CreationDate, drill header date, "
          "job CreationDate)" % (same, stripped))
    if differ:
        print("identical except: %s" % ", ".join(differ))
        return 2
    print("identical except timestamps and G04 comments")
    return 0


# ---------------------------------------------------------------- main
def main():
    ap = Parser(prog="fabset.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True, parser_class=Parser)
    c = sub.add_parser("check", help="file-set checks after fab_export.sh plots")
    c.add_argument("outdir")
    c.add_argument("stem", help="board file name stem, as in <stem>.drl")
    c.add_argument("copper_count", type=int)
    m = sub.add_parser("manifest", help="write <outdir>/MANIFEST.txt")
    m.add_argument("outdir")
    m.add_argument("--pcb", required=True)
    m.add_argument("--sch", required=True)
    m.add_argument("--kicad", required=True, help="kicad-cli version string")
    m.add_argument("--copper", required=True, help="comma-separated copper layers, F.Cu first")
    m.add_argument("--checks", required=True, choices=["pass", "FAIL"])
    d = sub.add_parser("diff", help="compare two fab sets")
    d.add_argument("old")
    d.add_argument("new")
    a = ap.parse_args()
    if a.cmd == "check":
        if not os.path.isdir(a.outdir):
            sys.exit("no such directory: %s" % a.outdir)
        sys.exit(cmd_check(a.outdir, a.stem, a.copper_count))
    if a.cmd == "manifest":
        for p in (a.outdir, a.pcb, a.sch):
            if not os.path.exists(p):
                sys.exit("no such file or directory: %s" % p)
        sys.exit(cmd_manifest(a.outdir, a.pcb, a.sch, a.kicad, a.copper, a.checks))
    sys.exit(cmd_diff(a.old, a.new))


if __name__ == "__main__":
    main()
