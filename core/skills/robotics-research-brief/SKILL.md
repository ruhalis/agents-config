---
name: robotics-research-brief
description: Use when comparing models, papers, datasets or toolchains for robotics/physical AI (VLAs, world models, GR00T/Cosmos, retargeting, RL) or drafting a peer review — produces a fixed-format brief for the Obsidian vault.
---

# Robotics research brief

Arlan does physical-AI R&D (Unitree Go2/G1, Jetson, Isaac Lab, GR00T N1.7, Cosmos 3, VLAs like π0/OpenVLA/RT-2, world models like DreamerV3/JEPA, motion retargeting GVHMR→GMR→BeyondMimic). Briefs are for deciding what to build or adopt next, so they must end in a decision, not a survey.

## Before writing

1. Search first. Papers, model cards, GitHub READMEs, release notes — current facts only, with links. Note release dates and license.
2. Ask one question only if the decision axis is unclear (e.g. "is this for on-Jetson inference or workstation training?"). Otherwise assume: deployment target is Jetson Orin or a single workstation GPU, sim is Isaac Lab, robots are Unitree.

## Brief format (Markdown, saved as a file; goes to the Obsidian vault if it's connected)

```
# <Topic> — brief (YYYY-MM-DD)

## Question
One sentence: the decision this brief informs.

## Bottom line
2–4 sentences. What to pick and why. State the main risk.

## Candidates
Table: name | what it is | inputs/outputs | compute (train / infer) | license | maturity (stars, last commit, real-robot results) | fit for our stack

## Key evidence
Per candidate, 2–3 lines of concrete numbers or results with source links. No adjectives without a number.

## Gaps and risks
What isn't known; what would break on Jetson / Unitree / Isaac Lab specifically.

## Next experiment
The smallest concrete test (≤1 day) that would confirm the bottom line. Include dataset/env, metric, and success threshold.

## Sources
Links.
```

Keep the whole thing under ~1,200 words. Prose inside sections, no nested bullets. ASCII diagrams only if they show a real mechanism (pipeline, data flow).

## Peer-review mode

If asked to review a paper (IEEE/conference style), use instead: Summary (3 sentences) → Strengths → Weaknesses (each tied to a section/figure, with what would fix it) → Questions for authors → Minor issues → Recommendation (accept / minor / major / reject) with one-line justification. Check math, baselines, and whether claimed real-robot results have enough detail to reproduce.

## Related-work extraction

When the brief supports Arlan's own paper, add a final section "For related work" with 1-line citation-ready summaries per paper (BibTeX keys if available).
