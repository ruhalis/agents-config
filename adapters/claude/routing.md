## Routing in Claude Code

Delegate with the **Agent** tool, naming the subagent in `subagent_type`. To run independent subtasks concurrently, issue **multiple Agent calls in a single message** — separate messages run them serially.

- `deep-reasoner` — tools: Read, Grep, Glob, Bash, WebSearch, WebFetch. Cannot edit; it advises.
- `fast-executor` — tools: Read, Edit, Write, Grep, Glob, Bash. Runs on Sonnet.
- `verifier` — tools: Read, Grep, Glob, Bash. Cannot edit; it reports.
- `Explore` — read-only fan-out search when you need conclusions, not file dumps. Specify breadth ("medium", "very thorough").
- `general-purpose` — research and multi-step tasks that need the full tool set.

Use `SendMessage` to continue an existing agent with its context intact; a fresh `Agent` call starts from zero. Background agents notify you on completion — never predict their results before the notification arrives.

Skills are invoked with the **Skill** tool by name. Check the available-skills list rather than guessing names.
