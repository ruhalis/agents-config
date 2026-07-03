# claude-config

Personal Claude Code configuration, installed into `~/.claude/`.

```bash
git clone --recurse-submodules https://github.com/ruhalis/claude-config ~/projects/claude-config
cd ~/projects/claude-config
./install.sh
```

`install.sh` is idempotent and backs up any pre-existing real files to `*.bak` (gitignored) before linking.

## What it installs

| Item | Target | Method |
| --- | --- | --- |
| `agents/*.md` | `~/.claude/agents/` | symlink (per file) |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | symlink |
| `skills/*/` | `~/.claude/skills/` | symlink (per skill) |
| `statusline/` | `~/.claude/statusline` | symlink (submodule) |
| `settings.json` | `~/.claude/settings.json` | copy |
| `keybindings.json` | `~/.claude/keybindings.json` | copy |

Symlinked items (agents, CLAUDE.md, skills, statusline) reflect repo edits live. The copied items (settings, keybindings) require re-running `install.sh` to update.

## Agents & orchestration

`CLAUDE.md` sets the main agent up as an orchestrator that plans, decomposes, delegates, and synthesizes. It routes to two global subagents:

- **deep-reasoner** (Opus) — reasoning-heavy phases: plans, architecture, complex debugging, algorithm design.
- **fast-executor** (Sonnet) — mechanical, well-specified work: boilerplate, tests, formatting, patterned edits.
