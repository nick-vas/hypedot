---
name: kit-review
description: Use when the user asks for the monthly review of the Godot agent kit, or wants to know which parts of it cost the most or help the least.
disable-model-invocation: true
---

# Monthly kit review

The goal is a smaller, sharper kit: propose cuts as readily as additions. At most three proposals per review.

This review reads and measures. It changes nothing in the kit clone, makes no branch and opens no pull request: its
output is one issue per proposal in the kit's repository (step 3).

## 1. Collect numbers (ask the user for what only they can see)

- **Usage by skill, subagent and plugin**: ask the user to run `/usage` and paste the attribution section; you cannot read it.
- **Friction**: the newest `/insights` report, `~/.claude/usage-data/report.html`, if the user has run `/insights` this month.
- **Evals**: the newest folder in the kit's `evals/results/`; if older than a month, run
  `claude plugin eval . --runs 3 --scaffold --trust-plugin --allow-tools Bash Edit Write --no-publish`
  from the kit folder and use that.
- **Size**: `pwsh <kit>/ci/godot/tools/Test-Skills.ps1 -Json` (findings) and the byte size of each `SKILL.md` and of
  `ci/godot/templates/AGENTS.md`.
- **Recurring failures**: `.godot/hyperdot-history.jsonl` in each game the user names.
- **Upstream**: the newest Godot release and the Claude Code changelog (`claude --version`, then the release notes).
  A new Claude Code feature counts only if it removes kit code or a kit instruction.

## 2. Decide

For each skill and agent: used this month? Did evals show a positive delta? A skill nobody invoked for three months and
with no eval delta is a removal candidate. A recurring error code with no kit coverage is an addition candidate.
Instructions that Claude follows without being told are cut candidates.

## 3. File the proposals as issues

Do not ask which to file, and do not start on any of them: the issue is the proposal, and the owner decides there (a
scheduled run has nobody to answer). No edit in the kit clone, no branch, no pull request.

One issue per proposal (up to three) in the kit's repository: `nick-vas/hyperdot`, or `$HYPERDOT_KIT_REPO` when it is set.

- **Title**: `kit-review: <cut|add|change> <what, in a few words>`.
- **Body**, in this order:
  - **Proposal**: the smallest place it fits (a line in an existing skill, a `doctor` check, a script fix, a removal) and
    the exact text to add or the file to delete, written out so whoever picks it up needs nothing else. Not applied.
  - **Evidence**: the numbers behind it (usage counts, eval scores with and without the plugin, byte sizes, error codes with
    counts, the upstream release or changelog line), each with where it came from and its date.
  - **To merge it**: the validators (`Test-Skills.ps1`, `Test-SkillFixtures.ps1`) and, for a skill, agent or hook, the evals
    before and after, as `retro` step 5 lists them.
- **Privacy**: the kit's own file names and numbers only. No game name, absolute paths or file contents from a game.
- **Duplicates**: first look for an open issue for the same proposal (`gh issue list --repo <repo> --state open --search
  "kit-review in:title"`, or the session's GitHub tool). If there is one, add the new numbers as a comment instead.
- **Creating**: `gh issue create --repo <repo> --title ... --body-file <file>`, the body written to a file outside the
  project. Without `gh`, use the session's GitHub tool; with neither, print each title and body with
  `https://github.com/<repo>/issues/new` for the user to paste. Say an issue was filed only when the command returned its link.

Finish with each issue's link (or the printed text) and the numbers that led to no proposal. The user can have an issue built
later with `/retro` (its step 5 is the proof step); do not offer to build one now.
