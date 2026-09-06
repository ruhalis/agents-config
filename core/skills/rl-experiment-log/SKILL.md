---
name: rl-experiment-log
description: Use when starting, changing, or reviewing an Isaac Lab / RL training run (TVC rocket, G1 tracking, sim-to-real) so each run gets a comparable record of config, reward terms, result and next step.
---

# RL experiment log

Arlan runs RL in Isaac Lab (DirectRLEnv / ManagerBasedRLEnv) for a TVC model rocket and Unitree G1 motion tracking (DeepMimic-style, BeyondMimic pipeline). The problem this skill solves: after a few days it's unclear what was tried and why a reward change helped. Use the `isaac` skill for the code itself; this skill is for the record around it.

## When a run starts or a config changes

Create or append to `experiments/LOG.md` in the project repo (or the Obsidian vault if connected) one entry:

```
## <run-id> — <YYYY-MM-DD HH:MM> — <one-line hypothesis>
- Base: <previous run-id or "fresh">
- Changed: <exactly what differs from base — reward term/weight, obs, curriculum, domain rand, hyperparam>
- Env: <task name>, num_envs, episode length, sim dt / decimation
- Algo: <PPO/…>, key hparams (lr, entropy, clip, horizon)
- Reward terms: name → weight (full list, even unchanged)
- Seed(s):
- Command: <exact train command>
- Expected: <what metric should move, by how much, by which iteration>
```

The run-id is `<task>-<NNN>` incrementing. Never edit a past entry; add a new one.

## When a run finishes or is stopped

Append under the same entry:

```
- Result: <mean reward / success rate / tracking error at final iter>, wall time, GPU
- Curve: <where the tensorboard/wandb run lives>
- Verdict: keep / discard / inconclusive — one sentence why
- Next: <the single next change>
```

If asked to summarise, produce a table of run-id | changed | key metric | verdict from the log, then a 3-sentence read of the trend.

## Rules

- One variable per run unless explicitly doing a sweep; a sweep is one entry with a sub-table.
- Sim-to-real runs must record the domain-randomisation ranges and the real-robot outcome separately ("walks 5 m, falls on turn").
- Before proposing a reward change, check the log for the last time that term was touched and what happened.
- Keep it terse; this is a lab notebook, not a report.
