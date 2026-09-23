#!/usr/bin/env python3
"""Bounded serial reader for Espressif boards, for use from tool calls.

Reads a port for a fixed number of seconds, prints what arrives, and exits.
`idf.py monitor` needs a terminal, so it cannot run from a tool call; this
can. It needs pyserial, which lives in the ESP-IDF venv: source
~/esp/esp-idf/export.sh first and run this with that shell's `python`.

  serial_tail.py PORT [-C DIR] [--seconds N] [--baud B] [--reset]
                      [--until REGEX] [--max-lines N]

  -C DIR       the project directory (default: the current one). Without
               --baud, the baud is its console baud: CONFIG_ESPTOOLPY_MONITOR_BAUD
               from DIR/sdkconfig, else DIR/build/config/sdkconfig.json, else
               115200. The first stderr line says which.
  --baud       use this baud instead
  --reset      pulse EN through RTS so the boot log is captured from its
               first line. DTR is left deasserted, so IO0 stays high and the
               chip boots normally rather than into the ROM bootloader.
  --until      stop as soon as a line matches REGEX (exit 0); exit 2 if the
               deadline passes without a match, 4 if an output cap ends the
               read first
  --max-lines  stop after N lines so a chatty firmware cannot flood the
               caller (default 400). Output is also capped at 64 KB in all,
               and each line at 512 bytes (the rest is cut and counted).

If the port drops mid-read (a native USB port re-enumerates on every reset),
the reader polls for the device node for up to 5 s (never past --seconds),
reopens it, prints "[serial_tail] port re-enumerated" in the log and keeps
reading. Whatever the board printed while the port was gone is lost.

Exit codes: 0 done (or --until matched), 1 port error (cannot open or reset
it, or it was lost and not back within 5 s or before --seconds ran out, or
lost more than 10 times), 2 deadline passed without an --until match,
3 usage or environment error (bad arguments, regex or -C directory, no
pyserial), 4 --max-lines or the 64 KB output cap reached before an --until
match.

Prefer the UART bridge port (/dev/cu.usbserial-*, /dev/cu.SLAB_USBtoUART*,
/dev/cu.wchusbserial*, or /dev/cu.usbmodem* for a CDC bridge such as the
CH343). Espressif's native USB-Serial-JTAG port (USB ID 303a:1001, also a
/dev/cu.usbmodem*) re-enumerates when the chip resets, so after --reset
there the boot lines printed before the reopen are missing.
"""
import argparse
import json
import os
import re
import sys
import termios
import time

MAX_SECONDS = 60.0
MAX_LINE = 512            # bytes kept per line
MAX_OUTPUT = 64 * 1024    # bytes printed to stdout in all
REOPEN_WAIT = 5.0         # seconds to wait for a lost port to come back
REOPEN_POLL = 0.1
MAX_REOPENS = 10          # a port that keeps dropping is a port error
DEFAULT_BAUD = 115200


class Parser(argparse.ArgumentParser):
    """argparse exits 2 on a usage error; 2 means "no --until match" here."""

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(3, f"{self.prog}: error: {message}\n")


def positive_int(text):
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError(f"must be positive: {text}")
    return value


def console_baud(project):
    """(baud, file it came from) from the project's generated config, else (None, None)."""
    cfg = os.path.join(project, "sdkconfig")
    try:
        with open(cfg, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r"CONFIG_ESPTOOLPY_MONITOR_BAUD=(\d+)\s*$", line)
                if m and int(m.group(1)) > 0:
                    return int(m.group(1)), cfg
    except OSError:
        pass
    js = os.path.join(project, "build", "config", "sdkconfig.json")
    try:
        with open(js, encoding="utf-8") as f:
            baud = json.load(f).get("ESPTOOLPY_MONITOR_BAUD")
        if type(baud) is int and baud > 0:
            return baud, js
    except (OSError, ValueError, AttributeError):
        pass
    return None, None


class Output:
    """Prints complete lines within the line, line-count and byte caps."""

    def __init__(self, pattern, max_lines):
        self.pattern = pattern
        self.max_lines = max_lines
        self.lines = 0
        self.bytes = 0
        self.matched = False
        self.capped = None      # which cap ended the read
        self.buf = bytearray()  # the current line, at most MAX_LINE bytes
        self.cut = 0            # bytes of the current line dropped past MAX_LINE

    @property
    def done(self):
        return self.matched or self.capped is not None

    def _print(self, text):
        size = len(text.encode("utf-8", "replace")) + 1
        if self.bytes + size > MAX_OUTPUT:
            self.capped = f"the {MAX_OUTPUT // 1024} KB output cap"
            return False
        print(text, flush=True)
        self.bytes += size
        return True

    def note(self, text):
        """An in-band marker: printed with the log, not counted as a line."""
        self._print(f"[serial_tail] {text}")

    def feed(self, chunk):
        while chunk and not self.done:
            nl = chunk.find(b"\n")
            part = chunk if nl < 0 else chunk[:nl]
            room = MAX_LINE - len(self.buf)
            self.buf += part[:max(room, 0)]
            self.cut += max(len(part) - max(room, 0), 0)
            if nl < 0:
                return
            chunk = chunk[nl + 1:]
            self._emit()

    def flush(self):
        """Emit a pending partial line (no newline yet), if there is one."""
        if self.buf or self.cut:
            self._emit()

    def _emit(self):
        """Print the current line and honour --until and the caps."""
        text = self.buf.decode("utf-8", "replace").rstrip("\r")
        if self.cut:
            text += f" [... {self.cut} bytes cut]"
        self.buf.clear()
        self.cut = 0
        if not self._print(text):
            return
        self.lines += 1
        if self.pattern and self.pattern.search(text):
            self.matched = True
        elif self.lines >= self.max_lines:
            self.capped = f"--max-lines {self.max_lines}"


