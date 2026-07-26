---
name: raycast-macos-extensions
description: Build Raycast extensions with deep macOS integration. Covers menu-bar commands (lifecycle, the double render per launch, isLoading to stay resident, animating the icon without reflowing the bar, headless screenshot testing), background polling, detached process spawning (ffmpeg, Swift binaries, tsx workers), LocalStorage/Cache state across ticks, CoreAudio aggregate devices, IOHIDManager hardware event interception, and Raycast deeplinks. Use when building or debugging Raycast extensions, especially menu-bar commands, macOS system APIs, audio routing, or background processes.
---

# Raycast macOS Extensions

Guidance for building Raycast extensions that integrate deeply with macOS — background processes, system audio, hardware events, and native Swift binaries.

## Menu-Bar Commands

### Lifecycle — read this before writing any timer

A background-launched menu-bar command **renders once and is then unloaded**. A
`setInterval` in a `useEffect` will not fire; the rendered menu bar item simply
persists after the process dies. `package.json`'s `"interval"` (minimum `"10s"`)
is what re-runs it, and background refresh has a **9-second execution timeout**.

Two consequences that cost real debugging time:

**1. State does not survive between ticks — use `Cache`.** Each tick is a fresh
process. Anything incremental (file byte offsets, running totals, animation
frames) has to round-trip through `Cache` or `LocalStorage`.

**2. The component renders TWICE per launch, ~15ms apart.** So a counter
incremented during render advances by two every tick:

```
19:22:39.595 tick=39   19:22:50.300 tick=41   ← +2 per tick, parity never changes
19:22:39.615 tick=40   19:22:50.311 tick=42
```

Anything alternating off `count % 2` therefore looks frozen. Derive from
elapsed time and guard the repeat render instead:

```typescript
/** Flip once per tick; the repeat render inside the same tick is a no-op. */
export function nextFrame(frames: string[], stored: string | undefined, now: number, minGapMs = 5000) {
  const [cur, at] = (stored ?? "").split(":");
  const i = frames.indexOf(cur);
  if (i >= 0 && now - Number(at) < minGapMs) return { frame: cur, stored: stored! };
  const frame = frames[(i + 1) % frames.length];
  return { frame, stored: `${frame}:${now}` };
}
```

### Keeping the command alive (`isLoading`)

`isLoading` means "do not unload me", not just "show a spinner". It is the only
way to keep a menu-bar command resident so a `setInterval` can drive real
animation — verified at 400ms for 28s with no kill. Cost: a resident node
process, and Raycast then **skips its own background tick** (`Skipping
background load, userInitiated command is loaded`), so the component must
refresh its own data or the UI freezes. Scope it to the state that needs it:

```tsx
useEffect(() => {
  if (!needsAttention) return;              // otherwise stay unloaded = free
  const anim = setInterval(() => setFrame((f) => f + 1), 400);
  const refresh = setInterval(() => setData(loadSafe()), 10_000);
  return () => { clearInterval(anim); clearInterval(refresh); };
}, [needsAttention]);

<MenuBarExtra isLoading={needsAttention} … />
```

Prefer riding the existing 10s tick when a slow blink is enough — no resident
process, no self-refresh, much less to go wrong.

### Title and icon

- **Never animate the `title` with emoji.** Glyphs don't share an advance width
  (`✋` vs `👋`), so the item resizes and shoves every menu bar item left/right
  on each frame. Geometric Shapes (`●○◐◓`, `◴◷◶◵`) do share one width.
- **Swapping `icon` never reflows** — menu bar icons are normalised to a fixed
  box. Preferred way to signal state.
- **`tintColor` only works on template images.** On a normal coloured PNG it
  flattens the artwork into a single-colour silhouette. To recolour real
  artwork, render a second asset from the SVG source instead:
  ```bash
  sed 's/#d9dad8/#ffcc00/' logo.svg > alert.svg
  rsvg-convert -w 256 -h 256 -o assets/icon-alert.png alert.svg
  ```

### Testing menu-bar UI without a GUI

The menu bar can be verified headlessly — do this rather than guessing:

```bash
npm run dev &                                  # ray develop, hot-reloads on save
screencapture -x -R1050,0,320,26 /tmp/bar.png  # -R x,y,w,h crops the menu bar
```

Read the PNG back to confirm what actually rendered. For state you can't
produce on demand (an agent blocked, a timer firing), temporarily force the
branch (`… .length || 1; // TEMP`), screenshot, then revert. To confirm a
render loop is running at all, `appendFileSync` a timestamp per render — that's
what exposed the double render above.

