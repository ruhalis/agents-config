#!/usr/bin/env bash
# Bench test for the installed Claude Code setup: does it behave the way
# adapters/claude/CLAUDE.md and README.md claim?
#
#   scripts/bench.sh            static checks only (no API calls, a few seconds)
#   scripts/bench.sh --live     also run headless `claude -p` sessions (API cost,
#                               several minutes; needs `claude` logged in)
#   scripts/bench.sh --live --only L2,L5   run a subset of the live cases
#   scripts/bench.sh --keep     keep the live scratch dir for inspection
#
# Static (S*): symlinks point into this repo, live settings carry the hook, the
# deny list, the cache TTL and the subagent env; agent frontmatter pins the
# models and effort the docs say are valid; the guard hook decides correctly on
# synthetic input; skills pass check-skills.sh; CLAUDE.md stays under the
# documented 200-line budget.
#
# Live (L*), each a fresh `claude -p` run in a throwaway git repo whose project
# CLAUDE.md holds a random sentinel word:
#   L1  user CLAUDE.md reaches the main session (it can name the guard hook)
#   L2  project CLAUDE.md reaches the main session (it knows the sentinel)
#   L3  a general-purpose subagent also gets CLAUDE.md (knows the sentinel)
#   L4  the built-in Explore skips CLAUDE.md (does not know the sentinel)
#   L5  the guard hook denies `pytest` in the main session (marker file absent)
#   L6  the same command passes inside a subagent (marker file present)
#   L7  permissions.deny holds under bypassPermissions (`git clean -fd` blocked)
#   L8  model routing, from modelUsage of a haiku main session:
#       general-purpose + fast-executor -> a sonnet model, deep-reasoner -> opus
#   L9  Explore -> a haiku model, from a sonnet main session
# A logging hook (PreToolUse + SubagentStart) records every call with agent_id
# and agent_type into hook-input.log so each verdict has evidence.
#
# Exit 1 if any check failed.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LIVE=0; KEEP=0; ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --live) LIVE=1 ;;
        --keep) KEEP=1 ;;
        --only) ONLY="$2"; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; [ -z "${2:-}" ] || printf '        %s\n' "$2"; }
# check <label> <command...>: PASS when the command exits 0
check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label" "failed: $*"; fi; }

linked_to() {  # linked_to <link> <target>
    [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]
}
fm() {  # fm <agent.md> <key> -> frontmatter value
    awk -v k="$2" 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&index($0,k": ")==1{sub(k": ","");print;exit}' "$1"
}

echo "== Static checks (repo $REPO_DIR, config $CLAUDE_DIR)"

echo "-- tools"
check "jq installed (the guard hook needs it)" command -v jq
check "claude CLI installed" command -v claude

echo "-- symlinks from install.sh"
check "~/.claude/CLAUDE.md -> adapters/claude/CLAUDE.md" linked_to "$CLAUDE_DIR/CLAUDE.md" "$REPO_DIR/adapters/claude/CLAUDE.md"
for a in Explore deep-reasoner fast-executor verifier; do
    check "~/.claude/agents/$a.md -> core/agents" linked_to "$CLAUDE_DIR/agents/$a.md" "$REPO_DIR/core/agents/$a.md"
