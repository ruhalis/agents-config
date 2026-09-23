# agents-config

Personal agent configuration for **Claude Code** and **Codex**, installed from one source of truth — plus the **VS Code** extension set.

```bash
git clone --recurse-submodules https://github.com/ruhalis/agents-config ~/projects/agents-config
cd ~/projects/agents-config
./install.sh
```

```bash
./install.sh                     # every tool detected on this machine
./install.sh codex               # one tool
./install.sh claude codex        # several
./install.sh vscode              # install missing VS Code extensions
./install.sh skills              # only the skills, into both tools
./install.sh all                 # all three, detected or not
./install.sh --dry-run all       # print the plan, change nothing
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
  vscode/                extensions.txt — extension IDs to install
scripts/               check-skills.sh, package-skills.sh, skill-sync-status.sh
build/                 generated, gitignored; installed files symlink here
statusline/            submodule (Claude-only)
```

The orchestration doc can't be shared verbatim: it has to name the delegation mechanism, and that differs per tool. So each tool gets `core/orchestration.md` + its own `adapters/<tool>/routing.md`, composed at install time into `build/<tool>/`.

Everything that *can* be shared is shared. The three agents are authored once in Claude's format — the richer of the two — and derived for Codex. Skills need no translation at all.

## What lands where

| | Claude Code | Codex |
| --- | --- | --- |
| Instructions | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` |
| Agents | `~/.claude/agents/*.md` | `~/.codex/agents/*.toml` |
| Skills | `~/.claude/skills/` | `~/.codex/skills/` |
| Settings | `settings.json` (copy) | `config.toml` (merged block) |
| Keybindings | `keybindings.json` (copy) | — |
| Statusline | `statusline/` (submodule) | — |

Symlinked items track repo edits live. The two copies — `settings.json` and `keybindings.json` — are copies precisely because Claude Code rewrites `settings.json` in place when you change the theme or model, and a symlink would push those edits back into the repo. Re-run `install.sh` to update them.

## Skills and claude.ai

`core/skills/` is the only place skills are edited. The two installed skill directories hold symlinks to it, so an edit is live in every tool at once. After adding or renaming a skill, `./install.sh skills` relinks just the skills (no settings copy, no config merge) and names any skill still missing from `~/.claude/skills/` or `~/.codex/skills/`.

The claude.ai copies are separate. claude.ai, Cowork and cloud sessions use the skills uploaded to your claude.ai account; Claude Code downloads those into `~/.claude/skills/synced/` and never uploads, so a local edit does not reach them. After changing a skill, re-upload it:

```bash
scripts/check-skills.sh                # lint every skill; exit 1 on any FAIL
scripts/package-skills.sh esp-idf      # -> build/skills/esp-idf.skill
# upload build/skills/esp-idf.skill in claude.ai under Customize > Skills, in place of the old copy
scripts/skill-sync-status.sh           # after the next sync: in-sync, drifted or not-on-claude.ai
```

Never edit files under `synced/`: the next sync replaces them and the repo never sees the change. If `skill-sync-status.sh --diff` shows a claude.ai-side edit worth keeping, make it in `core/skills/` and upload again.

- `check-skills.sh` needs only bash and python3. It fails a skill whose frontmatter breaks the Agent Skills spec (a key outside `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`; `name` not the directory name; `description` over 1024 characters; `compatibility` over 500; a non-string `metadata` value), a script that does not parse or whose `--help` breaks, a bundled path `SKILL.md` names that does not exist, or a missing version-pin file. It warns about `__pycache__` and `.DS_Store`. Last it checks every `~/.claude/skills/<name>/<path>` in the Markdown under `~/projects`, because other repos call the bundled scripts by those paths. The header of the script lists every rule.
- `package-skills.sh` packages only skills that pass the check, with the root folder named after the skill and the same exclusions as skill-creator's packager (`__pycache__/`, `*.pyc`, `.DS_Store`, `evals/`). An unchanged skill packages to a byte-identical file.
- `install.sh` runs `check-skills.sh` and `skill-sync-status.sh` after any install that links skills. Both only report.

### What the skills read from a project

The skills hold workflow and boundaries; project facts live in the project, in `CLAUDE.md` (or `CLAUDE.local.md` / `AGENTS.md`) sections with one greppable `key: value` per line. A skill that finds its section missing works the facts out, then offers to write the section.

| Section | Read by | Keys |
|---|---|---|
| `## Boards` | esp-idf | `<board name>: <serial port>` |
| `## Hardware` | kicad-review, robotics-research-brief | `kicad:`, `pins:` (the firmware pin header), `mcu:`, `fab:`, `note:` |
| `## Motors` | motor-bench | `rule:`, `rig:`, `program:`, `send:`, `probe:`, `moves:`, `stop:`, `user-only:`, `kill:`, `limits:`, `watchdog:`, `supply:`, `direction:`, `log:` |
| `## Experiments` | rl-experiment-log | `log:`, `run-id:`, `runs:`, `metric:`, `eval:`, `framework:` |
| `## Where things run` | robotics-research-brief | robot, GPUs and VRAM, Jetson, simulator versions |

Keep this order, `## Boards` first and short: esp-idf reads a fixed 12 lines after its heading, and motor-bench reads up to the next heading. The sections also connect skills: when firmware changes the header `## Hardware` names as `pins:`, esp-idf hands back to kicad-review's pin diff, and a flash or reset of a board wired to ESCs or drivers follows motor-bench as well as esp-idf. led-animation reads the free-form `CLAUDE.md` section on the renderer and the host tooling's README instead; isaac reads the pin from `CLAUDE.md`, `.gitmodules` and `STATUS.md`.

## VS Code extensions

`adapters/vscode/extensions.txt` lists extension IDs, one per line, `#` comments allowed. `./install.sh vscode` — or a bare `./install.sh` when VS Code is detected — installs whichever are missing in a single `code --install-extension` call, always at the latest marketplace version; nothing is pinned. Extensions already on the machine are never removed, including ones the list doesn't mention. Those are reported instead, so you can add them:

```
installed here but not in extensions.txt: publisher.name
```

To capture what you've installed since, append the new IDs from `code --list-extensions` to the file. The installer needs the `code` CLI: it looks on `PATH` first, then inside the macOS app bundle. If neither is found it warns and skips — run **Shell Command: Install 'code' command in PATH** from the Command Palette and re-run.

## How the agents are derived

`core/agents/*.md` is Claude's format. Two things get translated:

**Read-only intent** is inferred from the `tools:` line rather than declared separately — an agent with no `Edit`/`Write` only advises. On Codex that becomes `sandbox_mode = "read-only"`, which is a genuine upgrade: `deep-reasoner` and `verifier` say "never modify files" as a prompt instruction in Claude, but Codex *enforces* it.

**Model tier.** `model: sonnet` maps to `CODEX_FAST_MODEL` in `adapters/codex/models.env`. Agents with no `model:` inherit the session model, and nothing is emitted for them. An unrecognized model name warns rather than guessing.

The top-level Codex `model` key is deliberately *not* managed — which models you can select depends on your plan and auth mode, so this repo won't silently repoint it. Uncomment it in `adapters/codex/config.toml` if you want it owned here.

## Codex versions

The Codex feature surface moved quickly, and an older binary silently ignores files it doesn't understand. `install.sh` inspects the installed binary and warns if subagents or skills won't be picked up (a dry run skips `codex --version`, which would write under `~/.codex/tmp/`, and only greps the binary):

```
! this Codex build has no subagent support — ~/.codex/agents/*.toml will be ignored.
  Upgrade: npm i -g @openai/codex@latest
```

`AGENTS.md` and `model_reasoning_effort` work on every build.

## Backups and safety

Anything pre-existing is backed up to `~/.agent-config-backups/<timestamp>/<tool>/`, never deleted.

Two different reconciliation policies, deliberately:

- **Swept** — `~/.claude/agents/` and `~/.claude/skills/` are owned by this repo. Anything not from here is backed up and removed, so after install they mirror the repo exactly. The exceptions are `~/.claude/skills/synced/` (skills Claude Code downloads from claude.ai) and `~/.claude/skills/.trash/`, which belong to Claude Code and are left alone.
- **Reconciled** — `~/.codex/skills/` and `~/.codex/agents/` are *shared*. Codex ships bundled skills in `~/.codex/skills/.system`, and other CLIs install alongside. Here `install.sh` only removes stale symlinks pointing back into this repo and leaves everything else alone.

Sweeping a shared directory would silently delete skills this repo never owned. Don't change `reconcile_dir` to `sweep_dir` for those paths. For the same reason a real file or directory sitting where a link should go, such as a skill Codex installed under the same name, is left alone with a warning: `ln -sfn` would overwrite the file or nest the link inside the directory.

Each `link` line says `new`, `exists` (already that link) or `replace`, so `--dry-run` shows what a run would change.

## Agents & orchestration

`core/orchestration.md` sets the main agent up as an orchestrator that plans, decomposes, delegates, and synthesizes, routing to three specialists installed on both tools:

- **deep-reasoner** (session model, read-only) — plans, architecture, complex debugging, algorithm design.
- **fast-executor** (cheap fast model) — boilerplate, tests, formatting, patterned edits.
- **verifier** (session model, read-only) — checks the integrated result against the original acceptance criteria and reports evidence.
