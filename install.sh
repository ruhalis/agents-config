#!/usr/bin/env bash
set -euo pipefail

# Install this repo's agent config into Claude Code, Codex, and/or Cursor, and
# its extension list into VS Code.
#
#   ./install.sh                    install into every tool detected on this machine
#   ./install.sh codex              install into one tool
#   ./install.sh claude cursor      install into several
#   ./install.sh vscode             install the VS Code extensions that are missing
#   ./install.sh all                install into all tools, detected or not
#   ./install.sh --dry-run all      print the plan, change nothing
#   ./install.sh --project ~/repo cursor
#                                   write project-level Cursor rules into a repo
#
# Layout:
#   core/          tool-agnostic source of truth (orchestration doc, agents, skills)
#   adapters/<t>/  per-tool routing tail and settings; adapters/vscode/extensions.txt
#   build/         generated, gitignored; installed files symlink here

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_DIR/build"
BACKUP_ROOT="$HOME/.agent-config-backups/$(date +%Y%m%d-%H%M%S)"

DRY_RUN=0
PROJECT_DIR=""
TOOLS=()

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

# Every filesystem mutation goes through these so --dry-run is airtight.

mk() {  # mk <dir>
    [ "$DRY_RUN" = 1 ] || mkdir -p "$1"
}

link() {  # link <src> <dst>
    say "link $2 -> ${1#"$REPO_DIR"/}"
    [ "$DRY_RUN" = 1 ] || { mkdir -p "$(dirname "$2")"; ln -sfn "$1" "$2"; }
}

copy() {  # copy <src> <dst>
    say "copy $2"
    [ "$DRY_RUN" = 1 ] || { mkdir -p "$(dirname "$2")"; cp "$1" "$2"; }
}

# emit <dst> — write stdin to dst. Always consumes stdin so callers behave
# identically under --dry-run.
emit() {
    local dst="$1" content
    content=$(cat)
    if [ "$DRY_RUN" = 1 ]; then
        note "generate $dst ($(printf '%s\n' "$content" | wc -l | tr -d ' ') lines)"
    else
        mkdir -p "$(dirname "$dst")"
        printf '%s\n' "$content" > "$dst"
    fi
}

