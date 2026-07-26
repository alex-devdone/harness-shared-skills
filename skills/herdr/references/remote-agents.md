# herdr agent detection & remote agents — field-verified knowledge (2026-07)

How herdr decides what shows up in the agents sidebar, why agents behind
ssh/tmux never appear on their own, and the tooling this machine has to fix
that. Everything here was verified empirically against herdr 0.7.1.

## How detection actually works

Two separate mechanisms, and the split matters:

- **The agent LABEL is process-gated.** herdr walks the pane's *local*
  process tree looking for known agent binaries. A pane running `ssh` (or
  `sshl`) only ever shows `ssh` — the remote claude's UI rendering in the
  pane is ignored for labeling. This is why remote agents never self-appear.
- **The agent STATE (idle/working/blocked) comes from screen-scraping
  rules** in per-agent TOML manifests at
  `~/.local/state/herdr/agent-detection/remote/<agent>.toml` — but those
  rules only drive state for *process-detected* agents.
- **Externally reported agents are reporter-owned.** After
  `herdr pane report-agent <pane> --source X --agent claude --state ...`,
  herdr shows exactly the reported state; the screen-rule engine does NOT
  update it, even when the screen changes. Whoever reports must keep
  reporting.
- `done` is a herdr-computed state ("finished, not yet viewed").
  `report-agent` cannot express it (only idle|working|blocked|unknown) —
  map done → idle when mirroring.

## Reporting API semantics

```bash
herdr pane report-agent <pane> --source <id> --agent claude --state idle|working|blocked|unknown
herdr pane release-agent <pane> --source <id> --agent claude
herdr agent rename <pane> <name>       # agent-level name shown in sidebar
herdr agent rename <pane> --clear
```

- The sidebar **name is agent-level and independent of the pane label** —
  herdr never copies the label. Set it with `agent rename` after the first
  successful report (renaming a pane with no agent fails).
- **Named-orphan gotcha:** a pane whose agent was released but still has an
  agent-level name keeps showing in the agents list as `unknown`. On
  release, also `agent rename <pane> --clear` (only if you set the name).
  herdr may eventually prune these, but don't rely on it.
- `pane report-agent-session` (what the official claude hook uses) needs a
  real `--agent-session-id`; without one it registers nothing.

## `agent explain` as a standalone detector

```bash
herdr agent explain --file <(herdr pane read <pane> --source visible | tail -12) --agent claude
```

- Runs the manifest screen rules over arbitrary text; prints `state:` and
  `rule:` lines (`--json` for full evaluation).
- **Fallback trap:** with `--agent claude` and NO matching rule, it prints
  `state: idle` with `rule: none` (`default_known_agent_idle_fallback`).
  Always check the `rule:` line — `none` means "no claude UI found", not
  idle.
- **Slice the screen bottom yourself** (`| tail -12`): `pane read --lines N`
  does not reliably return only the last N lines, and a dead claude's UI
  lingering higher in the buffer false-positives as idle otherwise.

## Remote Agent Watch plugin (the fix)

Linked herdr plugin at `~/work/herdr-remote-agent-watch/` (state in
`~/.local/state/herdr-remote-agent-watch/`, pidfile + name-flag per pane).
Pane actions "Watch this pane for a remote claude" / "Stop watching", or CLI:

```bash
watch.sh <pane_id>                          # scrape mode (ssh/tmux panes)
watch.sh --remote <host> <remote_sock> <pane_id>   # bridge mode
watch.sh --stop <pane_id>                   # stop + drop agent + clear name
```

- **Scrape mode:** event-driven — blocks on `herdr wait output` (so ~1s
  remote turns still flip status), evaluates bottom-12 lines via
  `agent explain --file`, reports via `report-agent`, names the agent from
  the pane label. Releases (agent + name) after 3 consecutive no-claude
  evaluations; re-registers automatically when a claude reappears.
