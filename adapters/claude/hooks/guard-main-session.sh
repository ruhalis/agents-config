#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Denies test, build and validation commands
# in the MAIN session only; the orchestration rule in CLAUDE.md sends those to
# the verifier subagent. Subagent calls carry agent_id in the hook input and
# pass through untouched. Set GUARD_MAIN_SESSION_OFF=1 in settings `env` to
# disable without removing the hook. Exit 0 with no output = no decision.
set -u
command -v jq >/dev/null 2>&1 || exit 0
[ "${GUARD_MAIN_SESSION_OFF:-0}" = "1" ] && exit 0

input=$(cat)
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
[ -n "$agent_id" ] && exit 0            # inside a subagent: allowed

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

# One regex per guarded shape; word-bounded so "pytest.ini" or "go tests/" don't match.
pattern='(^|[;&|[:space:]])(pytest|py\.test|(python3?|uv run|uvx)[[:space:]]+(-m[[:space:]]+)?pytest|(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test([[:space:]]|$)|cargo[[:space:]]+test|go[[:space:]]+test|ctest|make[[:space:]]+(test|check)|idf\.py[[:space:]]+(build|size)|cmake[[:space:]]+--build)([[:space:]]|$)'
if printf '%s' "$cmd" | grep -qE "$pattern"; then
  jq -n --arg reason "Blocked in the main session: tests, builds and validation runs go to the verifier subagent (Agent tool, subagent_type \"verifier\"), per CLAUDE.md. Subagents may run this command." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
fi
exit 0
