---
name: port-pr-to-branch
description: Port (cherry-pick) an existing GitHub PR from one branch to another (e.g. from `dev` onto `stage`, from `main` onto a release branch) as a brand-new PR, without rebasing or force-pushing shared branches. Use whenever the user asks to "port PR #X to <branch>", "cherry-pick PR to stage", "copy PR to another branch", "open a stage PR mirroring PR #X", "backport PR #X", or "apply PR #X on top of <branch>". Works across any repo that uses `gh` + `git` — not tied to a specific language or service. Trigger even if the user doesn't name the skill; any request of the form "take this merged/open PR and recreate it on another branch" is covered here.
---

# Port PR to Branch

Recreate an existing GitHub PR on a different base branch as a new PR, by cherry-picking its commits onto a fresh branch cut from the latest target. Language-agnostic. Safe by default.

## When to use

- "Port PR #3341 from dev to stage."
- "Cherry-pick this PR onto the release branch."
- "Open the same PR against stage."
- "Backport #1234 to the hotfix branch."

If the source PR is already merged, cherry-pick the commits from the PR itself (not the merge commit) to keep history clean.

## Non-negotiables

These are hard rules. Do not violate them without explicit user approval.

1. **No force-push.** Never `git push --force` or `--force-with-lease` to shared branches (`stage`, `dev`, `main`, `release/*`).
2. **No rebase of shared branches.** Don't `git rebase` onto or from shared branches in a way that rewrites their history.
3. **Don't modify the source PR.** No edits to its branch, commits, title, or body.
4. **Don't skip hooks.** Never `--no-verify`, `--no-gpg-sign`. If a hook fails, fix the cause.
5. **Dirty working tree → STOP.** If `git status` is not clean, report and stop. Do not `git stash` silently.
6. **Cherry-pick conflicts → ABORT and report.** Run `git cherry-pick --abort` and tell the user which commit and files conflicted. Never auto-resolve with `-X theirs` / `-X ours`.
7. **Don't invent naming or prefix conventions.** Check recent PRs on the target branch; follow what the repo already does.

## The 8-step procedure

Run these in order. Each command is copy-pasteable — substitute `<...>` placeholders.

### 1. Inspect the source PR

```bash
gh pr view <PR#> --json baseRefName,headRefName,title,body,commits
```

Capture from the output:
- `baseRefName` — original base branch (sanity check)
- `headRefName` — original feature branch name (basis for new branch name)
- `title`, `body` — to reuse verbatim on the new PR
- `commits[].oid` — exact SHAs, **in PR order**

### 2. Verify the target branch name

Don't guess. Confirm:

```bash
git branch -r | grep -iE 'stage|staging|release'
```

Different repos use `stage`, `staging`, `release`, `release/*`, etc.

### 3. Confirm clean working tree

```bash
git status
```

If anything is modified/untracked/staged → STOP and report. Do not stash.

### 4. Cut a new branch from the latest target

```bash
git fetch origin
git checkout -b <source-head>-<target> origin/<target>
```

**Naming convention:** mirror the source branch + `-<target>` suffix.

Example: source `feat/ABC-123`, target `stage` → new branch `feat/ABC-123-stage`.

If the repo has its own convention (e.g. `stage/feat/ABC-123`), follow that instead — check a few recent PRs targeting `<target>` first.

### 5. Cherry-pick the PR commits

```bash
git cherry-pick <sha1> <sha2> <sha3>
```

Rules:
- Use the SHAs from step 1, **in PR order**.
- Prefer cherry-picking **non-merge commits only**. The `commits` array from `gh pr view` already lists the PR's own commits (not the merge commit into the source base), so this is usually automatic.
- If the PR genuinely contains merge commits and you must pick one, use `-m 1` deliberately and explain it to the user.
- **On conflict:**
  ```bash
  git cherry-pick --abort
  ```
  Then report: which commit SHA, which files, and stop. Do not continue.

### 6. Push the new branch

```bash
git push -u origin <new-branch>
```

Never `--force`.

### 7. Open the new PR

```bash
gh pr create --base <target> --head <new-branch> \
  --title "<original title verbatim>" \
  --body "$(cat <<'EOF'
Ports #<source-PR>.

<original body>
EOF
)"
```

- Reuse the original title **verbatim** unless the repo convention adds a prefix (e.g. `[stage]`). Check recent PRs on the target branch.
- First line of the body: `Ports #<source-PR>.` — links back to the source.
- Do not add fabricated test plans or summaries beyond what was in the source PR.

### 8. Report back

Tell the user:
- New branch name
- New PR URL (from `gh pr create` output)
- Commits cherry-picked (SHAs and subjects)
- Any warnings (skipped merge commits, repo-specific prefix applied, etc.)

## Quick reference — full happy path

```bash
# 1. Inspect
gh pr view 3341 --json baseRefName,headRefName,title,body,commits

# 2. Confirm target
git branch -r | grep stage

# 3. Clean?
git status

# 4. Cut branch
git fetch origin
git checkout -b feat/ABC-123-stage origin/stage

# 5. Cherry-pick
git cherry-pick <sha1> <sha2>

# 6. Push
git push -u origin feat/ABC-123-stage

# 7. PR
gh pr create --base stage --head feat/ABC-123-stage \
  --title "<original title>" \
  --body "Ports #3341.\n\n<original body>"
```

## Anti-patterns

- ❌ `git stash` to hide a dirty tree and proceed anyway.
- ❌ `git cherry-pick -X theirs <sha>` to force through conflicts.
- ❌ `git push --force` after re-cherry-picking.
- ❌ Cherry-picking the PR's merge commit when individual commits are available.
- ❌ Rewriting or amending commits while porting ("just squashing them while I'm here").
- ❌ Creating the new branch off local `stage` without `git fetch origin` first.
- ❌ Inventing a title prefix like `[stage]` when the repo doesn't use one (or omitting it when it does).
