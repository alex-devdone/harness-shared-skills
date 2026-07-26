---
name: tmux
description: Work with a tmux setup — windows, panes/split screens, session persistence, and the custom hotkeys defined in ~/.tmux.conf (the reference config ships alongside this skill). Use when the user asks to split a screen, manage tmux windows/panes, swap panes, restore a session, or asks "what's my tmux shortcut for X".
---

# tmux

Reference for a tmux environment tuned for long-running AI agents. The config
this documents ships next to this file as [`tmux.conf`](tmux.conf) — copy it to
`~/.tmux.conf` to get the hotkeys and badges described below. After editing,
reload with `tmux source-file ~/.tmux.conf` (or prefix + `:source-file ~/.tmux.conf`).

## Environment summary

- **Prefix:** `C-b` (default — referred to below as `<prefix>`).
- **Mouse mode:** ON — click to select panes/windows, drag borders to resize, scroll to enter copy-mode.
- **Plugins** (via [TPM](https://github.com/tmux-plugins/tpm)):
  - `tmux-resurrect` — manual save/restore of sessions.
  - `tmux-continuum` — **auto-saves every 15 min** and **auto-restores on tmux server start**. Pane contents are captured (`@resurrect-capture-pane-contents`), so scrollback survives a reboot.
- TPM bindings: `<prefix> I` install plugins, `<prefix> U` update, `<prefix> alt-u` uninstall.

## Custom hotkeys (no prefix needed — `bind -n`)

Defined by the bundled [`tmux.conf`](tmux.conf). They work **without** pressing
the prefix first.

| Keys | Action |
|------|--------|
| `Shift-Left` | Swap current pane with the previous one (`swap-pane -U`) — moves the pane *up*/toward start. |
| `Shift-Right` | Swap current pane with the next one (`swap-pane -D`) — moves the pane *down*/toward end. |
| `Shift-Alt-Down` | New split **below**, spanning the **full width** of the window (`split-window -v -f`), opened in the current pane's directory. |
| `Shift-Alt-Right` | New split to the **right**, spanning the **full height** of the window (`split-window -h -f`), opened in the current pane's directory. |
| `Shift-Enter` | Send a literal newline to the current pane (useful for REPLs/agents that treat Enter as submit). |

Note the `-f` flag: these splits are full-window, not just splitting the current pane — good for adding a wide log pane or a tall side panel.

### Notification badges on window tabs

The config carries a small badge system for agent work. A window's `@noti`
counter is bumped by [`bin/tmux-badge`](bin/tmux-badge) and rendered in that
window's status tab; visiting the window clears it via the
`session-window-changed` hook.

Wire it to whatever signals "an agent wants you": a Claude Code hook, a build
finishing, a test run failing.

```bash
cp bin/tmux-badge ~/.local/bin/tmux-badge   # anywhere on PATH
tmux-badge                                   # bump the badge on this pane's window
```

It no-ops outside tmux and deliberately skips the window you are already
looking at — a badge on the window in front of you is noise.

## Common default tmux commands (prefix-based)

The config keeps tmux defaults for most things. Frequently used:

### Panes / split screens
- `<prefix> %` — split vertically (left/right).
- `<prefix> "` — split horizontally (top/bottom).
- `<prefix> <arrow>` — move focus between panes (or just click, mouse is on).
- `<prefix> z` — zoom/unzoom the current pane to fullscreen.
- `<prefix> x` — kill the current pane (confirm).
- `<prefix> {` / `<prefix> }` — move pane left / right in the layout.
- `<prefix> Space` — cycle preset layouts (even-horizontal, even-vertical, main-vertical, tiled…).
- `<prefix> <prefix> arrow`-style resize: `<prefix> :resize-pane -D 10` etc. (or drag borders with the mouse).
- `<prefix> !` — break the current pane out into its own window.

### Windows
- `<prefix> c` — create a new window.
- `<prefix> ,` — rename the current window.
- `<prefix> n` / `<prefix> p` — next / previous window.
- `<prefix> <number>` — jump to window N.
- `<prefix> w` — interactive window/session tree.
- `<prefix> &` — kill the current window (confirm).
- `<prefix> .` — move window to a different index.

### Sessions
- `<prefix> d` — detach (session keeps running).
- `tmux ls` — list sessions; `tmux attach -t <name>` — re-attach.
- `<prefix> s` — interactive session switcher.
- `<prefix> $` — rename the session.

### Copy mode (mouse-scroll also enters it)
- `<prefix> [` — enter copy mode; arrows / PageUp to navigate; `q` to exit.
- `Space` start selection, `Enter` copy, `<prefix> ]` paste.

### Session persistence (resurrect / continuum)
- `<prefix> Ctrl-s` — **manually save** the session now.
- `<prefix> Ctrl-r` — **manually restore** the last saved session.
- Auto-restore happens automatically when the tmux server starts (continuum), so after a reboot just run `tmux` and the layout/sessions come back.

## Advanced / scripting commands (from tmux docs)

Power-user commands beyond the basics — useful for automation and larger layouts.

### Panes — reorganize & automate
- `tmux swap-pane -s <src> -t <dst>` — swap two arbitrary panes.
- `tmux join-pane -s <src> -t <window>` — pull a pane from another window in (inverse of split). `move-pane` is the same with `-s`.
- `tmux break-pane` — `<prefix> !`; split a pane out into its own window.
- `tmux rotate-window` — cycle all panes through positions.
- `<prefix> q` — show pane numbers; press the number to jump. `<prefix> ;` jumps to the last-active pane.
- `tmux respawn-pane -k -c <cwd> 'cmd'` — restart a dead/exited pane with a new command.
- `tmux capture-pane -p -S -<N>` — dump the last N scrollback lines to stdout (great for grabbing build output).
- `tmux pipe-pane 'cat >> ~/tmux.log'` — continuously tee a pane's output to a file; run again to stop.
- `tmux send-keys -t <pane> "cmd" Enter` — script keystrokes into a pane.

### Pane synchronization (type into all panes at once)
- `<prefix> :setw synchronize-panes on` (and `off`) — broadcast keystrokes to every pane in the window. Handy for running the same command on several SSH sessions.

### Windows across sessions
- `tmux link-window -s <src>:<i> -t <dst>:<i>` — show one window in multiple sessions; `unlink-window` to detach.
- `tmux move-window -s <src> -t <dst>` — move/renumber a window.
- `tmux choose-tree -s` — interactive session/window tree with live preview (richer than `<prefix> w`).

### Copy mode (vi-style nav once inside `<prefix> [`)
- `/` `?` search forward/back, `n`/`N` next/prev match, `g`/`G` top/bottom, `Ctrl-b`/`Ctrl-f` page.
- Buffers: `tmux list-buffers`, `tmux save-buffer <file>`, `tmux load-buffer <file>`, `<prefix> #` list, `<prefix> -` delete newest.

### Misc / introspection
- `tmux display-popup -w 60% -h 60% -E "<cmd>"` — floating popup window running a command (e.g. a quick lazygit/htop overlay).
- `tmux command-prompt -p "x:" "<cmd> %1"` — prompt for input and feed it into a command.
- `tmux list-keys` / `<prefix> ?` — list all bindings; `tmux list-keys -T copy-mode-vi` for copy-mode.
- `tmux show-options -g` / `-w` / `-s` — inspect global / window / session options.
- `tmux new-session -d -s NAME -x 200 -y 50 'cmd'` — scripted detached session with explicit size.
- `tmux run-shell "<cmd>"` — run a shell command from tmux (used for plugin/init hooks).
- `<prefix> t` clock, `<prefix> :` command prompt, `<prefix> ~` message log.

## When applying this skill

- If the user asks for a shortcut by intent ("how do I split full-width below"), give the **custom** binding first (`Shift-Alt-Down`) since it differs from vanilla tmux — but confirm their `~/.tmux.conf` actually has it; the custom bindings come from the bundled config.
- When editing `~/.tmux.conf`, preserve the `run-shell '~/.tmux/plugins/tpm/tpm'` line at the very bottom — TPM init must stay last — and remind the user to reload + `<prefix> I` if a new plugin was added.
- `bind -n` means no prefix; `bind` means prefix-first. Keep that distinction when documenting or adding bindings.
