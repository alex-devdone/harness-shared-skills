# Syncing `~/.shared-skills` between machines

The pattern works on one machine without any of this. Add it when you have a
second machine — a desktop, a build box, anything you ssh into — and want an
agent there to be as capable as the one on your laptop.

This is the setup I actually run, including the two settings that are easy to
get wrong.

## Why Syncthing and not a cloud drive

- **It does not mangle symlinks or dot-directories.** iCloud and Dropbox both
  do, and this folder is nothing but dotfiles and executables.
- **`.stignore` gives per-path control**, which you need — some things in this
  folder must never leave the machine (see below).
- **Peer-to-peer, no cloud copy.** Your unpublished tooling is not sitting in
  someone else's bucket.
- **It preserves the executable bit**, which matters more than it sounds like
  (see `ignorePerms` below).

## Setup

### 1. Install on both machines

```bash
brew install syncthing && brew services start syncthing   # macOS
# Linux: your package manager, then `systemctl --user enable --now syncthing`
```

The web UI is at <http://127.0.0.1:8384>.

### 2. Pair the devices

On machine A: **Actions → Show ID**, copy it. On machine B: **Add Remote
Device**, paste. Accept the prompt back on A. They only need to reach each other
on some network — LAN, VPN, or via Syncthing's relays.

### 3. Add the folder on machine A

**Add Folder**, path `~/.shared-skills`, then set:

| Setting | Value | Why |
|---|---|---|
| Folder Type | `sendreceive` | Both machines edit skills. A one-way `sendonly` means fixing a typo on the desktop silently reverts. |
| Watch for Changes | **on**, delay `10s` | Edits propagate in seconds. Without it you wait for the rescan interval — up to an hour with a skill that is already wrong. |
| Full Rescan Interval | `3600s` | Fallback for anything the filesystem watcher misses. |
| **Ignore Permissions** | **`false`** | **The one that bites.** Skills contain scripts. With permissions ignored, an executable script arrives on the peer without its `+x` bit and every invocation fails with "permission denied" on a file that looks perfectly fine. |
| File Versioning | `staggered`, cleanup `3600s` | A bad edit syncs just as fast as a good one. Staggered versioning keeps old copies in `.stversions/` so a mistake is recoverable instead of replicated. |

Share it with machine B. Accept the invitation there and point it at
`~/.shared-skills`.

### 4. Install the ignore rules — before the first sync

On **each** machine, copy [`templates/stignore`](templates/stignore) to
`~/.shared-skills/.stignore`, and [`templates/stignore-shared`](templates/stignore-shared)
to `~/.shared-skills/.stignore-shared` (that one syncs, so you only author it
once).

Do this *before* the folders connect. Otherwise the first sync replicates
whatever is already in the directory — including `.git` — and you get to clean
up an index that two machines have been writing to.

## What must never sync

**`.git` — non-negotiable.** Two machines replicating one index will corrupt
it: one writes mid-operation while the other faithfully replicates a
half-written state. Each machine keeps its own `.git`. If you version this
folder (recommended, in a **private** repo), that repo is the *history* layer,
not the *transport* layer. Syncthing moves the working files; git records what
they were. Conflating those two roles is how you lose a week.

**Secrets.** `.env` and anything like it. Excluded from sync *and* gitignored —
two independent mechanisms, because you only need to be wrong once.

**Generated output.** Run-state, reports, `node_modules`, embeddings — anything
a skill produces rather than sources. Diverging between machines is correct for
these: a cooldown timestamp from the desktop is actively wrong on the laptop.

The rules live in [`templates/stignore-shared`](templates/stignore-shared). The
split matters: `.stignore` is per-device and does nothing but
`#include .stignore-shared`, which *is* synced — so shared rules reach every
peer automatically while machine-specific ones stay put.

## Verify it works

```bash
# on machine A
echo "sync check $(date)" > ~/.shared-skills/.synctest

# on machine B, within ~10s
cat ~/.shared-skills/.synctest

# executable bit survived? (the ignorePerms check)
ls -l ~/.shared-skills/<some-skill>/scripts/*.sh

# .git did NOT cross
ls ~/.shared-skills/.git 2>/dev/null && echo "each machine has its own — fine"
```

Then delete `.synctest` on either machine and confirm it disappears on the other.

## Gotchas

- **Conflicts are real.** Edit the same skill on both machines while they are
  disconnected and you get `<file>.sync-conflict-<date>-<device>.md`. They are
  excluded from sync and git, but check for them occasionally — a conflict file
  means you lost an edit somewhere:
  ```bash
  find ~/.shared-skills -name "*.sync-conflict-*"
  ```
- **The source of truth can never be a symlink.** A synced folder cannot hold a
  link pointing outside itself — the peer has no such path. So
  `~/.shared-skills/<name>` is always a real directory, and everything else
  points *at* it. This is why you copy a skill out to publish it, never
  relocate it.
- **Pause before large surgery.** Renaming or bulk-moving skills is much calmer
  with the folder paused on one side.
- **Device IDs are not secrets, but they are identifiers.** Don't paste yours
  into a public README.
