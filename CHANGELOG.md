# Changelog

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
