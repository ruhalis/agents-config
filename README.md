# agents-config

Personal agent configuration for **Claude Code**, **Codex**, and **Cursor**, installed from one source of truth.

```bash
git clone --recurse-submodules https://github.com/ruhalis/agents-config ~/projects/agents-config
cd ~/projects/agents-config
./install.sh
```

```bash
./install.sh                     # every tool detected on this machine
./install.sh codex               # one tool
./install.sh claude cursor       # several
./install.sh all                 # all three, detected or not
./install.sh --dry-run all       # print the plan, change nothing
./install.sh --project ~/repo cursor
                                 # project-level Cursor rules (see "Cursor's gap")
```

## Layout

```
core/                  tool-agnostic source of truth
  orchestration.md       the orchestration model, no tool-specific machinery named
  agents/*.md            the three specialists, written in Claude's format
  skills/*/              SKILL.md skills — already a cross-tool standard
adapters/
  claude/                routing tail + settings.json + keybindings.json
  codex/                 routing tail + managed config.toml keys + model map
  cursor/                routing tail
build/                 generated, gitignored; installed files symlink here
statusline/            submodule (Claude-only)
```

The orchestration doc can't be shared verbatim: it has to name the delegation mechanism, and that differs per tool. So each tool gets `core/orchestration.md` + its own `adapters/<tool>/routing.md`, composed at install time into `build/<tool>/`.

Everything that *can* be shared is shared. The three agents are authored once in Claude's format — the richest of the three — and derived for the others. Skills need no translation at all.

## What lands where

| | Claude Code | Codex | Cursor |
| --- | --- | --- | --- |
| Instructions | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | ⚠️ no file — see below |
| Agents | `~/.claude/agents/*.md` | `~/.codex/agents/*.toml` | `~/.cursor/agents/*.md` |
| Skills | `~/.claude/skills/` | `~/.codex/skills/` | `~/.cursor/skills/` |
| Settings | `settings.json` (copy) | `config.toml` (merged block) | — |
| Keybindings | `keybindings.json` (copy) | — | — |
| Statusline | `statusline/` (submodule) | — | — |

Symlinked items track repo edits live. The two copies — `settings.json` and `keybindings.json` — are copies precisely because Claude Code rewrites `settings.json` in place when you change the theme or model, and a symlink would push those edits back into the repo. Re-run `install.sh` to update them.

## How the agents are derived

`core/agents/*.md` is Claude's format. Two things get translated:

**Read-only intent** is inferred from the `tools:` line rather than declared separately — an agent with no `Edit`/`Write` only advises. On Codex that becomes `sandbox_mode = "read-only"`, which is a genuine upgrade: `deep-reasoner` and `verifier` say "never modify files" as a prompt instruction in Claude and Cursor, but Codex *enforces* it. Cursor has no equivalent, so there it stays instruction-only.

**Model tier.** `model: sonnet` maps to `CODEX_FAST_MODEL` in `adapters/codex/models.env`. Agents with no `model:` inherit the session model, and nothing is emitted for them. An unrecognized model name warns rather than guessing.

The top-level Codex `model` key is deliberately *not* managed — which models you can select depends on your plan and auth mode, so this repo won't silently repoint it. Uncomment it in `adapters/codex/config.toml` if you want it owned here.

## Cursor's gap

Cursor keeps global User Rules inside the application; there is no file to install to. Two workarounds, both supported:

- `./install.sh cursor` puts the composed text on your clipboard — paste once into **Settings → Rules → User Rules**, and re-paste after editing `core/orchestration.md`.
- `./install.sh --project ~/repo cursor` writes `.cursor/rules/orchestration.mdc` with `alwaysApply: true` into a specific repo. Reliable and version-controllable, but per-repo.

Cursor subagents and skills *are* file-based, so those install normally either way.

## Codex versions

The Codex feature surface moved quickly, and an older binary silently ignores files it doesn't understand. `install.sh` inspects the installed binary and warns if subagents or skills won't be picked up:

```
! this Codex build has no subagent support — ~/.codex/agents/*.toml will be ignored.
  Upgrade: npm i -g @openai/codex@latest
```

`AGENTS.md` and `model_reasoning_effort` work on every build.

## Backups and safety

Anything pre-existing is backed up to `~/.agent-config-backups/<timestamp>/<tool>/`, never deleted.

Two different reconciliation policies, deliberately:

- **Swept** — `~/.claude/agents/` and `~/.claude/skills/` are owned by this repo. Anything not from here is backed up and removed, so after install they mirror the repo exactly.
- **Reconciled** — `~/.codex/skills/`, `~/.cursor/skills/`, and the agent directories are *shared*. Codex ships bundled skills in `~/.codex/skills/.system`, Cursor manages `~/.cursor/skills-cursor`, and other CLIs install alongside. Here `install.sh` only removes stale symlinks pointing back into this repo and leaves everything else alone.

Sweeping a shared directory would silently delete skills this repo never owned. Don't change `reconcile_dir` to `sweep_dir` for those paths.

## Agents & orchestration

`core/orchestration.md` sets the main agent up as an orchestrator that plans, decomposes, delegates, and synthesizes, routing to three specialists installed on all three tools:

- **deep-reasoner** (session model, read-only) — plans, architecture, complex debugging, algorithm design.
- **fast-executor** (cheap fast model) — boilerplate, tests, formatting, patterned edits.
- **verifier** (session model, read-only) — checks the integrated result against the original acceptance criteria and reports evidence.
