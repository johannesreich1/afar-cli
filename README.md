# afar-rcd

[![CI](https://github.com/johannesreich1/afar-rcd/actions/workflows/ci.yml/badge.svg)](https://github.com/johannesreich1/afar-rcd/actions/workflows/ci.yml)

Keep [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control) running in the background on your Mac, so you can reach your projects from the Claude app or [claude.ai/code](https://claude.ai/code) at any time without leaving a terminal open.

`claude remote-control` runs only as long as the terminal that started it. Close the window, log out or restart, and your sessions go offline. Claude Code has no daemon mode for it ([the feature request](https://github.com/anthropics/claude-code/issues/77719) was closed as not planned). afar-rcd adds one:

- **Runs in the background** as a per-user launchd agent. No terminal needed.
- **Starts at login** and **restarts on its own** when Remote Control exits, with backoff. That includes after a long network outage, which makes `claude remote-control` give up after about 10 minutes.
- **Keeps the Mac awake** with `caffeinate` while it runs. Choose always, only on power, or never.
- **Tells you when it needs you**: when Remote Control needs its one-time confirmation, folder trust or a new sign-in, afar-rcd shows it in `status` and sends a notification, then waits instead of crash-looping. It also catches Claude Code's warning that it can't renew its sign-in, which comes about a day before Remote Control stops, and resumes by itself once you sign in again.
- **Several projects**: one service per folder, each with its own readable log and a live count of connected sessions.
- **Scriptable**: `afar-rcd status --json` for menu bar apps, scripts and monitoring.
- **Nothing extra to install**: a single bash script that uses only tools that come with macOS. If Claude Code itself is missing, afar-rcd offers to install it with the official installer.

> afar-rcd is a community project. It is not affiliated with or endorsed by Anthropic.

## Requirements

- macOS (tested on macOS 27; uses only long-standing tools such as `launchctl`, `caffeinate` and `osascript`)
- [Claude Code](https://code.claude.com/docs/en/setup), signed in with a claude.ai subscription (Pro, Max, Team or Enterprise), which Remote Control needs. afar-rcd offers to install Claude Code and sign you in if needed.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/johannesreich1/afar-rcd/main/install.sh | bash
```

This puts `afar-rcd` in `~/.local/bin` (the same place Claude Code's installer uses) and then runs `afar-rcd doctor`, which checks for Claude Code and your sign-in and offers to fix what is missing.

With Homebrew (this repository is also its tap):

```bash
brew tap johannesreich1/afar-rcd https://github.com/johannesreich1/afar-rcd
brew install johannesreich1/afar-rcd/afar-rcd
afar-rcd doctor
```

From a clone:

```bash
git clone https://github.com/johannesreich1/afar-rcd.git
cd afar-rcd
./install.sh
```

## Quick start

```bash
afar-rcd add ~/Projects/my-app
```

The first time, Remote Control asks a few one-time questions. afar-rcd runs it in your terminal so you can answer them, then hands over to the background service:

- **"Trust ~/Projects/my-app?"**, only for a folder Claude Code has never opened: answer **y**.
- **"Enable Remote Control? (y/n)"**: answer **y**.

Claude Code doesn't ask for a spawn mode ("Choose [1/2]"), because afar-rcd always passes one (see [Spawn mode](#spawn-mode)). Then you see:

```text
✔ Added 'my-app' for ~/Projects/my-app
✔ 'my-app' is running in the background.
  Session: https://claude.ai/code/session_...
  Connect from the Claude app (Code tab) or https://claude.ai/code. It starts at login and restarts on its own.
```

Open the **Code** tab in the Claude app on your phone, or [claude.ai/code](https://claude.ai/code) in a browser, and pick the session. You can close the terminal now.

## Commands

| Command | What it does |
| --- | --- |
| `afar-rcd add [FOLDER]` | Serve a folder (default: the current one) as a background service and start it |
| `afar-rcd status [NAME]` | List services, or show details for one: session link, connection, connected sessions |
| `afar-rcd status [NAME] --json` | The same as JSON, for scripts (see [JSON status](#json-status)) |
| `afar-rcd logs NAME [-f]` | Show a service's log (`-f` follows it) |
| `afar-rcd open [NAME]` | Open the service's session in your browser |
| `afar-rcd stop NAME` | Stop a service. It stays stopped, even after a restart, until you start it |
| `afar-rcd start NAME` | Start a stopped service |
| `afar-rcd restart NAME` | Restart a service |
| `afar-rcd spawn [NAME] [same-dir\|worktree]` | Show or set where new sessions work (see [Spawn mode](#spawn-mode)) |
| `afar-rcd setup [NAME]` | Answer Remote Control's one-time questions for a service |
| `afar-rcd remove NAME` | Stop a service and delete it |
| `afar-rcd doctor` | Check Claude Code, your sign-in and every service |

`NAME` can also be the service's folder, and you can leave it out when you have only one service. `start`, `stop`, `restart` and `remove` also take `--all`.

### Options for `add`

```bash
afar-rcd add ~/Projects/my-app --name app --keep-awake ac --spawn worktree -- --capacity 4
```

- `--name NAME`: service name (default: made from the folder name).
- `--keep-awake always|ac|off`: `always` (default) stops idle sleep, on battery too. `ac` keeps the Mac awake only while it is on power. `off` lets it sleep as usual. Remote Control reconnects after the Mac wakes up.
- `--spawn same-dir|worktree`: where new sessions work (default: `same-dir`, see [Spawn mode](#spawn-mode)).
- `--no-start`: install the service without starting it.
- `--yes`: answer yes to questions, such as installing Claude Code.
- `-- ARGS...`: passed to `claude remote-control`, for example:
  - `--capacity 4` limits how many sessions run at once.
  - `--permission-mode acceptEdits` sets the permission mode for new sessions.
  - `--name "My app"` names the first session.

  Run `claude remote-control --help` for the full list.

To change a service later, edit its config in `~/.config/afar-rcd/services/NAME.conf`, then run `afar-rcd restart NAME`.

### Spawn mode

The spawn mode decides where sessions you start from the Claude app or claude.ai/code work. It applies to all sessions of a service, not one at a time:

- `same-dir` (the default): every session works in the folder itself, on the same files.
- `worktree`: each new session gets its own git worktree under `.claude/worktrees`, on its own branch, so parallel sessions can't edit each other's files. Their changes stay on that branch until you merge them. It needs a git repository.

```bash
afar-rcd spawn my-app            # prints the mode
afar-rcd spawn my-app worktree   # sets it
```

Setting it restarts the service if it is running, which interrupts its connected sessions for a few seconds. afar-rcd always passes the mode to `claude remote-control`, so Claude Code never asks "Choose [1/2]". A service added before 0.3.0 keeps the mode Claude Code saved for its folder, if any, else `same-dir`. `status NAME` and `status --json` show the mode.

## How it works

```text
launchd (starts at login, restarts the supervisor if it dies)
└── afar-rcd _run NAME              supervisor: restart with backoff, notifications
    ├── claude remote-control       in the service's folder
    │   └── claude (one per session)
    ├── caffeinate -i -w <pid>      keeps the Mac awake while claude runs
    ├── log filter (awk)            turns claude's screen output into log lines
    └── sign-in watcher             spots sign-in problems while claude runs
```

- Each service is a launchd agent, `~/Library/LaunchAgents/com.github.johannesreich1.afar-rcd.NAME.plist`.
- The supervisor stops Remote Control the way Ctrl+C does. Sessions it was serving stay resumable, and the next start in the same folder brings them back (Claude Code keeps them for about four hours).
- If Remote Control exits, the supervisor restarts it after 5 seconds, doubling the wait up to 5 minutes while it keeps failing. A run that lasts 5 minutes resets the wait.
- If Remote Control needs the one-time confirmation or folder trust, the service waits, retries every 10 minutes and sends one notification. If you are signed out, it waits until you sign in again.
- Logs go to `~/Library/Logs/afar-rcd/NAME.log` (also visible in Console.app). Even without a terminal, claude redraws its status block every second, so afar-rcd logs only what changed, as plain timestamped lines, and rotates the log at 10 MB.
- The service runs with the `PATH` of the shell you ran `add` in, so your tools are available to Claude.

## When something needs you

afar-rcd sends a macOS notification (at most every 6 hours while the problem lasts) and shows the problem in `afar-rcd status`:

- **Sign-in running out.** Claude Code renews Remote Control's connection with your saved claude.ai sign-in. If claude.ai stops accepting it, Claude Code warns but keeps working for about a day, then stops with `Authentication failed (401)`. afar-rcd watches for the warning, so you have that day to run `claude auth login`. The status turns to `needs-login` while claude still runs. Once you sign in, the service notices the new sign-in and carries on, or restarts if claude had already stopped.
- **Signed out.** The service waits for `claude auth login`, then starts by itself.
- **Remote Control not enabled, or folder not trusted.** Run `afar-rcd setup NAME`.
- **Keeps stopping.** After five quick exits in a row you get a notification. See `afar-rcd logs NAME`.

Notifications come from **Script Editor**, which runs the AppleScript behind them. If you don't see them, allow notifications for Script Editor in **System Settings → Notifications**.

## Staying reachable

- **Log in.** launchd agents start when you log in, and all your services come back with the same session links. With FileVault on, macOS cannot log in by itself, so after a restart the services start once you log in. For a planned restart, `sudo fdesetup authrestart` restarts and unlocks the disk once without the login screen. Without FileVault, turn on automatic login (**System Settings → Users & Groups**) to have the Mac come back unattended. `afar-rcd doctor` tells you which applies to your Mac.
- **Laptops sleep when the lid closes**, whatever `caffeinate` does, unless an external display, keyboard and power are connected. Desktop Macs such as a Mac mini are the easiest always-on host.
- **"Background item added"** notifications from macOS are expected when a service is added. If you turn afar-rcd off under **System Settings → General → Login Items & Extensions**, launchd will not start it.
- **Protected folders.** Folders such as Desktop, Documents and Downloads are protected by macOS privacy controls, and background processes may not get access to them. Keep projects somewhere like `~/Projects`, or grant access in **System Settings → Privacy & Security**.

## Troubleshooting

Start with:

```bash
afar-rcd status NAME
afar-rcd logs NAME
afar-rcd doctor
```

| Status | Meaning | Fix |
| --- | --- | --- |
| `running` | Remote Control is up | Nothing to do |
| `needs-login` while it still has a pid | Claude Code can't renew its sign-in and will stop in about a day | `claude auth login` |
| `needs-setup` | Remote Control needs its one-time confirmation, or the folder is not trusted yet | `afar-rcd setup NAME` |
| `needs-login` | Claude Code is signed out, or its sign-in ran out | `claude auth login` (the service resumes by itself) |
| `restarting` | Remote Control exited and will be restarted | Check `afar-rcd logs NAME` |
| `error` | Folder or Claude Code missing | See the message in `afar-rcd status NAME` |
| `stopped` | Stopped with `afar-rcd stop` | `afar-rcd start NAME` |

## JSON status

`afar-rcd status --json` (or `status NAME --json`) prints one JSON object, for example for a menu bar app:

```json
{"schema": 1, "version": "0.3.0", "services": [{
  "name": "my-app", "folder": "/Users/me/Projects/my-app", "state": "running",
  "connection": "Connected", "pid": 54892, "since": 1792160683,
  "url": "https://claude.ai/code?environment=env_...", "message": null,
  "keep_awake": "always", "spawn": "same-dir", "log": "/Users/me/Library/Logs/afar-rcd/my-app.log",
  "session_count": 1,
  "sessions": [{"id": "session_...", "name": "...", "url": "https://claude.ai/code/session_...",
                "status": "busy", "since": 1792161505, "pid": 54971}]
}]}
```

- `state` is one of `running`, `starting`, `restarting`, `needs-setup`, `needs-login`, `error` or `stopped`. `needs-login` can appear while claude still runs (see [When something needs you](#when-something-needs-you)).
- `connection` is `Connected`, `Connecting`, `Reconnecting` or `Disconnected` as claude reports it, or `null`.
- `spawn` is the [spawn mode](#spawn-mode) the service runs with: `same-dir`, `worktree`, or `session` when it serves one session only. Added in 0.3.0.
- `session_count` comes from claude's own status line. `sessions` is best effort: it reads Claude Code's per-session state files, which are internal to Claude Code and may change, so `status` values are passed through as-is (for example `busy` or `waiting`).
- Times are Unix seconds, and unknown values are `null`. Within schema 1, fields are only ever added, never changed or removed. With no services, `services` is an empty list.

## Security

- Remote Control lets anyone signed in to your claude.ai account drive Claude Code on this Mac with your user's permissions. Protect the account (and consider [Trusted Devices](https://code.claude.com/docs/en/remote-control)).
- afar-rcd does not change Claude Code's permission prompts. New sessions use Claude Code's default permission mode unless you pass `--permission-mode`. Avoid `bypassPermissions` for an always-on service.
- The service runs as your user, never as root, and everything afar-rcd writes stays in your home folder.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/johannesreich1/afar-rcd/main/install.sh | bash -s -- --uninstall
```

or `./install.sh --uninstall` from a clone. This stops and removes every service, then deletes `afar-rcd`. Claude Code itself stays installed.

With Homebrew, remove the services first, since `brew uninstall` leaves them running:

```bash
afar-rcd remove --all
brew uninstall afar-rcd
```

## Alternatives

- **tmux or screen**: run `claude remote-control` inside tmux and detach. Survives closing the terminal, but not a restart, and nothing restarts it when it exits.
- **`claude --bg`**: Claude Code's background sessions survive closing the terminal, but they don't start at login or keep the Mac awake.
- **The Claude desktop app** can connect its sessions to Remote Control, but only while the app is open.

## Configuration

Settings live in each service's config file (see [Options for `add`](#options-for-add)). A few environment variables tune afar-rcd itself; set them before `afar-rcd add` and they are copied into the service:

| Variable | Default | What it does |
| --- | --- | --- |
| `AFAR_RCD_NOTIFY` | `1` | `0` turns notifications off |
| `AFAR_RCD_RENOTIFY` | `21600` | Seconds before a notification about the same problem repeats |
| `AFAR_RCD_WATCH_INTERVAL` | `30` | Seconds between sign-in checks while claude runs |
| `AFAR_RCD_BACKOFF_MAX` | `300` | Longest wait between restarts, in seconds |
| `AFAR_RCD_LOG_MAX_BYTES` | `10485760` | Log size that triggers rotation |

## Development

```bash
make lint   # shellcheck
make test   # runs real launchd agents against a fake claude, in a temp folder
```

The tests use `test/fake-claude` in place of Claude Code and their own launchd labels (`com.github.johannesreich1.afar-rcd.selftest.*`), so they never touch your real services. The fake behaves like the real CLI where it matters: it redraws its status every fraction of a second, prints Claude Code's real sign-in warnings and errors, and runs a child process per session. The tests take about four minutes, because they exercise real restarts, timeouts and launchd throttling.

## License

[MIT](LICENSE). "Claude" is a trademark of Anthropic, PBC.
