---
name: robotics-research-brief
description: "Use when comparing models, papers, datasets or toolchains for robotics/physical AI (VLAs, world models, GR00T/Cosmos, retargeting, RL) or drafting a peer review (confidential submissions: policy gate first) — produces a fixed-format brief for the Obsidian vault."
---

# Robotics research brief

Arlan does physical-AI R&D. Interests as of 2026-09 (starting points only; search for newer releases from the last ~6 months before comparing): GR00T N1.7, Cosmos 3, VLAs like π0.5/OpenVLA (RT-2: closed, reference only), world models like DreamerV3/JEPA, motion retargeting GVHMR (non-commercial license)→GMR→BeyondMimic. Robots and compute come from the project (step 1); Known platforms below is the fallback only. Briefs are for deciding what to build or adopt next, so they must end in a decision, not a survey.

## Before writing

0. Pick the mode first: brief, peer review, or related work (a brief plus its final section). Peer review starts at its gate, before steps 1–4. Never run step 3 on a manuscript under review.
1. Project facts come from the repo. Before searching, read the current repo's CLAUDE.md (`## Hardware` / `## Where things run`) and project memory. Take the robot, GPU model and VRAM, Jetson module and JetPack, and simulator and version from there (whichever apply), and state them in the Question line. If the request names a robot or project in Known platforms, read that project's CLAUDE.md (Source column) even from another repo. Where memory and CLAUDE.md disagree, CLAUDE.md wins.
2. Ask one question only if the decision axis is unclear (e.g. "is this for on-Jetson inference or workstation training?") or there is no project context (which robot / which compute?). Cannot ask: use Known platforms below and state the assumption in the Question line.
3. Search. Papers, model cards, GitHub READMEs, release notes — current facts only, with links. Note release dates. License: read the LICENSE file and the model card, not GitHub's SPDX badge (NOASSERTION = read the file). Check code, weights, body models and datasets separately. Flag non-commercial, research-only or gated terms in Gaps and risks, and say which intended use (commercial or research) the verdict assumes.
4. Every number in Key evidence and the compute column comes from a primary source you opened (paper, model card, README, release notes), never a search-result summary. Tag each result with [real|sim], embodiment, N trials and model version; tag inference numbers with device and precision. If the embodiment or device isn't ours, write "measured on <X>; ours is <Y>". If the primary source could not be opened, append "(unverified)".

## Known platforms (fallback only; the project CLAUDE.md wins)

Step 1 uses the Source column to find a named robot's project. Use the Facts only when step 1 finds no project facts and step 2 cannot ask. Name the one you assumed in the Question line.

| Platform | Facts | Source |
|---|---|---|
| Workstation | RTX 5080 16 GB, Ubuntu 22.04 | ~/projects/cooper/CLAUDE.md:25, ~/projects/aquila/CLAUDE.md:11 |
| Overnight training | H200 141 GB, nights only | ~/projects/cooper/CLAUDE.md:26; nvidia.com/en-us/data-center/h200 |
| RTX 5090 32 GB | (unconfirmed - ask the user) | memory note only |
| cooper arm | myCobot 280, 6-DOF + adaptive gripper, trained in Isaac Lab | ~/projects/cooper/CLAUDE.md:7-9 |
| berkley humanoid | Berkeley Humanoid Lite, 22 DoF; onboard Beelink Mini S12 (Intel N95, 8 GB); Isaac Lab + rsl_rl | ~/projects/berkley/CLAUDE.md:56-63 |
| aquila drone | raptor-torch policy trained on the RTX 5080, deployed to ESP32-S3 / STM32 | ~/projects/aquila/CLAUDE.md:9-11 |
| Unitree G1 EDU (archived projects) | Jetson Orin NX 16GB, JetPack 6.x, CUDA 12.x | ~/projects/archive/g1_concierge/CLAUDE.md:7 |
| Unitree Go2 EDU (archived projects) | optional Orin module, 40–100 TOPS; which module: (unconfirmed - ask the user) | unitree.com/go2 spec table |
| Simulator | Isaac Lab at the version in the isaac skill's `metadata: isaac-lab-version` (`../isaac/SKILL.md` frontmatter) | isaac skill |

## Brief format (Markdown file; see Saving)

```
# <Topic> — brief (YYYY-MM-DD)

## Question
One sentence: the decision this brief informs. Then the robot, compute and simulator it is judged against (step 1, or the stated assumption).

## Bottom line
2–4 sentences. What to pick and why. State the main risk.

## Candidates
Table: name | what it is | inputs/outputs | compute (min VRAM train / infer, device) | license (code / weights / data; gated?) | released | maturity (stars, last commit) | fit for the stack in Question

## Key evidence
Per candidate, 2–3 lines of concrete numbers or results with source links, tagged as in step 4. No adjectives without a number.

## Gaps and risks
What isn't known; what would break on the robot, compute and simulator named in the Question. Compare each candidate's minimum memory (train/infer) and required JetPack/CUDA/Python with the target device. State the Isaac Lab/Sim version each candidate pins and whether it runs on ours; flag 2.x→3.x breaks (quaternion order, Isaac Sim 6.1, Python 3.12). License terms flagged in step 3.

## Next experiment
The smallest concrete test (≤1 day) that would confirm the bottom line. Include dataset/env, metric, and success threshold. Name the GPU it runs on and confirm it fits that GPU's VRAM; otherwise name the machine (e.g., H200 overnight).

## Sources
Links.
```