# backup <path> <label> — move an existing real file/dir out of the way.
# Symlinks into this repo are ours; drop them silently, they get recreated.
backup() {
    local path="$1" label="$2"
    [ -e "$path" ] || [ -L "$path" ] || return 0
    if [ -L "$path" ]; then
        case "$(readlink "$path")" in
            "$REPO_DIR"/*|"$BUILD_DIR"/*) [ "$DRY_RUN" = 1 ] || rm "$path"; return 0 ;;
        esac
    fi
    say "backup $path -> $BACKUP_ROOT/$label/"
    [ "$DRY_RUN" = 1 ] || {
        mkdir -p "$BACKUP_ROOT/$label"
        mv "$path" "$BACKUP_ROOT/$label/$(basename "$path")"
    }
}

# sweep_dir <dir> <label> — make dir mirror the repo exactly: everything not
# ours is backed up. ONLY for directories this repo owns outright (Claude's).
# Never use on ~/.codex/skills or ~/.cursor/skills: those hold tool-bundled and
# third-party skills that this repo has no business deleting.
sweep_dir() {
    local dir="$1" label="$2" entry
    [ -d "$dir" ] || return 0
    for entry in "$dir"/* "$dir"/.[!.]*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        backup "$entry" "$label"
    done
}

# reconcile_dir <dir> — the safe counterpart for shared directories: remove only
# stale symlinks pointing back into this repo, leave everything else alone.
reconcile_dir() {
    local dir="$1" entry
    [ -d "$dir" ] || return 0
    for entry in "$dir"/*; do
        [ -L "$entry" ] || continue
        case "$(readlink "$entry")" in
            "$REPO_DIR"/*|"$BUILD_DIR"/*)
                [ "$DRY_RUN" = 1 ] || rm "$entry" ;;
        esac
    done
}

# ------------------------------------------------- frontmatter extraction ----

# fm_field <file> <key> — value of a top-level frontmatter key, empty if absent.
fm_field() {
    awk -v want="$2" '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { exit }
        fm {
            i = index($0, ":")
            if (i == 0) next
            k = substr($0, 1, i - 1); v = substr($0, i + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", k)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (k == want) { print v; exit }
        }
    ' "$1"
}

# fm_body <file> — everything after the closing frontmatter delimiter, with the
# leading blank line dropped. Counts only the first two "---" lines, so
# horizontal rules in the body survive.
fm_body() {
    awk 'n >= 2 { if (!started && !NF) next; started = 1; print; next } /^---$/ { n++ }' "$1"
}

# ------------------------------------------------------------- composing ----

# compose <tool> — core orchestration doc + that tool's routing tail.
compose() {
    local tool="$1" routing="$REPO_DIR/adapters/$1/routing.md"
    [ -f "$routing" ] || die "missing $routing"
    printf '<!-- Generated by install.sh — do not edit.\n'
    printf '     Sources: core/orchestration.md + adapters/%s/routing.md -->\n\n' "$tool"
    cat "$REPO_DIR/core/orchestration.md"
    printf '\n'
    cat "$routing"
}

# --------------------------------------------------------- agent codegen ----

# Claude's agent format is the richest, so core/agents/*.md is written in it and
# the other tools are derived. Read-only intent is derived from the tools list
# rather than a separate field: no Edit/Write means the agent only advises.
agent_is_readonly() {
    case "$(fm_field "$1" tools)" in
        *Edit*|*Write*) return 1 ;;
        *) return 0 ;;
    esac
}

# Cursor: same markdown shape, but only name and description are specified
# fields. Strip Claude-only keys rather than betting on them being ignored.
gen_agent_cursor() {
    local src="$1"
    printf -- '---\n'
    printf 'name: %s\n' "$(fm_field "$src" name)"
    printf 'description: %s\n' "$(fm_field "$src" description)"
    printf -- '---\n\n'
    fm_body "$src"
}

# Codex: TOML, body becomes developer_instructions, read-only intent becomes an
# enforced sandbox_mode.
gen_agent_codex() {
    local src="$1" model sandbox
    model=$(fm_field "$src" model)
    if agent_is_readonly "$src"; then sandbox="read-only"; else sandbox="workspace-write"; fi

    printf '# Generated by install.sh from core/agents/%s — do not edit.\n\n' "$(basename "$src")"
    printf 'name = "%s"\n' "$(fm_field "$src" name | toml_str)"
    printf 'description = "%s"\n' "$(fm_field "$src" description | toml_str)"
    case "$model" in
        sonnet|haiku) printf 'model = "%s"\n' "$CODEX_FAST_MODEL" ;;
        "") : ;;  # no model field: inherit the session model
        *) warn "unmapped model '$model' in $(basename "$src"); inheriting session model" ;;
    esac
    printf 'model_reasoning_effort = "high"\n'
    printf 'sandbox_mode = "%s"\n' "$sandbox"
    printf 'developer_instructions = """\n'
    fm_body "$src" | toml_block
    printf '"""\n'
}

# TOML string escaping. Basic strings process backslash escapes, so backslashes
# double; multi-line strings additionally must not contain a bare triple quote.
toml_str()   { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
toml_block() { sed -e 's/\\/\\\\/g' -e 's/"""/\\"\\"\\"/g'; }

# ----------------------------------------------------------------- tools ----

install_claude() {
    local dir="$HOME/.claude"
    step "Claude Code -> $dir"
    mk "$dir"

    # statusline (submodule; Claude-only feature)
    backup "$dir/statusline" claude
    link "$REPO_DIR/statusline" "$dir/statusline"
    [ "$DRY_RUN" = 1 ] || chmod +x "$REPO_DIR/statusline/statusline.sh"

    # instructions
    compose claude | emit "$BUILD_DIR/claude/CLAUDE.md"
    backup "$dir/CLAUDE.md" claude
    link "$BUILD_DIR/claude/CLAUDE.md" "$dir/CLAUDE.md"

    # agents — core format is Claude format, so these link straight through
    mk "$dir/agents"
    sweep_dir "$dir/agents" claude/agents
    local f
    for f in "$REPO_DIR"/core/agents/*.md; do
        [ -e "$f" ] || continue
        link "$f" "$dir/agents/$(basename "$f")"
    done

    # skills
    mk "$dir/skills"
    sweep_dir "$dir/skills" claude/skills
    local d
    for d in "$REPO_DIR"/core/skills/*/; do
        [ -d "$d" ] || continue
        link "${d%/}" "$dir/skills/$(basename "$d")"
    done

    # settings and keybindings are copies: Claude rewrites settings.json in
    # place (theme, model picker), and a symlink would push that into the repo.
    backup "$dir/settings.json" claude
    copy "$REPO_DIR/adapters/claude/settings.json" "$dir/settings.json"
    backup "$dir/keybindings.json" claude
    copy "$REPO_DIR/adapters/claude/keybindings.json" "$dir/keybindings.json"
}

