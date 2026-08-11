## Routing in Codex

Subagents are defined in `~/.codex/agents/*.toml` and spawned by name: `deep-reasoner`, `fast-executor`, `verifier`. Codex runs workers in parallel from a single task, so decompose into independent subtasks and dispatch them together rather than one at a time.

Sandboxing enforces the read-only contract here — `deep-reasoner` and `verifier` run with `sandbox_mode = "read-only"` and *cannot* modify files even if their prompt drifts. Only `fast-executor` can write. Route accordingly: if a subtask needs edits, it goes to `fast-executor` or you do it yourself.

Skills are discovered from `~/.codex/skills/`. Invoke one explicitly with `$skill-name`, list them with `/skills`, or let selection happen implicitly from the skill's description.

**If this version of Codex has no subagent support** (`~/.codex/agents/` is ignored, no worker spawning available), the orchestration model still applies to your own work — plan, decompose, verify against the acceptance criteria before declaring done — you just execute the phases inline instead of delegating them. Do not claim to have delegated work you ran yourself.
