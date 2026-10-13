#!/usr/bin/env bash
set -euo pipefail

# Report, and optionally purge, developer caches on this Mac.
#
#   scripts/cleanup.sh                 report cache sizes, change nothing
#   scripts/cleanup.sh --purge         clear the safe caches (brew, npm, uv, Go, yarn, pnpm, Xcode DerivedData, unavailable simulators)
#   scripts/cleanup.sh --purge-heavy   also Docker images and model weights, each confirmed first
#   scripts/cleanup.sh --purge-heavy --yes   no confirmations
#   scripts/cleanup.sh --dry-run --purge     print what would run
#
# Not part of install.sh; run it by hand. Informational entries (~/Library/Caches,
# ~/.cache, logs, Trash, simulators, ~/.npm, ~/.docker, the Homebrew cache) are
# only ever reported, never deleted.

DRY_RUN=0
PURGE=0
HEAVY=0
YES=0
TOTAL_KB=0

# ---------------------------------------------------------------- output ----

if [ -t 1 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; YEL=$'\033[33m'; RED=$'\033[31m'; RST=$'\033[0m'
else
    B=""; DIM=""; YEL=""; RED=""; RST=""
fi

step() { printf '\n%s==> %s%s\n' "$B" "$1" "$RST"; }
say()  { printf '    %s\n' "$1"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RST"; }
warn() { printf '    %s! %s%s\n' "$YEL" "$1" "$RST" >&2; }
die()  { printf '%serror: %s%s\n' "$RED" "$1" "$RST" >&2; exit 1; }

usage() { awk 'NR == 1 { next } /^#/ { seen = 1; sub(/^# ?/, ""); print; next } seen { exit }' "${BASH_SOURCE[0]}"; exit 0; }

# ------------------------------------------------------------ primitives ----

# Every deletion goes through run() so --dry-run is airtight.
run() {  # run <command> [args...]
    if [ "$DRY_RUN" = 1 ]; then
        say "would run: $*"
    else
        say "run: $*"
        "$@" || warn "failed: $*"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

confirm() {  # confirm <question> — true when --yes or the user answers y
    [ "$YES" = 1 ] && return 0
    local ans
    read -r -p "    $1 [y/N] " ans || return 1
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# size <label> <path> [count] — print the size of a path; add to the total when count is set.
size() {
    local label="$1" path="$2" count="${3:-}" kb
    if [ ! -e "$path" ]; then
        note "$(printf '%-32s' "$label") not present"
        return 0
    fi
    kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}') || true
    kb=${kb:-0}
    say "$(printf '%-32s %8s  %s' "$label" "$(du -sh "$path" 2>/dev/null | awk '{print $1}')" "$path")"
    if [ -n "$count" ]; then TOTAL_KB=$((TOTAL_KB + kb)); fi
}

# ------------------------------------------------------------------ args ----

for arg in "$@"; do
    case "$arg" in
        --purge)       PURGE=1 ;;
        --purge-heavy) PURGE=1; HEAVY=1 ;;
        --yes)         YES=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        -h|--help)     usage ;;
        *)             die "unknown option: $arg (try --help)" ;;
    esac
done

# ---------------------------------------------------------------- report ----

step "Safe caches (--purge)"
if have brew; then size "Homebrew" "$(brew --cache 2>/dev/null)" count; else note "brew not installed"; fi
if have npm;  then size "npm" "$(npm config get cache 2>/dev/null)" count; else note "npm not installed"; fi
if have uv;   then size "uv" "$(uv cache dir 2>/dev/null)" count; else note "uv not installed"; fi
size "pip" "$HOME/Library/Caches/pip" count
size "Arduino staging" "$HOME/Library/Arduino15/staging" count
size "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData" count
if have go;   then size "Go build cache" "$(go env GOCACHE 2>/dev/null)" count; else note "go not installed"; fi
if have yarn; then size "yarn" "$(yarn cache dir 2>/dev/null)" count; else note "yarn not installed"; fi
if have pnpm; then size "pnpm store" "$(pnpm store path 2>/dev/null)" count; else note "pnpm not installed"; fi

step "Expensive to rebuild (--purge-heavy)"
size "Hugging Face" "$HOME/.cache/huggingface" count
size "PyTorch" "$HOME/.cache/torch" count
size "ModelScope" "$HOME/.cache/modelscope" count
size "Xcode iOS DeviceSupport" "$HOME/Library/Developer/Xcode/iOS DeviceSupport" count
if have docker; then note "Docker images: see 'docker system df'"; else note "docker not installed"; fi

step "Informational (never deleted)"
size "~/Library/Caches" "$HOME/Library/Caches"
size "~/.cache" "$HOME/.cache"
size "~/Library/Logs" "$HOME/Library/Logs"
size "~/.Trash" "$HOME/.Trash"
size "CoreSimulator devices" "$HOME/Library/Developer/CoreSimulator/Devices"
size "~/.npm" "$HOME/.npm"
size "~/.docker" "$HOME/.docker"
size "Docker disk image" "$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
size "Ollama models (ollama rm)" "$HOME/.ollama/models"
size "conda pkgs (conda clean --all)" "$HOME/miniforge3/pkgs"
size "ESP-IDF dist archives" "$HOME/.espressif/dist"
if have brew; then size "Homebrew cache (brew --cache)" "$(brew --cache 2>/dev/null)"; fi

step "Total"
say "reclaimable by --purge and --purge-heavy: $(awk -v k="$TOTAL_KB" 'BEGIN { printf "%.1f GB", k / 1048576 }')"
note "informational entries are not counted"

[ "$PURGE" = 1 ] || exit 0

# ----------------------------------------------------------------- purge ----

step "Purging safe caches$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"
if have brew; then run brew cleanup --prune=all; else note "skip brew: not installed"; fi
if have npm;  then run npm cache clean --force;  else note "skip npm: not installed"; fi
if have uv;   then run uv cache clean;           else note "skip uv: not installed"; fi
run rm -rf "$HOME/Library/Caches/pip"
run rm -rf "$HOME/Library/Arduino15/staging"
run rm -rf "$HOME/Library/Developer/Xcode/DerivedData"
if have xcrun && xcrun --find simctl >/dev/null 2>&1; then run xcrun simctl delete unavailable; else note "skip simctl: Xcode not installed"; fi
if have go;   then run go clean -cache;          else note "skip go: not installed"; fi
if have yarn; then run yarn cache clean;         else note "skip yarn: not installed"; fi
if have pnpm; then run pnpm store prune;         else note "skip pnpm: not installed"; fi

[ "$HEAVY" = 1 ] || exit 0

step "Purging heavy caches$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"
if ! have docker; then
    note "skip docker: not installed"
elif ! docker info >/dev/null 2>&1; then
    note "skip docker: daemon not running"
elif confirm "Docker: remove ALL unused images, stopped containers, networks and build cache?"; then
    run docker system prune -a -f
else
    note "skip docker: declined"
fi
for p in "$HOME/.cache/huggingface" "$HOME/.cache/torch" "$HOME/.cache/modelscope" "$HOME/Library/Developer/Xcode/iOS DeviceSupport"; do
    if [ ! -e "$p" ]; then note "skip ${p/#$HOME/~}: not present"
    elif confirm "Delete ${p/#$HOME/~}?"; then run rm -rf "$p"
    else note "skip ${p/#$HOME/~}: declined"
    fi
done