install_codex() {
    local dir="$HOME/.codex"
    step "Codex -> $dir"
    mk "$dir"
    # shellcheck disable=SC1091
    . "$REPO_DIR/adapters/codex/models.env"

    codex_capability_check

    # instructions
    compose codex | emit "$BUILD_DIR/codex/AGENTS.md"
    backup "$dir/AGENTS.md" codex
    link "$BUILD_DIR/codex/AGENTS.md" "$dir/AGENTS.md"

    # subagents (TOML)
    mk "$dir/agents"
    reconcile_dir "$dir/agents"
    local f name
    for f in "$REPO_DIR"/core/agents/*.md; do
        [ -e "$f" ] || continue
        name=$(fm_field "$f" name)
        gen_agent_codex "$f" | emit "$BUILD_DIR/codex/agents/$name.toml"
        link "$BUILD_DIR/codex/agents/$name.toml" "$dir/agents/$name.toml"
    done

    # skills — shared directory, tool-bundled skills live here too. Reconcile,
    # never sweep.
    mk "$dir/skills"
    reconcile_dir "$dir/skills"
    local d
    for d in "$REPO_DIR"/core/skills/*/; do
        [ -d "$d" ] || continue
        link "${d%/}" "$dir/skills/$(basename "$d")"
    done

    merge_codex_config "$dir/config.toml"
}

# Merge our managed keys into an existing config.toml without disturbing the
# rest of it (theme, per-project trust_level, mcp_servers).
merge_codex_config() {
    local target="$1" src="$REPO_DIR/adapters/codex/config.toml"
    local begin='# >>> claude-config managed >>>'
    local end='# <<< claude-config managed <<<'
    local keys merged managed

    managed=$(grep -E '^[a-z_]+[[:space:]]*=' "$src" || true)
    [ -n "$managed" ] || { warn "no managed keys in adapters/codex/config.toml"; return 0; }
    keys=$(printf '%s\n' "$managed" | sed -E 's/[[:space:]]*=.*//' | paste -sd'|' -)

    if [ -f "$target" ]; then
        say "backup $target -> $BACKUP_ROOT/codex/"
        [ "$DRY_RUN" = 1 ] || { mkdir -p "$BACKUP_ROOT/codex"; cp "$target" "$BACKUP_ROOT/codex/config.toml"; }
    fi

    merged=$(
        {
            printf '%s\n%s\n%s\n' "$begin" "$managed" "$end"
            if [ -f "$target" ]; then
                printf '\n'
                # drop a previous managed block, then comment out any surviving
                # top-level duplicate of a key we now own (TOML rejects dupes)
                awk -v b="$begin" -v e="$end" '
                    $0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }
                ' "$target" |
                awk -v keys="$keys" '
                    BEGIN { n = split(keys, k, "|") }
                    /^[[:space:]]*\[/ { tables = 1 }
                    {
                        if (!tables) {
                            for (i = 1; i <= n; i++) {
                                if ($0 ~ "^[[:space:]]*" k[i] "[[:space:]]*=") {
                                    print "# superseded by claude-config: " $0
                                    next
                                }
                            }
                        }
                        print
                    }
                '
            fi
        } | awk 'NF || prev { print } { prev = NF }'  # collapse blank runs
    )
    printf '%s\n' "$merged" | emit "$target"
    say "merged managed block into $target"
}

# Resolve the real Codex executable. `codex` on PATH is usually a Node wrapper
# that re-execs a platform binary shipped in a per-arch sub-package, and that
# layout has already changed once between releases — so search rather than
# hardcode a path.
codex_binary() {
    local bin pkg
    bin=$(command -v codex 2>/dev/null) || return 1
    bin=$(readlink -f "$bin" 2>/dev/null || printf '%s' "$bin")
    # A native binary has no shebang; anything else is a wrapper to look behind.
    if ! head -c 2 "$bin" 2>/dev/null | grep -q '#!'; then
        printf '%s\n' "$bin"; return 0
    fi
    pkg=$(cd "$(dirname "$bin")/.." 2>/dev/null && pwd) || return 1
    find "$pkg" -type f -name codex -perm -u+x -size +1M 2>/dev/null | head -1
}

