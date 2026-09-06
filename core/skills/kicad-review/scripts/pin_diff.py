#!/usr/bin/env python3
"""Diff GPIO assignments between a KiCad netlist and a firmware pin header. Read-only, stdlib only.

    pin_diff.py --netlist review/board.net --header firmware/main/app_config.h --mcu U1
                [--pin-regex REGEX] [--io-regex REGEX] [--alias NAME=GPIO ...]
                [--reserved LIST] [--caution LIST] [--pinmap pad_to_gpio.csv]

Netlist: `kicad-cli sch export netlist --format kicadsexpr`. Only nodes whose (ref) equals --mcu are read.
The GPIO number of a node comes from, in order: an --alias for its pin name, the first --io-regex match on the
pin name (KiCad's RF_Module:ESP32-S3-WROOM-1 names pins IO4, IO12, ...), or --pinmap (CSV `pad,gpio`) by pad
number. Built-in aliases cover the WROOM-1 pins that carry no number: USB_D-=19 USB_D+=20 RXD0=44 TXD0=43.

Header: flat `#define NAME <int>` lines matched by --pin-regex (default: names starting with PIN_). Comments are
stripped; #if branches are not evaluated. Names are compared to net names by their `_`-separated tokens, case-
insensitive, either side a subset of the other (PIN_I2C_SDA matches /SDA; PIN_MOTOR_FR does not match /M1).

Verdicts, one row per GPIO:
  OK              header GPIO wired to a net whose name matches the header name
  NAME-MISMATCH   wired, but the net name does not match (warning)
  HEADER-ONLY     header GPIO has no net, or an `unconnected-` net, on the MCU (error)
  SCHEMATIC-ONLY  MCU GPIO on a named net that the header does not mention (info; `Net-(...)` auto names too)
  RESERVED        GPIO in --reserved (default 26-34: flash lines, never on a WROOM-1 pin) on either side (error)
  CAUTION         GPIO in --caution (default 0,3,19,20,35,36,37,43,44,45,46: strapping, USB, UART0, octal
                  PSRAM) on either side (warning; the module variant and the design note decide)
  DUPLICATE       two header names on one GPIO (warning)
  PINMAP-CLASH    two MCU pins map to one GPIO through --alias/--pinmap (error)

Exit 0: no error rows. 2: at least one error row. 1: misuse or a file that could not be parsed.
"""
import argparse
import re
import sys

DEFAULT_ALIASES = {"USB_D-": 19, "USB_D+": 20, "RXD0": 44, "TXD0": 43}


# ---------------------------------------------------------------- s-expressions
def tokenize(text):
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif c in "()":
            yield c
            i += 1
        elif c == '"':
            j = i + 1
            buf = []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                else:
                    buf.append(text[j])
                    j += 1
            yield "".join(buf)
            i = j + 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in "()":
                j += 1
            yield text[i:j]
            i = j


def parse(text):
    stack = [[]]
    for tok in tokenize(text):
        if tok == "(":
            stack.append([])
        elif tok == ")":
            node = stack.pop()
            stack[-1].append(node)
        else:
            stack[-1].append(tok)
    if len(stack) != 1:
        raise ValueError("unbalanced parentheses in netlist")
    return stack[0]


def child(node, key):
    for x in node:
        if isinstance(x, list) and x and x[0] == key:
            return x
    return None


def value(node, key, default=""):
    c = child(node, key)
    return c[1] if c and len(c) > 1 and not isinstance(c[1], list) else default


# ---------------------------------------------------------------- helpers
def parse_list(spec):
    out = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out.update(range(int(a), int(b) + 1))
        else:
            out.add(int(part))
    return out


def tokens(name):
    name = re.sub(r"^.*/", "", name)  # hierarchical path
    name = re.sub(r"^PIN_", "", name, flags=re.I)
    return set(t.lower() for t in re.split(r"[_\-. ]+", name) if t)


def names_match(header_name, net_name):
    h, n = tokens(header_name), tokens(net_name)
    if not h or not n:
        return False
    return h <= n or n <= h or "".join(sorted(h)) == "".join(sorted(n))


