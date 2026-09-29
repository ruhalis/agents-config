# Orchestration

This section is for the main conversation. If you are a subagent or a workflow agent, skip it: do the task you were given yourself, following your own system prompt.

Work directly by default. Delegation costs several times the tokens and loses context at every handoff, so it has to buy something: a clean main context, real parallelism, or an independent check. When one of the cases below applies, use the Agent tool the way that case says; otherwise do the work yourself.

## When to delegate

- **Wide search or reading.** When an answer means sweeping many files or directories, use the Agent tool with `Explore` (say "medium" or "very thorough"); it locates things from excerpts. When it means digesting long logs or docs you won't need afterwards, use `general-purpose`, which reads them in full. Keep only the conclusion.
- **Hard, self-contained question.** For a root cause you can't pin down, a design choice where a wrong call is expensive, the plan for a large or risky change, or an algorithm, use the Agent tool with `deep-reasoner`. Send the full problem context; it returns a decision you act on.
- **Independent parallel work.** When a change splits into sizeable parts that touch separate files, use the Agent tool with `fast-executor` for the mechanical parts, one per set of files, launched together. Anything you can finish in a handful of tool calls stays with you.
- **Independent check.** At a milestone of a multi-part change, after long unattended work, or on a high-stakes change, use the Agent tool with `verifier` against the acceptance criteria; for a plain correctness review of a diff, `/code-review` also works. Routine work you can check yourself by running the tests doesn't need it.
- **Side task that needs this conversation.** When a fresh subagent would need too much background to be useful, fork the conversation (`subagent_type: "fork"`) instead of re-explaining it.
- **Big fan-out.** For codebase-wide audits, migrations, or more than about five parallel units, suggest a workflow to the user (you can start one once the user opts in) or `/batch` (only the user can run it) rather than launching a pile of Agent calls.

## Splitting and handing off

- Split by context, not by role. The agent that implements a part also writes its tests, and planning, implementation and testing that share context stay in one place, usually here. Don't chain planner → implementer → reviewer by default.
- One writer per file. Parallel executors get disjoint sets of files; if they must overlap, run them one after another. (`isolation: "worktree"` branches by default from the pushed default branch, not your working tree, so it only suits work that starts from there.)
- Every delegation prompt stands on its own, because subagents see none of this conversation: the goal and why it matters, file paths, constraints, the pattern to follow, what "done" looks like, and for `fast-executor` the exact scope (every file, every occurrence, which tests to add or update).
- `deep-reasoner`, `fast-executor` and `verifier` can't load skills. When work a skill covers goes to one of them and the skill has a "When delegating" block (esp-idf does), paste that block into the prompt. Hardware actions such as flashing, resets, or anything that moves a motor stay with you whichever agent you delegate to, because the safety steps for them live in skills those agents can't load.
- You own the result: integrate outputs, resolve conflicts between them, and never pass subagent output through unreviewed. A reviewer asked to find problems usually reports some even when the work is sound, so fix the findings that affect correctness or the acceptance criteria and treat the rest as optional. If an agent comes back off-spec, correct it with `SendMessage` while its context is still useful, or re-delegate once with a better prompt; if it's still wrong, do it yourself.

## Workflows

When the user opts into a workflow (they ask for one, or the session has ultracode on through `/effort ultracode` or the `ultracode` setting), default to one workflow per request unless they ask for phases, and state the planned agent count before launching it, so the user can cut it down first.

## Mechanics

- Subagents run in the background. Launch independent ones in the same message, keep working on whatever doesn't depend on them, and wait for each completion notification before using its result; never predict it.
- `deep-reasoner`: read-only (Read, Grep, Glob, Bash, WebSearch, WebFetch), session model at `xhigh` effort.
- `fast-executor`: Read, Edit, Write, Grep, Glob, Bash; Sonnet at `medium` effort.
- `verifier`: read-only (Read, Grep, Glob, Bash), session model; reports evidence and fixes nothing.
- `Explore` and `Plan` skip CLAUDE.md, so restate any project rule they need in the prompt.
- Skills are invoked with the **Skill** tool by name. Check the available-skills list rather than guessing names.
