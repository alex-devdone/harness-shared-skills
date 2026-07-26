---
name: shipped-where
description: Answer "is this commit/PR already on stage or prod, and when did it land?" for any git repo with a promotion flow (dev → stage → main). Reports, per release branch, whether the change is contained and which merge commit + timestamp first carried it there. Use this whenever the user asks whether a PR/fix/commit is on stage, on prod, on main, "did this ship", "is this released yet", "when did this reach production", "is my fix live", "do we need to port this to main", or asks to compare a branch against dev/stage/main — even if they only paste a PR URL and ask "where is this?". Also use it before porting/cherry-picking a PR to another branch, to check the port isn't already unnecessary.
---

# Shipped Where

Given a commit SHA, PR number, PR URL, or branch name, report which release branches already contain it and the merge that introduced it.

## Usage

Run from inside the repo the PR belongs to:

```bash
~/.claude/skills/shipped-where/scripts/shipped-where.sh 4269          # PR number
~/.claude/skills/shipped-where/scripts/shipped-where.sh https://github.com/org/repo/pull/4269
~/.claude/skills/shipped-where/scripts/shipped-where.sh 904a7622b     # commit
~/.claude/skills/shipped-where/scripts/shipped-where.sh               # HEAD
BRANCHES="main" ~/.claude/skills/shipped-where/scripts/shipped-where.sh 1234   # repos with a single release branch
```

Default branches are `dev stage main`; ones that don't exist on `origin` are skipped, so the same command works in a single-branch repo (one that ships straight to `main`) and a three-stage one.

Output:

```
PR #1234  [MERGED -> dev]  ABC-123: allow clearing the default selection
commit 3839572b6 2026-07-09 Merge pull request #1234 from myorg/fix/ABC-123

dev    YES  2026-07-09T08:57:45Z  via PR #1234  ABC-123: allow clearing the default selection
stage  YES  2026-07-09T13:54:41Z  via PR #1234  Dev
main   YES  2026-07-13T13:49:21Z  via PR #1234  Stage
```

## Reading the result

Each `via PR` is the promotion that carried the change onto that branch, so the line names the hop: the fix merged to `dev`, rode `dev → stage` (#1234) five hours later, and reached `main` four days after that via `stage → main` (#1234).

Answer in prose: where it is, when each hop happened, and — if a branch says NO — that a port is still needed. `port-pr-to-branch` handles the port; don't hand-roll a cherry-pick.

## Caveats worth saying out loud

- **Contained ≠ deployed.** This reads git and the GitHub API, not Cloud Run. If the user needs certainty that prod is *serving* the code, check the running revision's commit (e.g. `gcloud run revisions list`) — a merge into `main` minutes ago may not be live yet.
- **Squash/rebase merges rewrite the SHA.** In a squashing repo the branch commit is an ancestor of nothing and every branch reads NO. Pass the PR number rather than the SHA — it resolves to the merge commit, which is the object that actually lives on the release branches. If a squashed PR still reads NO everywhere, fall back to grepping the PR title in `git log --oneline origin/main`.
- **Don't try to date the arrival from git topology alone.** The tempting `git log --first-parent origin/stage` walk is wrong in a workspace like this: auto-merge bots merge dev/stage/main into each other in both directions, so a branch's first-parent chain wanders through its neighbours' history and reports the wrong date (it dated ABC-123's arrival on stage as 07-13 instead of 07-09). `git merge-base --is-ancestor` answers *whether*; the merged-PR list answers *when*. That is exactly what the script does — reach for it instead of ad-hoc archaeology.
