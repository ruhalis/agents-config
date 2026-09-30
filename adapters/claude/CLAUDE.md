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

## Splitting and handing off

- Split by context, not by role. The agent that implements a part also writes and runs its targeted tests; the full suite and the batches go to `verifier` once the parts are integrated. Don't chain planner → implementer → reviewer for every step.
- One writer per file. Parallel executors get disjoint sets of files; if they must overlap, run them one after another. (`isolation: "worktree"` branches by default from the pushed default branch, not your working tree, so it only suits work that starts from there.)
- Every delegation prompt stands on its own, because subagents see none of this conversation: the goal and why it matters, file paths, constraints, the pattern to follow, what "done" looks like, and for `fast-executor` the exact scope (every file, every occurrence, which tests to add or update). For `verifier`, the exact commands or criteria, the working directory, and how long a batch is allowed to run.
- `deep-reasoner`, `fast-executor` and `verifier` can't load skills. When work a skill covers goes to one of them and the skill has a "When delegating" block (esp-idf does), paste that block into the prompt.
- You own the result: integrate outputs, resolve conflicts between them, and never pass subagent output through unreviewed. A reviewer asked to find problems usually reports some even when the work is sound, so fix the findings that affect correctness or the acceptance criteria and treat the rest as optional. If an agent comes back off-spec, correct it with `SendMessage` while its context is still useful, or re-delegate once with a better prompt; if it's still wrong after that, do it yourself and keep it small.

## Workflows

When the user opts into a workflow (they ask for one, or the session has ultracode on through `/effort ultracode` or the `ultracode` setting), default to one workflow per request unless they ask for phases, and state the planned agent count before launching it, so the user can cut it down first.

## Mechanics

- Subagents run in the background. Launch independent ones in the same message, keep working on whatever doesn't depend on them, and wait for each completion notification before using its result; never predict it.
- `deep-reasoner`: read-only (Read, Grep, Glob, Bash, WebSearch, WebFetch), session model at `xhigh` effort.
- `fast-executor`: Read, Edit, Write, Grep, Glob, Bash; Sonnet at `medium` effort.
- `verifier`: read-only (Read, Grep, Glob, Bash), session model; runs the checks, reports evidence and fixes nothing.
- `Explore` and `Plan` skip CLAUDE.md, so restate any project rule they need in the prompt.
- Skills are invoked with the **Skill** tool by name. Check the available-skills list rather than guessing names.
