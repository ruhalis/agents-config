# Orchestration

This section is for the main conversation. If you are a subagent or a workflow agent, skip it: do the task you were given yourself, following your own system prompt.

You are the orchestrator, and your context is the scarce resource: once it fills with command output and file dumps, the session loses the thread of the task. Delegate by default with the Agent tool and keep for yourself only the decision-bearing steps: understanding the request, choosing what to do, the one targeted edit, reading agent reports, integrating results and reporting. Delegation costs more tokens than doing the work; that trade is accepted. Decide before a step, not after it has filled your context: if it would take more than about three tool calls, or return more than a screen of output, it goes to an agent.

## Always delegate

- **Tests, builds, validation batches, benchmarks, smoke tests, checksums, determinism reruns.** Never run these yourself, not even one suite "just to confirm": use the Agent tool with `verifier`. Give it the commands or the acceptance criteria; it returns pass/fail with the decisive output lines. Launch it in the background and keep working on the next step. Don't rerun its commands to double-check; if its report leaves a question, ask the same agent with `SendMessage`.
- **Long output.** Logs, batch results, replay traces, any command whose output you would have to read through: use `general-purpose`, which reads in full and returns only the facts you asked for.
- **Wide search or reading.** When an answer means sweeping many files or directories, use `Explore` (say "medium" or "very thorough"); it locates things from excerpts.
- **Investigation.** A root cause that isn't visible in the file in front of you, a design choice where a wrong call is expensive, the plan for a large or risky change, an algorithm: use `deep-reasoner` with the full problem context; it returns a decision you act on. Tracing behaviour across several files or runs is an investigation, not a lookup.
- **Mechanical edits.** Boilerplate, patterned edits across files, renames, a fix whose shape is already decided, writing tests: use `fast-executor`, one per set of files, launched together when they're independent. It runs the targeted test for what it touched; the wider checks still go to `verifier`.
- **Milestone check.** At the end of a multi-part change, after long unattended work, or on a high-stakes change, use `verifier` with the original acceptance criteria and the diff scope, on top of the per-step checks; for a plain correctness review of a diff, `/code-review` also works.
- **Side task that needs this conversation.** When a fresh subagent would need too much background to be useful, fork the conversation (`subagent_type: "fork"`) instead of re-explaining it.
- **Big fan-out.** For codebase-wide audits, migrations, or more than about five parallel units, suggest a workflow to the user (you can start one once the user opts in) or `/batch` (only the user can run it) rather than launching a pile of Agent calls.

## Keep for yourself

Reading the one file you are about to edit, a single edit, a grep to confirm a name, and hardware actions (flashing, resets, anything that moves a motor), because their safety steps live in skills the agents can't load. If a step you kept grows past the limit above, stop and hand the rest to an agent.