Keep the whole thing under ~1,200 words. Prose inside sections, no nested bullets. ASCII diagrams only if they show a real mechanism (pipeline, data flow).

## Check before saving

Before writing the file, check the draft against the template (peer review: against the skeleton in Peer-review mode):
- Headings present, in order: Question, Bottom line, Candidates, Key evidence, Gaps and risks, Next experiment, Sources — or, in peer-review mode, Summary, Strengths, Weaknesses, Questions for authors, Minor issues, Recommendation.
- Brief mode only: Bottom line names exactly one pick and one risk.
- Brief mode only: every Candidates cell is filled or marked "unknown".
- Brief mode only: every Key evidence line has a number, a URL, and a provenance tag ([real|sim], embodiment, N trials, model version; device and precision for inference numbers; or "(unverified)" if the primary source wasn't opened).
- Brief mode only: Next experiment names dataset/env, metric, success threshold, and the GPU it runs on (or the machine, e.g. H200 overnight).
- Under ~1,200 words (peer review has no fixed length target — stay concise).
- No nested bullets — prose inside sections, as the template uses; peer review follows the skeleton's own structure.

Fix anything that fails, then re-check before saving.

## Saving

Vault = `/Users/ruhalis/obsidian/ruhalis` (a plain folder, so no connector is needed). Save to the folder named by `newFileFolderPath` in its `.obsidian/app.json` (currently "0. Files/6. Inbox") unless the user names another folder, if that folder exists and is writable (`test -w`). Filename: "<Topic> brief YYYY-MM-DD.md", with none of / \ : # ^ | [ ] % * ? " < >. Never overwrite an existing note; append " 2". If the vault or folder is missing or not writable (other machine, claude.ai), save to `docs/briefs/` in the current repo or return the brief inline, and name the vault folder it belongs in. Always report the path.

## Peer-review mode

Gate, before reading the manuscript: ask the venue and whether it is under confidential review. If it is under review at an IEEE RAS venue (e.g. ICRA, IROS, CASE, Humanoids, RA-L, T-RO, T-ASE), or at any venue whose reviewer policy bans AI or is unknown, do not read, summarize, search or save the manuscript or any review text. Offer only the empty review skeleton below, inline. A preprint Arlan is reviewing for such a venue still counts as under review. Reason: the IEEE RAS generative-AI guidelines (https://www.ieee-ras.org/publications/guidelines-for-generative-ai-usage/) say using AI to perform reviews of submitted manuscripts is not allowed, and quote IEEE PSPB 8.2.1.C.5: manuscript content under review must not be processed through a public platform. The page names no venues; the examples are RAS conferences and journals from ieee-ras.org's Conferences and Publications pages. The gate applies only when Arlan is the reviewer: Arlan's own paper is never gated, even while it is under review. Run the full review only for public papers (arXiv/published) or Arlan's own drafts. In every mode, never web-search a submission's title, abstract or distinctive phrases, and never save manuscript content to the synced vault.

Review skeleton: Summary (3 sentences) → Strengths → Weaknesses (each tied to a section/figure, with what would fix it) → Questions for authors → Minor issues → Recommendation on the venue's own scale, with one-line justification: journals (RA-L, T-RO) accept / minor revision / major revision / reject; IEEE RAS conferences (ICRA, IROS, CASE) overall rating, no revision round; OpenReview venues (CoRL, NeurIPS) their numeric score. Ask the venue if unknown. In a full review, check math, baselines, and whether claimed real-robot results have enough detail to reproduce.

## Related-work extraction

When the user says the brief is for a paper or thesis, or asks for related work or BibTeX, add a final section "For related work": one citation-ready line per paper. Use keys from the paper repo's .bib if one exists (`git ls-files "*.bib"`). Otherwise fetch the entry from `https://arxiv.org/bibtex/<id>` or the DOI (`curl -sLH "Accept: application/x-bibtex" "https://doi.org/<doi>"`), and prefer the published venue entry over arXiv. Never write BibTeX from memory; write "no BibTeX found" if the fetch fails.

## Degradation

- No live web (e.g., WebSearch unavailable or disabled): say so in the Bottom line and mark facts that may be newer than the index "(unverified)".
- A fact you cannot confirm: "(unverified)".
- Paywalled paper: use the arXiv version or abstract and say so.
- Cannot ask the user: state the assumed decision axis and platform in the Question line.
- Vault not writable: follow the Saving fallback.
