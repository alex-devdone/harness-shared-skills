---
name: shared-skill
description: Manage shared skills that live in ~/.shared-skills/ and are symlinked into project .claude/skills/ directories. Use this skill when the user wants to share a skill across projects, link/unlink skills, move a project or global skill to shared, or see which projects use a shared skill. Trigger on "shared skill", "share skill", "link skill", "symlink skill", "move skill to shared", or when discussing skill sharing across projects.
---

# Shared Skill Manager

Manages skills that are shared across multiple projects via symlinks. Shared
skills live in `~/.shared-skills/<name>/` and are symlinked into each project's
`.claude/skills/` directory. This keeps one source of truth while making the
skill available per-project — and invisible to git.

## How it works

```
~/.shared-skills/           # Source of truth (shared skills live here)
  my-shared-skill/
  another-shared-skill/

project-a/.claude/skills/
  my-shared-skill -> ~/.shared-skills/my-shared-skill    # symlink
  project-only-skill/                                     # real project skill

project-b/.claude/skills/
  my-shared-skill -> ~/.shared-skills/my-shared-skill    # same shared skill
```

## Operations

### List shared skills

```bash
ls -1 ~/.shared-skills/
```

To see which projects use each shared skill:
```bash
find ~ -path "*/.claude/skills/*" -type l -exec sh -c 'readlink "$1" | grep -q ".shared-skills" && echo "$1 -> $(readlink "$1")"' _ {} \;
```

### Link a shared skill to a project

Steps (run in order):

1. Create the symlink:
```bash
ln -s ~/.shared-skills/<name> <project>/.claude/skills/<name>
```

2. If the project is a git repo, check if the path is tracked:
```bash
cd <project> && git ls-files .claude/skills/<name>
```

3. If files are tracked, remove them from the git index (keeps the symlink on disk):
```bash
cd <project> && git rm --cached -r .claude/skills/<name>/
```

4. Add to `.git/info/exclude` so git ignores the symlink going forward:
```bash
echo ".claude/skills/<name>" >> <project>/.git/info/exclude
```

### Unlink a shared skill from a project

Remove the symlink (the shared source stays intact):
```bash
unlink <project>/.claude/skills/<name>
```

Optionally clean up the exclude entry:
```bash
sed -i '' '/.claude\/skills\/<name>/d' <project>/.git/info/exclude
```

### Move a project skill to shared

This takes a skill that currently lives only in one project and makes it shared:

1. Move the skill directory to the shared location:
```bash
mv <project>/.claude/skills/<name> ~/.shared-skills/<name>
```

2. Create a symlink back:
```bash
ln -s ~/.shared-skills/<name> <project>/.claude/skills/<name>
```

3. Handle git (same as the link operation — check tracking, `git rm --cached`, add to exclude).

### Move a global skill to shared

This takes a skill from `~/.claude/skills/` and makes it shared, optionally
linking it to specific projects:

1. Move from global to shared:
```bash
mv ~/.claude/skills/<name> ~/.shared-skills/<name>
```

2. For each project that should have it, run the **Link** steps above.

## Naming convention

- Project-specific shared skills must include the service name:
  `dep-graph-myservice`, `api-patterns-backend`. This prevents ambiguity when
  multiple projects share `~/.shared-skills/`.
- Generic shared skills that apply to any project keep simple names: `recharts`,
  `ffmpeg`, `mermaid-diagrams`.
- The **symlink name must match the shared skill directory name** exactly. For
  example, if `~/.shared-skills/dep-graph-myservice` exists, the symlink must be
  `.claude/skills/dep-graph-myservice`, not `.claude/skills/dep-graph`.

## Important notes

- Always use **absolute paths** for symlinks (e.g. `$HOME/.shared-skills/<name>`,
  expanded — not a literal `~` inside a script) to avoid breakage if the project
  moves. Never use relative paths like `../../.shared-skills/`.
- Use `.git/info/exclude` (not `.gitignore`) to keep git-ignore rules local and
  uncommitted. A `.gitignore` entry would itself be committed, telling everyone
  on the team about a path only you have.
- The `git rm --cached` step is only needed if the skill was previously
  committed. Check with `git ls-files` first.
- Before any destructive operation (move, unlink), confirm with the user what
  will happen.
- After linking, verify the symlink works: `ls <project>/.claude/skills/<name>/`
  should show the skill contents.
- When linking to worktrees, apply the same symlink to all worktrees of the same
  repo — a new worktree starts with an empty `.claude/skills/`, so nothing is
  inherited.