- **Bridge mode:** when the remote host runs its own herdr, poll
  `ssh <host> "HERDR_SOCKET_PATH=<sock> herdr agent list"` — the remote
  herdr's *native* detection is the source of truth. Aggregate
  blocked > working > idle (done→idle) onto the local pane; no agents →
  release. Exact states, no scraping, works even when the remote UI isn't
  on the local screen.

## Pane-label ↔ agent-name sync

herdr never copies a pane label into the sidebar agent name (pane rename /
agent restart leave the name stale or unset → sidebar falls back to the
bare agent label). The coupling is one-directional the other way:
`agent rename` DOES also set the pane label. This machine set fixes it:

- Plugin action **"Sync agent names from pane labels"** /
  `watch.sh --sync-names` — one pass over every running local session,
  label wins.
- `watch.sh --sync-names-daemon` — foreground 5s loop, supervised by a
  launchd agent `dev.herdr.name-sync` (`~/Library/LaunchAgents/`) on
  every machine. So renaming a pane updates the sidebar name within ~5s
  everywhere, automatically.
- **launchd + external volume gotcha:** if the checkout lives on an external
  volume, launchd agents can't execute from it (macOS TCC → exit code 126,
  crash loop). Run the daemon from a script copy on the internal disk
  (e.g. `~/.herdr-name-sync.sh`) and re-copy watch.sh there when it changes.

## Wrappers that arm it automatically

- **`sshl [host]`** (ssh+tmux loop): starts scrape mode on its pane, stops
  it in the EXIT trap.
- **`herdrl <herdr args>`** (e.g. `herdrl --remote myhost --session
  my-session`): passthrough wrapper around `herdr` adding an
  sshl-style reconnect loop (backoff, terminal reset, rc 0/130 = clean
  quit) and bridge-mode mirroring. Socket discovery via
  `ssh <host> herdr session list`, retried in the background for ~2min —
  `herdr --remote` creates the session on first attach, so it may not
  exist at launch time.

## Messaging remote agents (claude-peers bridge)

Status in the sidebar is this plugin's job; **messaging** remote agents is the
claude-peers cross-machine relay's job. When the `peers-relay` launchd hub is
running, cldp sessions on remote hosts are addressable as `repo@host`
(`myrepo-wt-hotfix@myhost`) from any local mesh session, and `peers-here`
lists the peers of your herdr tab — including remote ones, matched by ssh-pane
labels that name the host. See the claude-peers skill
(`references/setup.md` → "Cross-machine relay", `references/orchestration.md` →
"Cross-machine workers").

## Remote herdr servers

```bash
ssh <host> herdr session list        # name | status | directory | socket
ssh <host> "HERDR_SOCKET_PATH=<sock> herdr agent list"   # drive any session
```

A remote host's default session socket is `~<user>/.config/herdr/herdr.sock`;
named sessions live under `~<user>/.config/herdr/sessions/<name>/herdr.sock`.
Note the remote `~` expands to the *remote* user's home — if their checkout is
on an external volume, the resolved path won't match yours.

## Pitfalls (all hit in practice)

- `herdr pane run <pane> "<prompt>"` into a **Claude Code prompt box**
  leaves the text unsubmitted — Claude treats text+immediate-Enter as a
  paste. Send the text, then a separate `pane send-keys <pane> Enter`.
- Concurrent ssh connections to a host with configured port-forwards spam
  "bind: Address already in use" warnings (harmless) and occasionally fail
  transiently — tolerate a few failed polls before releasing.
- The local claude manifest carries a local patch
  (`local_visible_working_timer`, version-bumped) because stock rules
  missed the current spinner format; deleting it regresses working-state
  detection.
- Community context (researched 2026-07): no upstream herdr support or
  other plugin does remote-agents-in-local-sidebar; the ecosystem's
  alternatives are running herdr on the remote box, Claude Code hooks
  pushing state (tmux-agent-status), or relay apps (herdr-remote, Happy).
