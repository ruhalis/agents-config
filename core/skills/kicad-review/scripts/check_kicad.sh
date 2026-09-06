#!/usr/bin/env bash
# Read-only status of KiCad on this Mac. Never installs anything.
# Exit 0: kicad-cli usable at the pinned major. Exit 1: KiCad missing, a different major, or no python3.
# A patch/minor version that differs from the pin is reported as a WARNING, not a failure.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "${SKILL_DIR}/kicad-version" 2>/dev/null || echo unknown)"
APP="${KICAD_APP:-/Applications/KiCad/KiCad.app}"
CLI="${APP}/Contents/MacOS/kicad-cli"
status=0
have=unknown

echo "pinned:      ${PIN}"

if [[ -x "${CLI}" ]]; then
  have="$("${CLI}" version 2>/dev/null | head -n 1 | tr -d '[:space:]')"
  [[ -n "${have}" ]] || have=unknown
  if [[ "${have}" == "${PIN}" ]]; then
    echo "kicad-cli:   ${have} at ${CLI}"
  elif [[ "${have%%.*}" == "${PIN%%.*}" ]]; then
    echo "kicad-cli:   ${have} at ${CLI} — WARNING: differs from pin ${PIN} (bump kicad-version deliberately, then re-run the scripts on a known project)"
  else
    echo "kicad-cli:   ${have} at ${CLI} — FAIL: major differs from pin ${PIN}; the JSON and netlist shapes the scripts parse are per-major"
    status=1
  fi
else
  echo "kicad-cli:   NOT FOUND at ${CLI} — KiCad is installed from kicad.org as an app bundle; never brew install it unasked"
  status=1
fi

if command -v python3 >/dev/null 2>&1; then
  pyv="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo unknown)"
  case "${pyv}" in
    3.[0-9].*) echo "python3:     ${pyv} at $(command -v python3) — FAIL: scripts need >= 3.10"; status=1 ;;
    *)         echo "python3:     ${pyv} at $(command -v python3)" ;;
  esac
else
  echo "python3:     MISSING — the bundled scripts need a system python3 >= 3.10"
  status=1
fi

# Informational only: the IPC API server (KiCad > Preferences > Plugins). This skill never uses it.
if [[ "${have}" != unknown ]]; then
  prefs="${HOME}/Library/Preferences/kicad/${have%.*}/kicad_common.json"
  if [[ -f "${prefs}" ]]; then
    api="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("api",{}).get("enable_server","unset"))' "${prefs}" 2>/dev/null || echo unreadable)"
    echo "ipc api:     enable_server=${api} (${prefs}; unused by this skill)"
  else
    echo "ipc api:     no ${prefs} yet (KiCad has not been opened at this version)"
  fi
fi

# kicad-happy: optional third-party review plugin (Claude Code marketplace). Present or not, nothing here changes.
if [[ -d "${HOME}/.claude/plugins/marketplaces/kicad-happy" ]] || ls -d "${HOME}"/.claude/plugins/cache/kicad-happy* >/dev/null 2>&1; then
  echo "kicad-happy: installed as a Claude Code plugin"
else
  echo "kicad-happy: not installed (optional; README at github.com/aklofas/kicad-happy)"
fi

# KiCad projects under the working directory, depth 4, skipping build trees.
projects="$(find . -maxdepth 4 -name '*.kicad_pro' \
  -not -path '*/build/*' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*-backups/*' \
  2>/dev/null | sed 's|^\./||' | tr '\n' ' ')"
echo "projects:    ${projects:-none under $(pwd) (depth 4)}"

exit "${status}"