done
for d in "$REPO_DIR"/core/skills/*/; do
    n=$(basename "$d")
    check "~/.claude/skills/$n -> core/skills" linked_to "$CLAUDE_DIR/skills/$n" "${d%/}"
done
check "~/.claude/hooks/guard-main-session.sh -> adapters/claude/hooks" linked_to "$CLAUDE_DIR/hooks/guard-main-session.sh" "$REPO_DIR/adapters/claude/hooks/guard-main-session.sh"
check "guard hook is executable" test -x "$REPO_DIR/adapters/claude/hooks/guard-main-session.sh"
check "guard hook passes bash -n" bash -n "$REPO_DIR/adapters/claude/hooks/guard-main-session.sh"

echo "-- settings"
LIVE_S="$CLAUDE_DIR/settings.json"; REPO_S="$REPO_DIR/adapters/claude/settings.json"
check "repo settings.json is valid JSON" jq -e . "$REPO_S"
check "live settings.json is valid JSON" jq -e . "$LIVE_S"
for f in "$REPO_S" "$LIVE_S"; do
    tag=$([ "$f" = "$REPO_S" ] && echo repo || echo live)
    check "$tag: PreToolUse hook on Bash runs guard-main-session.sh with onFailure block" \
        jq -e '.hooks.PreToolUse[]? | select(.matcher=="Bash") | .hooks[] | select(.command|test("guard-main-session.sh")) | select(.onFailure=="block")' "$f"
    check "$tag: permissions.deny covers force push, reset --hard, clean -fd, rm -rf /" \
        jq -e '.permissions.deny as $d | ["Bash(git push --force *)","Bash(git reset --hard *)","Bash(git clean -fd *)","Bash(rm -rf /)"] | all(. as $r | $d | index($r) != null)' "$f"
    check "$tag: subagentPromptCacheTtl is 1h" jq -e '.subagentPromptCacheTtl=="1h"' "$f"
    check "$tag: env.CLAUDE_CODE_SUBAGENT_MODEL is sonnet" jq -e '.env.CLAUDE_CODE_SUBAGENT_MODEL=="sonnet"' "$f"
    check "$tag: CLAUDE_CODE_SUBAGENT_MODEL_FORCE is not set (it would override the pins)" \
        jq -e '(.env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE // "") != "1"' "$f"
    check "$tag: advisorModel set" jq -e '.advisorModel != null' "$f"
done
if jq -e 'has("model") or has("autoMode")' "$LIVE_S" >/dev/null; then
    live_only=$(jq -r --slurpfile r "$REPO_S" 'keys - ($r[0]|keys) | join(" ")' "$LIVE_S")
    printf '  NOTE  live-only settings keys (re-merge after any install.sh run): %s\n' "${live_only:-none}"
fi

echo "-- agent frontmatter"
# bash 3.2 on macOS has no associative arrays
wm() { case $1 in Explore) echo haiku;; deep-reasoner) echo opus;; *) echo sonnet;; esac; }
we() { case $1 in Explore) echo low;; deep-reasoner) echo xhigh;; *) echo medium;; esac; }
for a in Explore deep-reasoner fast-executor verifier; do
    f="$REPO_DIR/core/agents/$a.md"
    check "$a: model is $(wm "$a")" test "$(fm "$f" model)" = "$(wm "$a")"
    check "$a: effort is $(we "$a")" test "$(fm "$f" effort)" = "$(we "$a")"
    check "$a: name matches filename" test "$(fm "$f" name)" = "$a"
done
posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
for a in fast-executor verifier; do
    check "$a: maxTurns is a positive integer" posint "$(fm "$REPO_DIR/core/agents/$a.md" maxTurns)"
done
check "deep-reasoner has no Edit/Write (read-only)" bash -c "! grep -qE '^tools:.*\b(Edit|Write)\b' '$REPO_DIR/core/agents/deep-reasoner.md'"
check "verifier has no Edit/Write (read-only)" bash -c "! grep -qE '^tools:.*\b(Edit|Write)\b' '$REPO_DIR/core/agents/verifier.md'"
check "Explore has omitClaudeMd: true (our override is a custom agent; without it CLAUDE.md loads)" test "$(fm "$REPO_DIR/core/agents/Explore.md" omitClaudeMd)" = true
check "Explore has no Edit/Write (read-only)" bash -c "! grep -qE '^tools:.*\b(Edit|Write)\b' '$REPO_DIR/core/agents/Explore.md'"

echo "-- guard hook on synthetic input"
GUARD="$REPO_DIR/adapters/claude/hooks/guard-main-session.sh"
main_json() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
sub_json()  { jq -n --arg c "$1" '{agent_id:"abc",agent_type:"verifier",tool_name:"Bash",tool_input:{command:$c}}'; }
deny_main() { main_json "$1" | "$GUARD" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null; }
pass_main() { local o; o=$(main_json "$1" | "$GUARD"); [ -z "$o" ]; }
pass_sub()  { local o; o=$(sub_json "$1" | "$GUARD"); [ -z "$o" ]; }
for c in "pytest" "uv run pytest tests/" "python -m pytest -x" "npm test" "pnpm run test" "cargo test" "go test ./..." "ctest" "make test" "idf.py build" "cmake --build build" "cd x && pytest"; do
    check "main denies: $c" deny_main "$c"
done
for c in "cat pytest.ini" "ls go tests/x" "idf.py flash" "idf.py monitor" "git status" "make" "echo npm testing"; do
    check "main allows: $c" pass_main "$c"
done
for c in "pytest" "idf.py build" "npm test"; do
    check "subagent allows: $c" pass_sub "$c"
done
guard_off() { local o; o=$(main_json pytest | GUARD_MAIN_SESSION_OFF=1 "$GUARD"); [ -z "$o" ]; }
reason_names_verifier() { main_json pytest | "$GUARD" | jq -e '.hookSpecificOutput.permissionDecisionReason|test("verifier")' >/dev/null; }
check "GUARD_MAIN_SESSION_OFF=1 disables the hook" guard_off
check "deny reason names the verifier" reason_names_verifier

echo "-- instructions and skills"
lines=$(wc -l < "$REPO_DIR/adapters/claude/CLAUDE.md" | tr -d ' ')
check "CLAUDE.md under 200 lines (is $lines)" test "$lines" -lt 200
check "CLAUDE.md names the guard hook" grep -q "guard-main-session.sh" "$REPO_DIR/adapters/claude/CLAUDE.md"
check "CLAUDE.md does not claim Plan follows CLAUDE_CODE_SUBAGENT_MODEL" bash -c "! grep -qiE 'Plan[^.]*fall(s)? back to Sonnet' '$REPO_DIR/adapters/claude/CLAUDE.md'"
check "check-skills.sh --quiet --no-refs passes" "$REPO_DIR/scripts/check-skills.sh" --quiet --no-refs
check "install.sh passes bash -n" bash -n "$REPO_DIR/install.sh"

# ---------------------------------------------------------------- live
if [ "$LIVE" = 1 ]; then
    echo
    echo "== Live checks (headless claude -p; each case is a fresh session)"
    if ! command -v claude >/dev/null 2>&1; then
        bad "claude CLI missing; live checks not run"
    else
        BENCH_DIR="${BENCH_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/claude-bench.XXXXXX")}"
        SENTINEL="PELICAN$(jq -rn 'now|tostring|.[-5:]')"
        LOG="$BENCH_DIR/hook-input.log"
        PROJ="$BENCH_DIR/proj"; mkdir -p "$PROJ"
        ( cd "$PROJ" && git init -q && printf 'bench\n' > README.md && git add README.md && git -c user.name=bench -c user.email=bench@example.com commit -qm init )
        printf '# Project rules\n\nThe bench sentinel word is %s. When asked for the bench sentinel word, answer with exactly that word.\n' "$SENTINEL" > "$PROJ/CLAUDE.md"
        echo "junk" > "$PROJ/junk.txt"   # untracked; git clean -fd would delete it
        cat > "$BENCH_DIR/logger.sh" <<EOF
#!/usr/bin/env bash
cat >> "$LOG"; echo >> "$LOG"; exit 0
EOF
        chmod +x "$BENCH_DIR/logger.sh"
        SETTINGS="$BENCH_DIR/settings.json"
        jq -n --arg l "$BENCH_DIR/logger.sh" '{hooks:{PreToolUse:[{matcher:"Bash|Read|Agent",hooks:[{type:"command",command:$l,timeout:10}]}],SubagentStart:[{hooks:[{type:"command",command:$l,timeout:10}]}]}}' > "$SETTINGS"
        echo "  scratch: $BENCH_DIR  sentinel: $SENTINEL"

        want() { [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]; }
        # run <case> <model> <extra args...> -- <prompt>  ; writes <case>.json and <case>.txt
        # (claude -p gets "--" before the prompt: --disallowedTools is variadic and would eat it)
        run() {
            local case="$1" model="$2"; shift 2
            local extra=(); while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
            printf '\n### %s\n' "$case" >> "$LOG"
            ( cd "$PROJ" && perl -e 'alarm shift; exec @ARGV' 420 \
                claude -p --model "$model" --permission-mode bypassPermissions --no-session-persistence \
                --settings "$SETTINGS" --output-format json ${extra[@]+"${extra[@]}"} -- "$1" ) > "$BENCH_DIR/$case.json" 2> "$BENCH_DIR/$case.err"
            jq -r '.result // empty' "$BENCH_DIR/$case.json" > "$BENCH_DIR/$case.txt" 2>/dev/null || true
        }
        out() { cat "$BENCH_DIR/$1.txt"; }
        models() { jq -r '.modelUsage // {} | keys[]' "$BENCH_DIR/$1.json" 2>/dev/null | tr '\n' ' '; }
        NOTOOLS=(--disallowedTools "Read,Grep,Glob,Bash,Edit,Write,WebFetch,WebSearch")

        if want L1; then
            run L1 sonnet "${NOTOOLS[@]}" -- "Without using any tool: your instructions mention a PreToolUse hook script. Reply with only that script's file name."
            if grep -q "guard-main-session" "$BENCH_DIR/L1.txt"; then ok "L1 user CLAUDE.md loaded in main session"; else bad "L1 user CLAUDE.md loaded in main session" "got: $(out L1)"; fi
        fi
        if want L2; then
            run L2 sonnet "${NOTOOLS[@]}" -- "Without using any tool: reply with only the bench sentinel word from the project instructions. If you have no such word, reply NONE."
            if grep -q "$SENTINEL" "$BENCH_DIR/L2.txt"; then ok "L2 project CLAUDE.md loaded in main session"; else bad "L2 project CLAUDE.md loaded in main session" "got: $(out L2)"; fi
        fi
        if want L3; then
            run L3 sonnet "${NOTOOLS[@]}" -- "Use the Agent tool once with subagent_type \"general-purpose\" and exactly this prompt: 'Without using any tool, reply with only the bench sentinel word from the project instructions you were given. If you have no such word, reply NONE.' Then reply with only the subagent's answer, verbatim."
            if grep -q "$SENTINEL" "$BENCH_DIR/L3.txt"; then ok "L3 general-purpose subagent received project CLAUDE.md"; else bad "L3 general-purpose subagent received project CLAUDE.md" "got: $(out L3)"; fi
        fi
        if want L4; then
            run L4 sonnet "${NOTOOLS[@]}" -- "Use the Agent tool once with subagent_type \"Explore\" and exactly this prompt: 'Without using any tool, reply with only the bench sentinel word from the project instructions you were given. If you have no such word, reply NONE.' Then reply with only the subagent's answer, verbatim."
            if grep -q "$SENTINEL" "$BENCH_DIR/L4.txt"; then bad "L4 Explore skips CLAUDE.md" "Explore knew the sentinel: $(out L4)"; else ok "L4 Explore skips CLAUDE.md (answer: $(out L4 | head -c 60))"; fi
        fi
        if want L5; then
            run L5 sonnet -- "Run exactly this with the Bash tool, once: touch main-ran.marker && pytest --version . Then reply with one line saying whether it ran or was blocked, quoting any block message."
            if [ ! -e "$PROJ/main-ran.marker" ] && grep -q "Blocked in the main session" "$BENCH_DIR/L5.txt" "$BENCH_DIR/L5.json"; then ok "L5 guard hook denies pytest in main session"; else bad "L5 guard hook denies pytest in main session" "marker exists: $([ -e "$PROJ/main-ran.marker" ] && echo yes || echo no); got: $(out L5)"; fi
        fi
        if want L6; then
            run L6 sonnet -- "Use the Agent tool once with subagent_type \"general-purpose\" and exactly this prompt: 'Run exactly this with the Bash tool, once: touch sub-ran.marker; pytest --version; true . Reply with one line: ran or blocked, quoting any block message.' Then reply with only the subagent's answer."
            if [ -e "$PROJ/sub-ran.marker" ]; then ok "L6 guard hook lets a subagent run pytest"; else bad "L6 guard hook lets a subagent run pytest" "got: $(out L6)"; fi
        fi
        if want L7; then
            run L7 sonnet -- "Run exactly this with the Bash tool, once: git clean -fd . Then reply with one line saying whether it ran or was blocked, quoting any message."
            if [ -e "$PROJ/junk.txt" ]; then ok "L7 permissions.deny blocks git clean -fd under bypassPermissions"; else bad "L7 permissions.deny blocks git clean -fd under bypassPermissions" "junk.txt was deleted; got: $(out L7)"; fi
        fi
        if want L8; then
            run L8 haiku "${NOTOOLS[@]}" -- "Use the Agent tool three times, in parallel, each with the prompt 'Reply with only the word OK. Use no tools.': once with subagent_type \"general-purpose\", once with \"fast-executor\", once with \"deep-reasoner\". Then reply with only: done."
            m=$(models L8)
            if echo "$m" | grep -q sonnet && echo "$m" | grep -q opus; then ok "L8 routing from haiku main: sonnet (general-purpose/fast-executor) and opus (deep-reasoner) used [$m]"; else bad "L8 routing from haiku main" "modelUsage: ${m:-empty}; got: $(out L8)"; fi
            if grep -q '"agent_type":"deep-reasoner"' "$LOG" && grep -q '"agent_type":"fast-executor"' "$LOG" && grep -q '"agent_type":"general-purpose"' "$LOG"; then ok "L8 SubagentStart logged all three agent types"; else bad "L8 SubagentStart logged all three agent types" "see $LOG"; fi
        fi
        if want L9; then
            run L9 sonnet "${NOTOOLS[@]}" -- "Use the Agent tool once with subagent_type \"Explore\" and the prompt 'Reply with only the word OK. Use no tools.' Then reply with only: done."
            m=$(models L9)
            if echo "$m" | grep -q haiku; then ok "L9 Explore ran on haiku from a sonnet main [$m]"; else bad "L9 Explore ran on haiku from a sonnet main" "modelUsage: ${m:-empty}; got: $(out L9)"; fi
        fi
        if [ "$KEEP" = 1 ]; then echo "  kept: $BENCH_DIR"; else rm -rf "$BENCH_DIR"; fi
    fi
fi

echo
printf '%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ]
