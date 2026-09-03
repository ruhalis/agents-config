#!/usr/bin/env python
"""Bounded serial reader for Espressif boards, for use from tool calls.

Reads a port for a fixed number of seconds, prints what arrives, and exits.
`idf.py monitor` is interactive and never returns; this does. It needs
pyserial, which lives in the ESP-IDF venv: source ~/esp/esp-idf/export.sh
first and run this with that shell's `python`.

  serial_tail.py PORT [--seconds N] [--baud B] [--reset] [--until REGEX]
                      [--max-lines N]

  --reset      pulse EN through RTS so the boot log is captured from its
               first line. DTR is left deasserted, so IO0 stays high and the
               chip boots normally rather than into the ROM bootloader.
  --until      stop as soon as a line matches REGEX (exit 0); exit 2 if the
               deadline passes without a match
  --max-lines  stop after N lines so a chatty firmware cannot flood the
               caller (default 400)

Exit codes: 0 done (or --until matched), 1 port error, 2 --until not matched.

Prefer the UART bridge port (/dev/cu.usbserial-*, /dev/cu.SLAB_USBtoUART*,
/dev/cu.wchusbserial*).
The native USB-Serial-JTAG port (/dev/cu.usbmodem*) re-enumerates when the
chip resets, so --reset on it usually ends in a port error.
"""
import argparse
import re
import sys
import time

MAX_SECONDS = 60.0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("port", help="/dev/cu.usbserial-... (UART connector) or /dev/cu.usbmodem...")
    ap.add_argument("--seconds", type=float, default=15.0, help="how long to read (max 60)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--reset", action="store_true", help="reset the board first")
    ap.add_argument("--until", metavar="REGEX", help="stop early on a matching line")
    ap.add_argument("--max-lines", type=int, default=400, help="stop after this many lines")
    args = ap.parse_args()

    try:
        import serial
    except ImportError:
        sys.exit("pyserial not found: source ~/esp/esp-idf/export.sh and run with its `python`")

    seconds = min(max(args.seconds, 0.5), MAX_SECONDS)
    max_lines = max(args.max_lines, 1)
    try:
        pattern = re.compile(args.until) if args.until else None
    except re.error as exc:
        sys.exit(f"bad --until regex: {exc}")

    try:
        port = serial.Serial(args.port, args.baud, timeout=0.2)
    except serial.SerialException as exc:
        sys.exit(f"cannot open {args.port}: {exc}")

    lines = 0
    matched = False
    truncated = False
    started = time.monotonic()
    try:
        with port:
            if args.reset:
                # Devkit auto-reset circuit (same logic esptool uses for a hard
                # reset): with DTR deasserted, asserting RTS pulls EN low;
                # releasing RTS lets the chip boot with IO0 high.
                port.dtr = False
                port.rts = True
                time.sleep(0.1)
                port.reset_input_buffer()
                port.rts = False
            deadline = started + seconds
            buf = b""
            while time.monotonic() < deadline and not matched and not truncated:
                chunk = port.read(4096)
                if not chunk:
                    continue
                buf += chunk
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    text = raw.decode("utf-8", "replace").rstrip("\r")
                    print(text, flush=True)
                    lines += 1
                    if pattern and pattern.search(text):
                        matched = True
                        break
                    if lines >= max_lines:
                        truncated = True
                        break
            if buf and not matched and not truncated:
                # Final partial line (no newline yet): print it and still honour --until.
                text = buf.decode("utf-8", "replace").rstrip("\r")
                print(text, flush=True)
                lines += 1
                if pattern and pattern.search(text):
                    matched = True
    except serial.SerialException as exc:
        print(f"[serial_tail] port error after {lines} lines: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        pass

    elapsed = time.monotonic() - started
    if truncated:
        print(f"[serial_tail] stopped at --max-lines {max_lines} after {elapsed:.1f}s", file=sys.stderr)
    if pattern and not matched:
        print(
            f"[serial_tail] no match for {args.until!r} within {elapsed:.1f}s ({lines} lines)",
            file=sys.stderr,
        )
        return 2
    print(f"[serial_tail] {lines} lines in {elapsed:.1f}s", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