def wait_for_port(serial, errors, path, baud, until):
    """Poll for the device node until `until`; (port, None) once it reopens, else (None, error)."""
    last = None
    while True:
        time.sleep(REOPEN_POLL)
        if os.path.exists(path):
            try:
                return serial.Serial(path, baud, timeout=0.2), None
            except errors as exc:
                last = exc
        if time.monotonic() >= until:
            return None, last


def main() -> int:
    try:
        sys.stdout.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass
    ap = Parser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("port", help="/dev/cu.usbserial-... (UART connector) or /dev/cu.usbmodem...")
    ap.add_argument("-C", "--project", metavar="DIR", help="project directory, for the console baud")
    ap.add_argument("--seconds", type=float, default=15.0, help="how long to read (max 60)")
    ap.add_argument("--baud", type=positive_int, help="override the project's console baud")
    ap.add_argument("--reset", action="store_true", help="reset the board first")
    ap.add_argument("--until", metavar="REGEX", help="stop early on a matching line")
    ap.add_argument("--max-lines", type=int, default=400, help="stop after this many lines")
    args = ap.parse_args()

    try:
        pattern = re.compile(args.until) if args.until else None
    except re.error as exc:
        print(f"bad --until regex: {exc}", file=sys.stderr)
        return 3
    project = args.project or os.getcwd()
    if not os.path.isdir(project):
        print(f"-C {project}: no such directory", file=sys.stderr)
        return 3
    try:
        import serial
    except ImportError:
        print("pyserial not found: source ~/esp/esp-idf/export.sh and run with its `python`", file=sys.stderr)
        return 3

    if args.baud:
        baud, source = args.baud, "--baud"
    else:
        baud, found = console_baud(project)
        if baud:
            source = f"CONFIG_ESPTOOLPY_MONITOR_BAUD in {found}"
        else:
            baud, source = DEFAULT_BAUD, f"default: no CONFIG_ESPTOOLPY_MONITOR_BAUD under {project}"
    print(f"[serial_tail] {baud} baud ({source})", file=sys.stderr, flush=True)

    seconds = min(max(args.seconds, 0.5), MAX_SECONDS)
    out = Output(pattern, max(args.max_lines, 1))
    # What a vanishing port raises: pyserial's own error, OSError from an
    # ioctl, and termios.error (not an OSError) from tcflush on a revoked fd.
    port_errors = (serial.SerialException, OSError, termios.error)

    try:
        port = serial.Serial(args.port, baud, timeout=0.2)
    except port_errors as exc:
        print(f"cannot open {args.port}: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"bad serial setting: {exc}", file=sys.stderr)
        return 3

    started = time.monotonic()
    deadline = started + seconds
    reopens = 0
    lost = None  # the error that took the port away, until it is back
    try:
        if args.reset:
            # Devkit auto-reset circuit (same logic esptool uses for a hard
            # reset): with DTR deasserted, asserting RTS pulls EN low;
            # releasing RTS lets the chip boot with IO0 high.
            pulsing = False
            try:
                port.dtr = False
                pulsing = True
                port.rts = True
                time.sleep(0.1)
                port.reset_input_buffer()
                port.rts = False
            except port_errors as exc:
                if not pulsing:  # no modem lines at all (a pty, some adapters)
                    print(f"cannot reset through {args.port}: {exc}", file=sys.stderr)
                    return 1
                lost = exc  # the reset took the port with it (native USB)
        while not out.done and time.monotonic() < deadline:
            if lost is None:
                try:
                    # Ask only for what is already buffered (or wait for one
                    # byte): pyserial drops what one read() call collected if
                    # the port fails before the call returns.
                    chunk = port.read(min(port.in_waiting, 4096) or 1)
                except port_errors as exc:
                    lost = exc
            if lost is not None:
                port.close()
                out.flush()
                if out.done:
                    break
                if reopens >= MAX_REOPENS:
                    print(f"[serial_tail] port lost again after {reopens} reopens: {lost}", file=sys.stderr)
                    return 1
                until = min(time.monotonic() + REOPEN_WAIT, deadline)
                port, err = wait_for_port(serial, port_errors, args.port, baud, until)
                if port is None:
                    why = f"; last open error: {err}" if err else ""
                    print(
                        f"[serial_tail] port lost after {out.lines} lines and not back within "
                        f"{REOPEN_WAIT:.0f} s or before --seconds ran out: {lost}{why}",
                        file=sys.stderr,
                    )
                    return 1
                lost = None
                reopens += 1
                out.note("port re-enumerated")
                continue
            if chunk:
                out.feed(chunk)
        if not out.done:
            # Final partial line (no newline yet): print it and still honour --until.
            out.flush()
    except KeyboardInterrupt:
        pass
    finally:
        if port is not None:
            port.close()

    elapsed = time.monotonic() - started
    again = f", {reopens} reopen{'s' if reopens != 1 else ''}" if reopens else ""
    if out.capped:
        print(f"[serial_tail] stopped at {out.capped} after {elapsed:.1f}s{again}", file=sys.stderr)
    if pattern and not out.matched:
        print(
            f"[serial_tail] no match for {args.until!r} within {elapsed:.1f}s ({out.lines} lines{again})",
            file=sys.stderr,
        )
        return 4 if out.capped else 2
    print(f"[serial_tail] {out.lines} lines in {elapsed:.1f}s{again}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
