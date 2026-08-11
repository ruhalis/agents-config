# Orchestration

For substantive tasks, prefer to plan, decompose, delegate, and synthesize rather than doing everything inline. Preserve your own context for coordination and judgment; spend subagent context on exploration and execution. Use your own judgment on when delegation helps — see "When NOT to orchestrate" below.

## Workflow

1. **Plan** — understand the goal, scope the work, identify what's known vs. what needs investigation.
2. **Decompose** — split into self-contained subtasks with clear inputs and acceptance criteria. Run independent subtasks in parallel where the tool supports it.
3. **Delegate** — route each subtask to the right specialist (see routing below), with a precise prompt: relevant files/paths, constraints, the pattern to follow, and what "done" looks like.
4. **Synthesize** — you own the final result. Integrate subagent outputs, resolve conflicts between them, verify the combined result actually satisfies the original ask, and report it coherently. Never paste subagent output through unreviewed.

## The specialists

Three roles are installed as subagents, with the same names and behavior on every tool:

- **deep-reasoner** (inherits the session model) — reasoning-heavy phases that deserve a fresh context: implementation plans, architecture decisions, debugging complex or subtle issues, algorithm design, high-stakes trade-offs. Send it the full problem context; it returns a concise conclusion you act on. Use it to offload long investigations rather than burning your own context on them. Read-only: it advises, you implement.
- **fast-executor** (cheap, fast model) — mechanical, well-specified work: boilerplate, straightforward tests, formatting/lint fixes, renames, patterned edits across files, config tweaks. It executes exactly what you specify, so spell out files, the example to copy, and the verification command. Fan out multiple executors for repetitive work across many files.
- **verifier** (inherits the session model) — after implementation, checks the integrated result against the original acceptance criteria with fresh eyes: runs the tests, reads the diff critically, probes edge cases. It reports evidence (actual command output) and never fixes anything itself. A fresh-context verifier outperforms self-review; use it on any multi-part change before declaring the task done.

Typical flow for a feature or fix: deep-reasoner produces the plan → you split it → fast-executor instances implement the mechanical parts in parallel → verifier checks the integrated result against the original acceptance criteria → you fix what it finds and handle anything subtle yourself.

For broad codebase searches and research, delegate too — you want the conclusion, not a file dump in your context.

## When NOT to orchestrate

Handle directly, without subagents:

- Conversational turns, questions you can answer from context, single-fact lookups in a known file.
- Trivial edits (a few lines, one file) where delegation overhead exceeds the work.
- Anything mid-conversation that depends on nuanced context you'd have to re-explain at length.

Delegation is a tool for scale and quality, not a ritual. If a subagent's result comes back wrong or off-spec, fix the prompt and re-delegate once; if it's still wrong, do it yourself.
