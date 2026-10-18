# Changelog

## 0.4.0 - 2026-10-18

- Renamed from afar-rcd to afar-cli: the command, its settings variables (AFAR_CLI_*), config and log folders (`~/.config/afar-cli`, `~/Library/Logs/afar-cli`), launchd labels (com.github.johannesreich1.afar-cli.*), the repository and the Homebrew formula. Services added with afar-rcd keep running under its labels; see "Coming from afar-rcd" in the README to move them over.
- The connection state no longer stays at `Reconnecting` after claude reconnects: "Reconnected after …" and "Ready" now count as `Connected`.
- `status --json` gives each session a `title`, the one the Claude app shows (schema 1). `status NAME` lists sessions by title.

## 0.3.0 - 2026-10-17

- Each service has a spawn mode: `same-dir` (the default for new services) or `worktree`. afar-rcd always passes it to `claude remote-control`, so Claude Code no longer asks "Choose [1/2]" during setup.
- `afar-rcd spawn NAME [same-dir|worktree]` shows or sets it, and restarts the service if it is running. `add --spawn MODE` sets it for a new service.
- Services added before 0.3.0 keep the mode Claude Code saved for their folder. `setup` writes it into the service's config.
- `status NAME` shows the spawn mode, and `status --json` has a new `spawn` field (schema 1).
- `setup` only lists the trust question when the folder isn't trusted yet.

## 0.2.0 - 2026-10-16

- launchd labels moved to com.github.johannesreich1.afar-rcd.NAME, like Afar's bundle id.

## 0.1.0 - 2026-10-16

First release.

- `afar-rcd add` serves a folder with `claude remote-control` as a per-user launchd agent that starts at login.
- A supervisor restarts Remote Control with backoff when it exits, and keeps the Mac awake with `caffeinate` while it runs.
- Detects when Remote Control needs its one-time confirmation, folder trust or a sign-in, and waits instead of looping.
- `setup` walks through the one-time questions; `add` runs it for you when needed.
- `status`, `logs`, `open`, `start`, `stop`, `restart`, `remove` and `doctor`.
- `doctor` and `add` check for Claude Code and offer to install it with the official installer.
- Uses only tools that ship with macOS.
- Watches for Claude Code's sign-in renewal warning while it runs, and handles the final `Authentication failed (401)` stop: status `needs-login`, a notification, and an automatic restart once you sign in again.
- Notifications repeat at most every 6 hours while a problem lasts.
- Logs claude's output as plain timestamped lines, without the status block it redraws every second, and rotates the log at 10 MB.
- `status` shows connection state and connected sessions; `status --json` prints the same for scripts (schema 1).
- `stop`, `restart` and `remove` say when they interrupt connected sessions.
- `doctor` explains whether services come back by themselves after the Mac restarts.