# The Codex feature surface moved fast; an older binary silently ignores agents
# and skills. Check rather than let the user assume it took effect.
codex_capability_check() {
    local bin ver
    command -v codex >/dev/null 2>&1 || { note "codex not on PATH; installing files anyway"; return 0; }
    ver=$(codex --version 2>/dev/null | head -1 || true)
    note "detected ${ver:-codex (version unknown)}"

    bin=$(codex_binary || true)
    if [ -z "$bin" ] || [ ! -f "$bin" ]; then
        note "could not locate the Codex binary; skipping the capability check"
        return 0
    fi

    # grep -q straight at the binary: it exits on the first hit, so the common
    # (supported) case is instant. Never buffer `strings` output into a variable
    # here — on a ~200MB binary that is hundreds of megabytes of shell string.
    grep -qaF 'developer_instructions' "$bin" 2>/dev/null || \
        warn "this Codex build has no subagent support — ~/.codex/agents/*.toml will be ignored. Upgrade: npm i -g @openai/codex@latest"
    grep -qaF 'SKILL.md' "$bin" 2>/dev/null || \
        warn "this Codex build has no skills support — ~/.codex/skills/ will be ignored. Upgrade: npm i -g @openai/codex@latest"
}

install_cursor() {
    local dir="$HOME/.cursor"
    step "Cursor -> $dir"
    mk "$dir"

    # subagents — same markdown shape as Claude, minus the Claude-only keys
    mk "$dir/agents"
    reconcile_dir "$dir/agents"
    local f name
    for f in "$REPO_DIR"/core/agents/*.md; do
        [ -e "$f" ] || continue
        name=$(fm_field "$f" name)
        gen_agent_cursor "$f" | emit "$BUILD_DIR/cursor/agents/$name.md"
        link "$BUILD_DIR/cursor/agents/$name.md" "$dir/agents/$name.md"
    done

    # skills — shared directory; reconcile, never sweep
    mk "$dir/skills"
    reconcile_dir "$dir/skills"
    local d
    for d in "$REPO_DIR"/core/skills/*/; do
        [ -d "$d" ] || continue
        link "${d%/}" "$dir/skills/$(basename "$d")"
    done

    # Cursor keeps User Rules inside the app, with no file to install to. Best
    # available: generate the text and put it on the clipboard to paste once.
    compose cursor | emit "$BUILD_DIR/cursor/USER_RULES.md"
    if [ "$DRY_RUN" = 0 ] && command -v pbcopy >/dev/null 2>&1; then
        pbcopy < "$BUILD_DIR/cursor/USER_RULES.md"
        note "orchestration doc copied to clipboard"
    fi
    warn "Cursor has no file-based global rules. Paste the clipboard (or build/cursor/USER_RULES.md) into Settings -> Rules -> User Rules. Re-paste after changing core/orchestration.md."
    note "for a specific repo instead: ./install.sh --project <path> cursor"
}

install_cursor_project() {
    local proj="$1"
    [ -d "$proj" ] || die "not a directory: $proj"
    proj="$(cd "$proj" && pwd)"
    step "Cursor project rules -> $proj"

    local rule="$proj/.cursor/rules/orchestration.mdc"
    backup "$rule" "cursor-project"
    {
        printf -- '---\n'
        printf 'description: Orchestration model — plan, decompose, delegate to subagents, synthesize.\n'
        printf 'alwaysApply: true\n'
        printf -- '---\n\n'
        compose cursor
    } | emit "$rule"
    say "wrote $rule"
    note "commit it to share with the repo, or add .cursor/rules/orchestration.mdc to .git/info/exclude"
}

# --------------------------------------------------------------- vscode ----

# VS Code's CLI. `code` is only on PATH after "Shell Command: Install 'code'
# command in PATH" from the Command Palette; fall back to the macOS app bundle.
vscode_cli() {
    local c
    if c=$(command -v code 2>/dev/null); then printf '%s\n' "$c"; return 0; fi
    c="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
    return 1
}