CAD model runs and snapshots (`cadgen`, `python src/<part>.py`, the text-to-cad plugin's `cad` skill) are design iteration, not validation: the agent doing the modelling must look at the PNG and change the model. Run them in the main session, a fork or `general-purpose`, never `verifier`, which can't load skills.

## Splitting and handing off

- Split by context, not by role. The agent that implements a part also writes and runs its targeted tests; the full suite and the batches go to `verifier` once the parts are integrated. Don't chain planner → implementer → reviewer for every step.
- One writer per file. Parallel executors get disjoint sets of files; if they must overlap, run them one after another. (`isolation: "worktree"` branches by default from the pushed default branch, not your working tree, so it only suits work that starts from there.)
- Every delegation prompt stands on its own, because subagents see none of this conversation: the goal and why it matters, file paths, constraints, the pattern to follow, what "done" looks like, and for `fast-executor` the exact scope (every file, every occurrence, which tests to add or update). For `verifier`, the exact commands or criteria, the working directory, and how long a batch is allowed to run.
- `deep-reasoner`, `fast-executor` and `verifier` can't load skills. When work a skill covers goes to one of them and the skill has a "When delegating" block (esp-idf does), paste that block into the prompt.
- You own the result: integrate outputs, resolve conflicts between them, and never pass subagent output through unreviewed. A reviewer asked to find problems usually reports some even when the work is sound, so fix the findings that affect correctness or the acceptance criteria and treat the rest as optional. If an agent comes back off-spec, correct it with `SendMessage` while its context is still useful, or re-delegate once with a better prompt; if it's still wrong after that, do it yourself and keep it small.

## Workflows

When the user opts into a workflow (they ask for one, or the session has ultracode on through `/effort ultracode` or the `ultracode` setting), default to one workflow per request unless they ask for phases, and state the planned agent count before launching it, so the user can cut it down first.

## Advisor

The advisor (`advisorModel` in settings, Opus by default) is a server-side second opinion that reads this conversation and nothing else: it can't open files or run commands. Consult it before committing to the plan for a large or risky change, when the same error recurs after two attempts, and before reporting a milestone done. Don't consult it for routine steps or lookups, and don't treat its guidance as evidence: `verifier` output still decides pass/fail, and an investigation that needs files or commands goes to `deep-reasoner`. Subagents inherit the same advisor, so the Sonnet agents get Opus at their own decision points; on a Fable main model it isn't attached to the main session, and that launch notice is expected. For a one-off Fable advisor, launch with `claude --advisor fable`; `/advisor` writes to the home settings copy, which the next install.sh run overwrites.

## Mechanics

- Subagents run in the background. Launch independent ones in the same message, keep working on whatever doesn't depend on them, and wait for each completion notification before using its result; never predict it.
- A `PreToolUse` hook (`~/.claude/hooks/guard-main-session.sh`) denies test, build and validation commands in the main session; subagents pass. The denial text names the verifier. CLAUDE.md is advice, the hook is the enforcement.
- Subagent models are pinned so nothing inherits the session model: `deep-reasoner` runs on Opus at `xhigh`, `fast-executor` on Sonnet at `medium`, `verifier` on Sonnet at `medium`, `Explore` on Haiku at `low`; `general-purpose` falls back to Sonnet through `CLAUDE_CODE_SUBAGENT_MODEL`; the built-in `Plan` ignores that variable and runs on the session model. Fable stays with the orchestrator.
- Escalate one agent to the session model only by passing `model: "fable"` on that Agent call, and only after an Opus attempt on the same problem has come back wrong or inconclusive, or for a milestone check on a high-stakes change (`verifier` with `model: "opus"`). Never set it as a default.
- `deep-reasoner`: read-only (Read, Grep, Glob, Bash, WebSearch, WebFetch); returns a decision.
- `fast-executor`: Read, Edit, Write, Grep, Glob, Bash; runs the targeted test for what it touched.
- `verifier`: read-only (Read, Grep, Glob, Bash); runs the checks, reports evidence and fixes nothing.
- `Explore`: read-only, returns `file:line` locations and never retyped code. `Explore` (`omitClaudeMd: true`; without it a user-level override loads CLAUDE.md like any custom agent) and the built-in `Plan` skip CLAUDE.md, so restate any project rule they need in the prompt.
- Skills are invoked with the **Skill** tool by name. Check the available-skills list rather than guessing names.

# Python

This section applies to every agent, subagents included.

Use `uv` for all Python setup and execution; never bare `pip install`, `python -m venv`, pipx, pyenv, poetry or conda.

- **One environment per repo, always inside it.** Before the first Python command in a repo, check for `pyproject.toml` or `.venv` at the repo root. If neither exists, run `uv init` (or `uv venv` when a `pyproject.toml` is not worth adding) at the repo root so `.venv` lands there and `.venv` is in `.gitignore`. Never run `uv init` or `uv venv` outside the repo, in a parent directory or in a scratch directory, and never create a second venv for the same repo; a subproject with its own `pyproject.toml` is the only case that gets its own `.venv` next to that file. Ad-hoc one-off scripts stay on `uv run --with` or inline metadata rather than a repo venv.
- **Projects:** `uv init`, `uv add <pkg>` (`--dev` for dev tools), `uv sync`, and `uv run <cmd>` to execute, so dependencies live in `pyproject.toml` and `uv.lock`.
- **Single scripts:** inline metadata (`uv add --script file.py <pkg>`) and `uv run file.py`; for a one-off, `uv run --with <pkg> ...`.
- **CLI tools:** `uvx <tool>` to run once, `uv tool install <tool>` to keep.
- **Interpreters:** `uv python install <version>`; pin with `uv python pin`.
- **No `pyproject.toml` and not worth adding one:** `uv venv` then `uv pip install`.

Exceptions: toolchains that ship their own Python keep it (ESP-IDF's environment from `install.sh`/`export.sh`, Isaac Sim/Lab's `python.sh`/`isaaclab.sh`, KiCad's bundled Python), and a repo already on another tool stays on it unless the user asks to migrate.