**Critical constraints:**
- Never call blocking CLI tools (e.g., `osascript`, `open`) in the background refresh path
- Use `execSync` with explicit `timeout` on every call
- Prefer `LocalStorage`/`Cache` reads over filesystem checks for state
- Wrap the whole load in try/catch — a background launch must never throw

## LocalStorage State Management

Persist recording/process state across Raycast restarts using `LocalStorage`. Do not use the filesystem for state that must survive process boundaries.

```typescript
interface ProcessState {
  pid: number;
  filePath: string;
  startedAt: string;
  previousDeviceId?: string;
  monitorPid?: number;
}

// Save
await LocalStorage.setItem("state-key", JSON.stringify(state));

// Load
const json = await LocalStorage.getItem<string>("state-key");
const state: ProcessState = json ? JSON.parse(json) : null;

// Cleanup
await LocalStorage.removeItem("state-key");
```

**Pattern:** Store PIDs of all detached processes in state so they can be killed on stop.

## Detached Process Spawning

Spawn long-running processes that outlive Raycast's lifecycle:

```typescript
import { spawn } from "child_process";

const proc = spawn(binaryPath, args, {
  detached: true,
  stdio: "ignore",  // or redirect to log file
});
proc.unref();

if (!proc.pid) throw new Error("Failed to start process");
// Store proc.pid in LocalStorage
```

**For log-visible workers** (redirect stdout/stderr to file):

```typescript
import { openSync } from "fs";

const logFd = openSync(logPath, "a");
const proc = spawn(binaryPath, args, {
  detached: true,
  stdio: ["ignore", logFd, logFd],
});
proc.unref();
```

**Killing detached processes:**

```typescript
try {
  process.kill(pid, "SIGTERM"); // or "SIGINT" for graceful ffmpeg shutdown
} catch {
  // Fallback for processes that escaped Node's process group
  try {
    execSync(`kill -TERM ${pid} 2>/dev/null`, { timeout: 2000 });
  } catch { /* already exited */ }
}
```

**Process liveness check:**

```typescript
function isProcessRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    try {
      execSync(`kill -0 ${pid} 2>/dev/null`, { timeout: 2000 });
      return true;
    } catch {
      return false;
    }
  }
}
```

## Deeplink-Based Command Launching

Launch a Raycast command programmatically from another command:

```typescript
import { launchCommand, LaunchType } from "@raycast/api";

await launchCommand({
  name: "confirm-recording",
  type: LaunchType.UserInitiated,
  context: { meetingTitle: "Standup" },
});
```

## Native Swift Binaries

For macOS system APIs not available from Node.js (CoreAudio, IOKit, etc.), compile Swift helpers as standalone binaries.

**Compile:** `swiftc source.swift -o binary -framework CoreAudio -framework IOKit`

**Call from TypeScript:**

```typescript
const result = execSync(`"${binaryPath}" create`, {
  encoding: "utf-8",
  timeout: 5000,
}).trim();
```

See [references/coreaudio-patterns.md](references/coreaudio-patterns.md) for CoreAudio aggregate device creation, volume control, and IOHIDManager patterns.

## execSync Gotchas

**Always set timeout:**
```typescript
execSync(cmd, { encoding: "utf-8", timeout: 5000 });
```

**Commands that exit non-zero by design** (e.g., `ffmpeg -list_devices`):
```typescript
const output = execSync(`${cmd} 2>&1 || true`, { encoding: "utf-8" });
```

**Prefer `execFile` over `exec`** when arguments don't need shell expansion — ~16ms faster and avoids shell injection.

## Incremental File Writing

Write output files in two passes for progressive UX:

1. Write initial content immediately (e.g., transcript with placeholder summary)
2. Overwrite with complete content after async processing finishes

This lets users see partial results while expensive operations (API calls) complete.

## Debugging Detached Workers

Workers spawned with `detached: true` and `stdio: "ignore"` produce no visible output. Use a shared logger that writes to a file:

```typescript
const LOG_PATH = join(homedir(), "Library/Logs/app-name/worker.log");

export function log(msg: string) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  appendFileSync(LOG_PATH, line);
  console.log(msg); // also visible in Raycast dev terminal
}
```

**Debugging checklist:**
- Check `tail -f ~/Library/Logs/app-name/worker.log`
- Verify process is running: `pgrep -af worker-name`
- Check for stale flag/lock files
- If a worker crashes before cleanup, manually remove flag files

## macOS Permissions

| Capability | Permission Required |
|---|---|
| `NSEvent.addGlobalMonitorForEvents` | Input Monitoring (Accessibility) |
| `CGEvent.tapCreate` | Accessibility |
| `IOHIDManagerCreate` | None (for standard HID devices) |
| CoreAudio device creation | None |
| Microphone recording | Microphone access |
| `osascript` for AppleScript | Automation permission per target app |