def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--netlist", required=True)
    ap.add_argument("--header", required=True)
    ap.add_argument("--mcu", required=True, help="reference designator of the MCU/module symbol, e.g. U1")
    ap.add_argument("--pin-regex", default=r"^\s*#define\s+(PIN_\w+)\s+\(?(\d+)\)?", help="two groups: name, gpio")
    ap.add_argument("--io-regex", default=r"IO(\d+)", help="one group: gpio number inside the pin name")
    ap.add_argument("--alias", action="append", default=[], help="PINNAME=GPIO, repeatable")
    ap.add_argument("--reserved", default="26-34")
    ap.add_argument("--caution", default="0,3,19,20,35,36,37,43,44,45,46")
    ap.add_argument("--pinmap", help="CSV pad,gpio for symbols whose pin names carry no GPIO number")
    a = ap.parse_args()

    aliases = dict(DEFAULT_ALIASES)
    for s in a.alias:
        k, _, v = s.rpartition("=")
        if not k or not v.strip().isdigit():
            sys.exit("bad --alias %r (want NAME=GPIO with an integer GPIO)" % s)
        aliases[k] = int(v)
    pinmap = {}
    if a.pinmap:
        try:
            for ln, line in enumerate(open(a.pinmap), 1):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = [x.strip() for x in line.split(",")]
                if len(parts) < 2 or not parts[1].isdigit():
                    sys.exit("bad --pinmap line %d: %r (want pad,gpio)" % (ln, line))
                pinmap[parts[0]] = int(parts[1])
        except OSError as e:
            sys.exit("cannot read pinmap: %s" % e)
    try:
        reserved, caution = parse_list(a.reserved), parse_list(a.caution)
    except ValueError:
        sys.exit("bad --reserved/--caution list (want e.g. 0,3,26-34)")
    try:
        io_re = re.compile(a.io_regex)
        pin_re = re.compile(a.pin_regex, re.M)
    except re.error as e:
        sys.exit("bad regex: %s" % e)
    if io_re.groups < 1:
        sys.exit("--io-regex needs one capturing group for the GPIO number")
    if pin_re.groups < 2:
        sys.exit("--pin-regex needs two capturing groups: name, gpio")

    # --- header
    try:
        src = strip_comments(open(a.header, encoding="utf-8", errors="replace").read())
    except OSError as e:
        sys.exit("cannot read header: %s" % e)
    header = {}  # gpio -> [names]
    for m in pin_re.finditer(src):
        if not m.group(2).isdigit():
            sys.exit("--pin-regex group 2 must capture an integer GPIO; got %r for %s" % (m.group(2), m.group(1)))
        header.setdefault(int(m.group(2)), []).append(m.group(1))
    if not header:
        sys.exit("no pins matched --pin-regex in %s" % a.header)

    # --- netlist
    try:
        tree = parse(open(a.netlist, encoding="utf-8", errors="replace").read())
    except (OSError, ValueError) as e:
        sys.exit("cannot parse netlist: %s" % e)
    root = tree[0] if tree and isinstance(tree[0], list) else None
    nets = child(root, "nets") if root else None
    if nets is None:
        sys.exit("no (nets ...) section: is this a kicadsexpr netlist?")

    refs_seen = set()
    mcu_nodes = []  # (pinname, pad, netname)
    for net in nets[1:]:
        if not isinstance(net, list) or net[0] != "net":
            continue
        netname = value(net, "name")
        for nd in net[1:]:
            if not isinstance(nd, list) or nd[0] != "node":
                continue
            ref = value(nd, "ref")
            refs_seen.add(ref)
            if ref == a.mcu:
                mcu_nodes.append((value(nd, "pinfunction"), value(nd, "pin"), netname))
    if not mcu_nodes:
        sys.exit("ref %s not in netlist; refs present: %s" % (a.mcu, ", ".join(sorted(refs_seen))[:300]))

    sch = {}  # gpio -> (pinname, netname)
    clashes = []  # (gpio, first pinname, second pinname)
    unmapped = []
    for pinname, pad, netname in mcu_nodes:
        gpio = None
        if pinname in aliases:
            gpio = aliases[pinname]
        else:
            m = io_re.search(pinname)
            if m:
                gpio = int(m.group(1))
            elif pad in pinmap:
                gpio = pinmap[pad]
        if gpio is None:
            unmapped.append("%s(pad %s)" % (pinname, pad))
            continue
        if gpio in sch:
            clashes.append((gpio, sch[gpio][0], pinname))
            continue
        sch[gpio] = (pinname, netname)
    if not sch:
        sys.exit("no pin of %s could be mapped to a GPIO number (pin names: %s). Pass --pinmap or --io-regex."
                 % (a.mcu, ", ".join(unmapped[:15])))

    def is_unconnected(netname):
        return netname == "" or netname.startswith("unconnected-")

    def is_auto(netname):
        return netname.startswith("Net-(")

    # --- verdicts
    rows = []  # (gpio, header_names, net, verdict, sev, note)
    for gpio in sorted(set(header) | set(sch)):
        hn = header.get(gpio, [])
        pinname, net = sch.get(gpio, ("", None))
        if hn and net is not None and not is_unconnected(net):
            if any(names_match(n, net) for n in hn) and not is_auto(net):
                rows.append((gpio, hn, net, "OK", "ok", pinname))
            elif is_auto(net):
                rows.append((gpio, hn, net, "NAME-MISMATCH", "warning", "connected but unlabeled; add a net label"))
            else:
                rows.append((gpio, hn, net, "NAME-MISMATCH", "warning", "rename the label or the define"))
        elif hn:
            rows.append((gpio, hn, net or "-", "HEADER-ONLY", "error",
                         "firmware uses it; MCU pin %s" % ("is unconnected" if net else "not in netlist")))
        elif net is not None and not is_unconnected(net):
            rows.append((gpio, [], net, "SCHEMATIC-ONLY", "info",
                         "unlabeled" if is_auto(net) else "not in header"))
        else:
            continue
        if len(hn) > 1:
            rows.append((gpio, hn, net or "-", "DUPLICATE", "warning", "two defines on one GPIO"))
        if gpio in reserved:
            rows.append((gpio, hn, net or "-", "RESERVED", "error", "flash/PSRAM line, not a usable GPIO"))
        elif gpio in caution:
            rows.append((gpio, hn, net or "-", "CAUTION", "warning",
                         "strapping/USB/UART0/octal-PSRAM pin: check esp32-s3-rules.md and the module variant"))

    for gpio, first, second in clashes:
        rows.append((gpio, header.get(gpio, []), sch[gpio][1], "PINMAP-CLASH", "error",
                     "pins %s and %s both map to GPIO %d: fix --alias/--pinmap" % (first, second, gpio)))
    rows.sort(key=lambda r: r[0])

    # --- print
    w = max([len(",".join(h)) for _, h, _, _, _, _ in rows] + [6])
    print("%-4s  %-*s  %-28s  %-14s  %s" % ("GPIO", w, "header", "net", "verdict", "note"))
    for gpio, hn, net, verdict, sev, note in rows:
        print("%-4d  %-*s  %-28s  %-14s  %s" % (gpio, w, ",".join(hn) or "-", (net or "-")[:28], verdict, note))
    if unmapped:
        print("unmapped %s pins (no GPIO number): %s" % (a.mcu, ", ".join(unmapped[:20])))
    counts = {"error": 0, "warning": 0, "info": 0}
    for r in rows:
        if r[4] in counts:
            counts[r[4]] += 1
    print("errors=%d warnings=%d info=%d  (header pins: %d, %s GPIO pins in netlist: %d)"
          % (counts["error"], counts["warning"], counts["info"], len(header), a.mcu, len(sch)))
    sys.exit(2 if counts["error"] else 0)


if __name__ == "__main__":
    main()