# Normalise an extension list (stdin) to one lowercase ID per line, sorted, so
# the lists can be diffed with comm. Marketplace IDs are case-insensitive and
# `--list-extensions` prints them lowercase. Strips comments and blank lines.
ext_ids() {
    awk '{ sub(/#.*/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print tolower($0) }' | sort -u
}

install_vscode() {
    local list="$REPO_DIR/adapters/vscode/extensions.txt" code
    step "VS Code extensions"
    [ -f "$list" ] || die "missing $list"
    code=$(vscode_cli) || {
        warn "VS Code CLI not found; skipping. Install VS Code, then run \"Shell Command: Install 'code' command in PATH\" from the Command Palette."
        return 0
    }
    note "using $code"

    local wanted have missing extra
    wanted=$(ext_ids < "$list")
    have=$("$code" --list-extensions 2>/dev/null | ext_ids)
    missing=$(comm -23 <(printf '%s\n' "$wanted") <(printf '%s\n' "$have"))
    extra=$(comm -13 <(printf '%s\n' "$wanted") <(printf '%s\n' "$have"))

    if [ -z "$missing" ]; then
        note "all $(printf '%s\n' "$wanted" | wc -l | tr -d ' ') extensions already installed"
    else
        local args=() id
        while IFS= read -r id; do
            say "install $id"
            args+=(--install-extension "$id")
        done <<< "$missing"
        if [ "$DRY_RUN" = 0 ]; then
            # One invocation: every `code` launch costs a second or two. A
            # marketplace failure must not abort the rest of the install; the
            # re-check below reports what did not land.
            "$code" "${args[@]}" 2>&1 | sed 's/^/      /' || true
            missing=$(comm -23 <(printf '%s\n' "$wanted") <("$code" --list-extensions 2>/dev/null | ext_ids))
            [ -z "$missing" ] || warn "not installed: $(printf '%s' "$missing" | tr '\n' ' ')"
        fi
    fi
    # Report, never remove: the list is what a fresh machine should get, not a
    # ban on installing anything else.
    [ -z "$extra" ] || note "installed here but not in extensions.txt: $(printf '%s' "$extra" | tr '\n' ' ')"
}

# ------------------------------------------------------------------ main ----

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --project) shift; [ $# -gt 0 ] || die "--project needs a path"; PROJECT_DIR="$1" ;;
        all) TOOLS=(claude codex cursor vscode) ;;
        claude|codex|cursor|vscode) TOOLS+=("$1") ;;
        -*) die "unknown flag: $1 (try --help)" ;;
        *) die "unknown tool: $1 (expected claude, codex, cursor, vscode, or all)" ;;
    esac
    shift
done

if [ ${#TOOLS[@]} -eq 0 ]; then
    for t in claude codex cursor; do
        if command -v "$t" >/dev/null 2>&1 || [ -d "$HOME/.$t" ]; then TOOLS+=("$t"); fi
    done
    if vscode_cli >/dev/null 2>&1 || [ -d "$HOME/.vscode" ]; then TOOLS+=(vscode); fi
    [ ${#TOOLS[@]} -gt 0 ] || die "no supported tool detected; name one explicitly (claude|codex|cursor|vscode)"
    note "detected: ${TOOLS[*]}"
fi

# de-duplicate while preserving order
UNIQ=()
for t in "${TOOLS[@]}"; do
    case " ${UNIQ[*]-} " in *" $t "*) continue ;; esac
    UNIQ+=("$t")
done
TOOLS=("${UNIQ[@]}")

printf '%sInstalling from %s%s\n' "$B" "$REPO_DIR" "$RST"
[ "$DRY_RUN" = 1 ] && printf '%s(dry run — nothing will be written)%s\n' "$YEL" "$RST"

if [ -n "$PROJECT_DIR" ]; then
    case " ${TOOLS[*]} " in
        *" cursor "*) ;;
        *) die "--project currently applies to cursor only" ;;
    esac
    install_cursor_project "$PROJECT_DIR"
    exit 0
fi

if [ -f "$REPO_DIR/.gitmodules" ] && [ "$DRY_RUN" = 0 ]; then
    git -C "$REPO_DIR" submodule update --init --recursive
fi

for t in "${TOOLS[@]}"; do
    "install_$t"
done

printf '\n%sDone.%s Restart the tools you installed into.\n' "$B" "$RST"
[ -d "$BACKUP_ROOT" ] && say "backups: $BACKUP_ROOT"
exit 0
