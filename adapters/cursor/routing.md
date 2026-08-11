## Routing in Cursor

Subagents are defined in `~/.cursor/agents/*.md` (user-level) and `.cursor/agents/*.md` (project-level, higher priority). Delegate to them by name: `deep-reasoner`, `fast-executor`, `verifier`. They run in isolated contexts, which is the point — exploration and execution stay out of your main conversation.

Cursor does not guarantee parallel fan-out the way the other tools do. Prefer delegating the expensive phases (a long investigation, a repetitive multi-file edit, the final verification pass) over splitting work into many small concurrent subtasks. Sequential delegation still buys you the context isolation.

Cursor does not enforce a read-only sandbox on subagents, so `deep-reasoner` and `verifier` are read-only **by instruction only**. If either one reports having edited files, treat that as a defect and check the diff yourself.

Skills are auto-discovered from `~/.cursor/skills/` and `.cursor/skills/`. Reference one directly when you know it applies rather than waiting for implicit selection.
