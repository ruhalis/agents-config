---
name: rl-experiment-log
description: Keeps a lab notebook of RL/IL training runs (e.g. Isaac Lab rsl_rl/skrl PPO, SAC, BC/DAgger distillation) - base run, the one change, config, code commit, exact command and inputs, task metric, verdict, next step. Use whenever the user starts, stops, sweeps or compares training runs, asks what was tried before or which run was best, is about to change a reward term/weight, curriculum, domain randomisation or hyperparameter, or mentions an experiment log, run log, decision ledger, TensorBoard/W&B run or sim-to-real test. Not for writing env code (isaac) or comparing papers (robotics-research-brief).
---

# RL experiment log

Arlan trains RL/IL policies in several repos (e.g. cooper: Isaac Lab PPO fine-tuned from BC; aquila/raptor-torch: SAC teachers → DAgger student; TVC rocket; Unitree G1 motion tracking). The problem this skill solves: after a few days it's unclear what was tried and why a reward change helped. Project specifics (where runs are recorded, which metric counts, where run dirs live) come from the repo's CLAUDE.md/AGENTS.md (its `## Experiments` section if it has one), not from this skill. Use the `isaac` skill for the code itself; this skill is for the record around it.

## Resolve the log first

Once per project, pick where entries go, in this order:

1. The project CLAUDE.md/AGENTS.md has a `## Experiments` section: use its `log:` path.
2. The repo already keeps a results ledger (`grep -rl 'Decision ledger' --include='*.md' .`; aquila: `raptor-torch/STATUS.md` ledger + `EVIDENCE.md`): write there in that ledger's own format. Map this skill's fields onto its columns and put the detail in its evidence doc. If the ledger takes results only, put the start block wherever the repo's doc map puts plans and pre-registrations (aquila: `PLAN.md` next actions, at that doc's own heading level), or ask if the map doesn't say; the ledger row and its evidence section land with the Verdict.
3. Otherwise propose `experiments/LOG.md` (in a monorepo, next to the training package). First run `git check-ignore -q <path>`; if the path is ignored, use `docs/EXPERIMENTS.md` instead and say so. If the repo has a doc-ownership map (cooper's CLAUDE.md), ask before creating the file and add it to the map in the same change.

The repo log is the only home for run history. The Obsidian vault gets a summary only on request, at `~/obsidian/ruhalis/1. Projects/<Project>/Experiments.md`, linking back to the repo log.

## When a run starts or a config changes

Add one entry to the resolved log:

```
## <run-id> — <YYYY-MM-DD HH:MM> — <one-line hypothesis>
- Base: <previous run-id or "fresh">
- Changed: <exactly what differs from base — reward term/weight/params or reward code, obs, curriculum, domain rand, hyperparam, inputs>
- Code: <task repo>@<git rev-parse --short HEAD>[-dirty] (<branch>)
- Inputs: <init checkpoint path + producing run-id or sha256 | scratch>; dataset path (e.g. datasets/expert_demos.npz); reference motion as the resolved W&B artifact version (:vN, never :latest)
- Env: <task name>, num_envs, episode length, sim dt / decimation
- Obs/Act (optional): <obs terms + dim; action type + scale>
- Algo: <PPO/SAC/…> + key hparams as named in the config; for BC/DAgger: N demos, epochs, val loss
- Reward terms: name → weight {non-default params} (full list, even unchanged)
- Curriculum: <term: what ramps, from→to, over which steps>
- DR: <term: range> (copied from params/env.yaml events:, or the env cfg)
- Seed(s):
- Command: <exact train command, including every env var the launcher reads, e.g. BC_CKPT=… BC_INIT_STD=0.1 BC_GRIP_STD=1.0 …; redact secrets such as WANDB_API_KEY>
- Expected: <what task metric should move, by how much, by which iteration>
```

Code is the task repo as checked out on the training host, not Isaac Lab; add `-dirty` when `git status --porcelain` is not empty.

The run-id is `<short-task-slug>-<NNN>` (e.g. `pick-ik-004`), where NNN is the highest number already in that log plus 1. For rsl_rl, pass the same string as `--run_name`.

An entry is open until it has a Verdict. Fill its result block under its own heading, not at the end of the file, replacing any `pending` values once the numbers arrive. After the Verdict it is frozen; corrections go in a new entry with `Base: <run-id> (correction)`.

## When a run finishes or is stopped

Fill in under the entry's own heading:

```
- Result: <task metric that does not depend on reward weights (success/lift rate, Metrics/<cmd>/error_*, gate return under a fixed eval reward), with the exact logged tag or eval output line, the checkpoint (final/best), and the eval protocol (N episodes, play env, deterministic, seed)>; wall time, GPU; train mean_reward is secondary only
- Curve: <where the tensorboard/wandb run lives>
- Verdict: keep / discard / inconclusive — one sentence why
- Next: <the single next change>
```

If asked to summarise, produce a table of run-id | changed | key metric | verdict from the log, where key metric is the task metric from Result, then a 3-sentence read of the trend.

## Rules

- One variable per run unless explicitly doing a sweep; a sweep is one entry with a sub-table.
- A reward-formula change in code counts as the one Changed variable and must cite the commit.
- Never compare Train/mean_reward or Episode_Reward/* across runs whose reward weights or params differ; Isaac Lab multiplies each term by its weight before logging. The Verdict must cite the task metric; if the run is closed without one, the Verdict is inconclusive.
- Sim-to-real: log the real-robot test as a new entry with `Base: <sim run-id>` and `- Deployed: <checkpoint/export path + sha256 or export manifest>, robot, firmware/controller rev, date` and `- Real: <outcome, e.g. walks 5 m, falls on turn>`, so the sim verdict stays frozen. The DR ranges are in the sim entry's DR line.
- Before proposing a reward change, check the log for the last time that term was touched (a params-only change counts) and what happened. If no log entry covers the term, check `git log -L '/[^_[:alnum:]]<term>[^_[:alnum:]].*=/,/^ *)/:<reward/env cfg file>'` (the range ends at the term's closing paren) (`git log -S'<term>'` only finds where the term was added or removed), the comments next to the term, and the project ledger before proposing.
- Keep it terse; this is a lab notebook, not a report.

## Degradation

- Run artifacts on a remote training host: ask the user for the run-dir listing, the final scalars and `git -C <repo> rev-parse --short HEAD && git -C <repo> status --porcelain` from the host, or rsync the run's config dump and logs (Isaac Lab: `params/` + `events.out.tfevents.*`). Never invent numbers; write `Result: pending (on <host>:<path>)` and leave the entry open. Without the host's sha, write `Code: unknown (local <sha>)`.
- No repo filesystem (claude.ai): output the entry as a fenced block for the user to paste.
- Task metric never evaluated and the run is being closed anyway: Next is the eval to run.
