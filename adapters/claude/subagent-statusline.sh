#!/usr/bin/env bash
# subagent-statusline.sh: the row body for each subagent in Claude Code's agent
# panel (the list under the prompt while agents run). Replaces the default
# "name · description · tokens" with
#   <agent type> <model> <effort> · <description> · <tokens>
# so the type, the resolved model and the configured effort are visible at a
# glance. Wired by settings.json:
#   "subagentStatusLine": { "type": "command", "command": "~/.claude/subagent-statusline.sh" }
#
# Input (stdin): one JSON object with `columns` and `tasks[]`; each task has
# id, agentType (2.1.293+), status, description, label, startTime, model
# (optional, resolved id), effort (optional, configured level), tokenCount, ...
# Output: one JSON line per row, {"id": "<task id>", "content": "<row body>"}.
# Docs: code.claude.com/docs/en/statusline, "Subagent status lines".
set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0   # no jq: keep the default rows

jq -rc '
  def esc(c): "\u001b[" + c + "m";
  def dim: esc("2") + . + esc("0");
  def bold: esc("1") + . + esc("0");
  def effort_color:
    if . == "max" or . == "xhigh" then esc("35") + . + esc("0")      # magenta
    elif . == "high" then esc("33") + . + esc("0")                   # yellow
    else esc("36") + . + esc("0") end;                               # cyan
  # claude-opus-5-5[-20260901] -> "opus 5.5"; an alias (opus, inherit) stays.
  def short_model:
    if . == null then null
    else (capture("claude-(?<n>[a-z]+)(-(?<a>[0-9]+)-(?<b>[0-9]+))?") // null) as $m
      | if $m == null then .
        elif $m.a == null then $m.n
        else "\($m.n) \($m.a).\($m.b)" end
    end;
  def k:
    if . < 1000 then tostring
    elif . < 10000 then "\((. / 100 | floor) / 10)k"
    else "\(. / 1000 | round)k" end;
  def clip($n): if length > $n then .[:($n - 1)] + "…" else . end;

  (.columns // 80) as $cols
  | .tasks[]
  | {
      id,
      content: (
        ([
          ((.agentType // .name // "agent") | bold),
          ((.model | short_model) // "model?"),
          (if .effort == null then ("effort?" | dim) else (.effort | tostring | effort_color) end)
        ] | join(" "))
        + " · " + ((.label // .description // "") | clip(if $cols > 100 then 60 else 32 end) | dim)
        + " · " + ((.tokenCount // 0) | k | dim)
      )
    }
'
