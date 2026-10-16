#!/bin/bash
#
# Tests for afar-rcd. They run real launchd agents, under their own label
# prefix and in a temporary folder, with test/fake-claude standing in for the
# Claude Code CLI, so they never touch your own services.
#
# Usage: test/run.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TOOL="$ROOT/bin/afar-rcd"
T=$(mktemp -d -t afar-rcd-test) || exit 1
T=$(cd "$T" && pwd -P)

export AFAR_RCD_HOME="$T/home"
export AFAR_RCD_LOG_DIR="$T/logs"
export AFAR_RCD_AGENTS_DIR="$T/agents"
export AFAR_RCD_LABEL_PREFIX="com.github.afar-rcd.selftest"
export AFAR_RCD_NOTIFY=log
export AFAR_RCD_BACKOFF_MIN=1 AFAR_RCD_BACKOFF_MAX=2 AFAR_RCD_STABLE_AFTER=3
export AFAR_RCD_RECHECK=2 AFAR_RCD_SETUP_GRACE=1 AFAR_RCD_LOGIN_POLL=1 AFAR_RCD_STOP_TIMEOUT=3
export AFAR_RCD_WATCH_INTERVAL=1 AFAR_RCD_LOGIN_RECHECK=8
export AFAR_RCD_CLAUDE="$T/bin/claude"
# Claude Code settings for the tests: trusts everything under $T.
export CLAUDE_CONFIG_DIR="$T/claude-config"
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}\n' "$T" >"$CLAUDE_CONFIG_DIR/.claude.json"
# Saved sign-in. `sign_in` changes it the way `claude auth login` would.
printf '{}' >"$CLAUDE_CONFIG_DIR/.credentials.json"
sign_in() { printf ' ' >>"$CLAUDE_CONFIG_DIR/.credentials.json"; }
NOTES="$AFAR_RCD_HOME/run/notifications.log"
notes() { grep -c "$1" "$NOTES" 2>/dev/null || printf '0'; }

FAKE="$T/fake"
mkdir -p "$T/bin" "$FAKE"
cp "$ROOT/test/fake-claude" "$T/bin/claude"
chmod +x "$T/bin/claude"
printf '%s\n' "$FAKE" >"$T/bin/FAKE_CLAUDE_STATE"

PASSES=0 FAILS=0

pass() { PASSES=$((PASSES + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { FAILS=$((FAILS + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

check() { # check DESCRIPTION COMMAND...
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

wait_for() { # wait_for SECONDS DESCRIPTION COMMAND...
  local secs=$1 desc=$2 _
  shift 2
  for _ in $(seq 1 $((secs * 4))); do
    if "$@" >/dev/null 2>&1; then pass "$desc"; return 0; fi
    sleep 0.25
  done
  fail "$desc (waited ${secs}s)"
  return 1
}

rcd() { "$TOOL" "$@"; }
# jsonq EXPR [NAME]: evaluates a JavaScript expression on `status --json`, as j.
jsonq() {
  /usr/bin/osascript -l JavaScript -e "function run(a) { var j = JSON.parse(a[0]); return String($1) }" \
    "$("$TOOL" status ${2:+"$2"} --json)" 2>/dev/null
}
first_session_busy() { [ "$(jsonq 'j.services[0].sessions.length > 0 && j.services[0].sessions[0].status' my-project)" = busy ]; }
mode() { printf '%s\n' "$1" >"$FAKE/mode"; }
# shellcheck source=/dev/null
state() { (. "$AFAR_RCD_HOME/run/$1.state" 2>/dev/null && printf '%s' "$ST_STATE"); }
# shellcheck source=/dev/null
child() { (. "$AFAR_RCD_HOME/run/$1.state" 2>/dev/null && printf '%s' "$ST_PID"); }
state_is() { [ "$(state "$1")" = "$2" ]; }
running_new() { state_is "$1" running && [ -n "$(child "$1")" ] && [ "$(child "$1")" != "$2" ] && kill -0 "$(child "$1")"; }
loaded() { launchctl print "$(domain)/$AFAR_RCD_LABEL_PREFIX.$1" >/dev/null 2>&1; }
not_loaded() { ! loaded "$1"; }
domain() { if launchctl print "gui/$UID" >/dev/null 2>&1; then printf 'gui/%s' "$UID"; else printf 'user/%s' "$UID"; fi; }
event_for() { grep -q "^$1 $2" "$FAKE/events" 2>/dev/null; }
fakes_running() { pgrep -f "$T/bin/claude remote-control" | grep -c .; }
no_fakes() { [ "$(fakes_running)" -eq 0 ]; }
one_fake() { [ "$(fakes_running)" -eq 1 ]; }
starts() { grep -c ' start ' "$FAKE/events" 2>/dev/null || printf '0'; }
more_starts() { [ "$(starts)" -gt "$1" ]; }
caffeinated() { pgrep -f "caffeinate -$1 -w $2" >/dev/null; }

cleanup() {
  local f
  for f in "$AFAR_RCD_HOME"/services/*.conf; do
    [ -e "$f" ] || continue
    f=${f##*/}
    launchctl bootout "$(domain)/$AFAR_RCD_LABEL_PREFIX.${f%.conf}" >/dev/null 2>&1
  done
  pkill -f "$T/bin/claude remote-control" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

show_log() { printf '    --- log of %s ---\n' "$1"; tail -n 25 "$T/saved-logs/$1.log" 2>/dev/null | sed 's/^/    /'; }

printf 'launchd domain: %s\n' "$(domain)"

# ------------------------------------------------------------------------------
section "helpers"
lib() { AFAR_RCD_LIB=1 /bin/bash -c ". '$TOOL'; $1"; }
check "default_name cleans up folder names" [ "$(lib 'default_name "/x/My Cool_Project!!"')" = "my-cool_project" ]
check "default_name falls back for odd names" [ "$(lib 'default_name "/x/!!!"')" = "project" ]
check "backoff doubles from the minimum" [ "$(lib 'AFAR_RCD_BACKOFF_MIN=5 AFAR_RCD_BACKOFF_MAX=300; RCD_BACKOFF_MIN=5 RCD_BACKOFF_MAX=300; backoff 3')" = 20 ]
check "backoff stops at the maximum" [ "$(lib 'RCD_BACKOFF_MIN=5 RCD_BACKOFF_MAX=300; backoff 30')" = 300 ]
check "fmt_dur formats durations" [ "$(lib 'fmt_dur 45; fmt_dur 3700; fmt_dur 90000')" = "45s1h1m1d1h" ]
check "xml_escape escapes markup" [ "$(lib 'xml_escape "a&b<c>"')" = "a&amp;b&lt;c&gt;" ]
check "valid_name rejects slashes" lib '! valid_name "a/b" && valid_name "ok.name-1_x"'
check "trust_state sees a trusted parent folder" [ "$(lib "trust_state '$T/projects/x'")" = yes ]
check "trust_state sees an untrusted folder" [ "$(lib "trust_state /usr")" = no ]
rm -f "$T/rot.log" "$T/rot.log.1"
seq 1 400 | sed 's/^/unique line /' | AFAR_RCD_LOG_MAX_BYTES=2000 lib "log_filter '$T/rot.log'"
check "log_filter rotates a log that grows too big" [ -f "$T/rot.log.1" ] && [ "$(stat -f %z "$T/rot.log")" -le 2000 ]
check "log_filter keeps the newest lines" grep -q 'unique line 400$' "$T/rot.log"
printf 'a \033]8;;https://x.test/1\007label\033]8;;\007 \033[1mbold\033[0m\n' | lib "log_filter '$T/esc.log'"
check "log_filter keeps link targets and strips escape codes" grep -q '\[claude\] a label <https://x.test/1> bold$' "$T/esc.log"
check "service_path has no duplicates" [ "$(lib 'PATH=/usr/bin:/bin:/usr/bin service_path' | tr ':' '\n' | sort | uniq -d | wc -l | tr -d ' ')" = 0 ]

section "commands without services"
check "version prints the version" sh -c "'$TOOL' version | grep -q '^afar-rcd [0-9]'"
check "help lists the commands" sh -c "'$TOOL' help | grep -q 'add \\[FOLDER\\]'"
check "status with no services says so" sh -c "'$TOOL' status | grep -q 'No services yet'"
check "status --json with no services has an empty list" [ "$("$TOOL" status --json)" = '{"schema":1,"version":"'"$("$TOOL" version | cut -d' ' -f2)"'","services":[]}' ]
check "unknown commands fail" sh -c "! '$TOOL' frobnicate 2>/dev/null"
check "adding the home folder is refused" sh -c "! '$TOOL' add '$HOME' </dev/null 2>/dev/null"

# ------------------------------------------------------------------------------
section "add a service (folder with a space in its name)"
P1="$T/projects/My Project"
mkdir -p "$P1"
mode serve
if rcd add "$P1" </dev/null >"$T/add.out" 2>&1; then pass "add succeeds"; else fail "add succeeds"; cat "$T/add.out"; fi
check "add reports the session link" grep -q 'https://claude.ai/code?environment=env_fake' "$T/add.out"
check "config was written" [ -f "$AFAR_RCD_HOME/services/my-project.conf" ]
check "launchd plist is valid" plutil -lint "$AFAR_RCD_AGENTS_DIR/$AFAR_RCD_LABEL_PREFIX.my-project.plist"
check "agent is loaded in launchd" loaded my-project
wait_for 10 "claude is running" state_is my-project running
PID1=$(child my-project)
check "claude runs in the service folder" grep -q "^$PID1 start mode=serve args= cwd=$P1\$" "$FAKE/events"
wait_for 5 "caffeinate keeps the Mac awake while claude runs" caffeinated i "$PID1"
check "status lists the service as running" sh -c "'$TOOL' status | grep -q '^my-project  *running  *$PID1'"
check "status NAME shows the environment link" sh -c "'$TOOL' status my-project | grep -q 'session: *https://claude.ai/code?environment=env_fake$PID1'"
check "status FOLDER resolves the service" sh -c "'$TOOL' status '$P1' | grep -q running"
check "logs shows claude's output" sh -c "'$TOOL' logs my-project | grep -q '\[claude\] Take this session with you'"
sleep 3
check "the log does not grow while claude redraws" [ "$(grep -c 'Capacity:' "$AFAR_RCD_LOG_DIR/my-project.log")" -eq 1 ]
check "the log has no escape codes" [ "$(tr -cd '\033' <"$AFAR_RCD_LOG_DIR/my-project.log" | wc -c | tr -d ' ')" -eq 0 ]
check "session links keep their target" grep -q "fake-session <https://claude.ai/code/session_fake$PID1?from=cli>" "$AFAR_RCD_LOG_DIR/my-project.log"
printf '1/32\n' >"$FAKE/capacity"
wait_for 5 "changes in the status block are logged" grep -q 'Capacity: 1/32' "$AFAR_RCD_LOG_DIR/my-project.log"
wait_for 5 "status counts connected sessions" sh -c "'$TOOL' status my-project | grep -q 'sessions: *1 connected'"
check "status shows the connection state" sh -c "'$TOOL' status my-project | grep -q 'connection: *Connected'"
check "the status table has a sessions column" sh -c "'$TOOL' status | grep -q '^my-project  *running  *[0-9]*  *[0-9a-z]*  *1  '"
check "adding the same folder twice is refused" sh -c "! '$TOOL' add '$P1' </dev/null 2>/dev/null"

section "restart after claude dies"
kill -KILL "$PID1"
wait_for 15 "a new claude is started" running_new my-project "$PID1"
PID2=$(child my-project)
check "only one claude is running" one_fake

section "stop"
START=$(date +%s)
rcd stop my-project >"$T/stop.out"
check "stop is quick when claude exits promptly" [ $(($(date +%s) - START)) -le 3 ]
check "stop warns about connected sessions" grep -q "has 1 connected session" "$T/stop.out"
rm -f "$FAKE/capacity"
check "claude got SIGINT (like Ctrl+C)" event_for "$PID2" "got SIGINT"
check "agent is unloaded" not_loaded my-project
check "status --json shows it stopped, without a pid" [ "$(jsonq 'j.services[0].state + " " + j.services[0].pid')" = "stopped null" ]
check "no claude left running" no_fakes
check "caffeinate stopped too" sh -c "! pgrep -f 'caffeinate -i -w $PID2'"
check "status shows stopped" sh -c "'$TOOL' status | grep -q '^my-project  *stopped'"
check "the log has no job-control noise" sh -c "! grep -Eq '^\[[0-9]+\]' '$AFAR_RCD_LOG_DIR/my-project.log'"
check "agent is disabled so it stays stopped after a restart" sh -c "launchctl print-disabled '$(domain)' | grep -Eq '\"$AFAR_RCD_LABEL_PREFIX.my-project\" => (disabled|true)'"

section "start"
rcd start my-project </dev/null >/dev/null
wait_for 10 "claude is running again" running_new my-project "$PID2"
check "agent is enabled again" sh -c "! launchctl print-disabled '$(domain)' | grep -Eq '\"$AFAR_RCD_LABEL_PREFIX.my-project\" => (disabled|true)'"
PID3=$(child my-project)

section "restart"
rcd restart my-project </dev/null >/dev/null
wait_for 10 "a new claude runs after restart" running_new my-project "$PID3"
check "the old claude got SIGINT" event_for "$PID3" "got SIGINT"
check "only one claude is running" one_fake
PID4=$(child my-project)

section "status --json"
touch "$FAKE/session"
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "claude is running with a session" running_new my-project "$PID4"
PID4=$(child my-project)
check "it is valid JSON with a schema version" [ "$(jsonq 'j.schema')" = 1 ]
check "it reports state, pid and folder" [ "$(jsonq 'j.services[0].state + " " + j.services[0].pid + " " + j.services[0].folder')" = "running $PID4 $P1" ]
check "it reports the log file" [ "$(jsonq 'j.services[0].log')" = "$AFAR_RCD_LOG_DIR/my-project.log" ]
check "it reports the connection and environment link" [ "$(jsonq 'j.services[0].connection + " " + j.services[0].url')" = "Connected https://claude.ai/code?environment=env_fake$PID4" ]
wait_for 5 "it lists the sessions with their status" first_session_busy
check "session entries link to the session" sh -c "[ \"\$(AFAR_RCD_LIB=1 /bin/bash -c '. \"$TOOL\"; session_list json $PID4')\" != '[]' ]"
check "status NAME lists the sessions too" sh -c "'$TOOL' status my-project | grep -q -- '- fake-session (busy) https://claude.ai/code/session_fakekid'"
mkdir -p "$T/nopgrep"
printf '#!/bin/sh\nexit 1\n' >"$T/nopgrep/pgrep"
chmod +x "$T/nopgrep/pgrep"
check "sessions are found even where pgrep sees nothing" sh -c "PATH='$T/nopgrep:$PATH' '$TOOL' status --json | grep -q '\"status\":\"busy\"'"
check "status NAME --json has just that service" [ "$(jsonq 'j.services.length + " " + j.services[0].name' my-project)" = "1 my-project" ]
rm -f "$FAKE/session"

section "Remote Control not enabled yet"
mode consent
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "state is needs-setup" state_is my-project needs-setup
wait_for 5 "a notification asks to run setup" grep -q "one-time confirmation" "$NOTES"
check "status explains how to fix it" sh -c "'$TOOL' status my-project | grep -q 'afar-rcd setup my-project'"
check "it does not restart in a tight loop" [ "$(grep -c 'start mode=consent' "$FAKE/events")" -le 2 ]
mode serve
wait_for 15 "it recovers on its own once enabled" running_new my-project "$PID4"
PID5=$(child my-project)

section "folder not trusted"
mode untrusted
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "state is needs-setup" state_is my-project needs-setup
mode serve
wait_for 15 "it recovers once trusted" running_new my-project "$PID5"
PID6=$(child my-project)

section "signed out"
touch "$FAKE/loggedout"
mode loggedout
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "state is needs-login" state_is my-project needs-login
sleep 2
N=$(starts)
sleep 2
check "it waits instead of restarting claude" [ "$(starts)" -eq "$N" ]
check "a notification asks to sign in again" grep -q "needs you to sign in again for 'my-project'" "$NOTES"
check "the notification is not repeated while it waits" [ "$(notes "needs you to sign in again")" -eq 1 ]
rm -f "$FAKE/loggedout"
sign_in
mode serve
wait_for 15 "it starts again after signing in" running_new my-project "$PID6"
PID7=$(child my-project)

section "sign-in stops renewing while claude runs"
mode renew-warning
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "claude is running" running_new my-project "$PID7"
PIDW=$(child my-project)
wait_for 10 "status shows needs-login while claude still runs" sh -c "'$TOOL' status | grep -q '^my-project  *needs-login  *$PIDW '"
check "status explains the problem" sh -c "'$TOOL' status my-project | grep -q 'problem: *Remote Control could not renew'"
check "status says how to fix it" sh -c "'$TOOL' status my-project | grep -q \"fix: *run 'claude auth login'\""
check "a notification asks to sign in right away" grep -q "cannot renew its sign-in for 'my-project'" "$NOTES"
check "claude keeps running meanwhile" kill -0 "$PIDW"
sign_in
wait_for 10 "signing in again clears the warning" sh -c "'$TOOL' status | grep -q '^my-project  *running  *$PIDW '"

section "sign-in ran out and claude stopped"
mode auth-401
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "state is needs-login" state_is my-project needs-login
N=$(starts)
sleep 3
check "it waits for a new sign-in instead of retrying" [ "$(starts)" -eq "$N" ]
mode serve
sign_in
wait_for 10 "a new sign-in starts it again right away" running_new my-project "$PIDW"
PIDX=$(child my-project)
mode auth-401
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "state is needs-login again" state_is my-project needs-login
mode serve
wait_for 20 "without a new sign-in it still retries after a while" running_new my-project "$PIDX"
PID7=$(child my-project)

section "crash loop"
mode crash
N=$(starts)
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "state is restarting" state_is my-project restarting
wait_for 15 "it keeps retrying" more_starts $((N + 2))
wait_for 20 "a notification says it keeps stopping" grep -q "keeps stopping" "$NOTES"
check "the log records the exit status" grep -q 'exited with status 3' "$AFAR_RCD_LOG_DIR/my-project.log"
mode serve
wait_for 15 "it recovers when claude works again" running_new my-project "$PID7"
PID8=$(child my-project)

section "claude that ignores SIGINT"
mode ignore-int
rcd restart my-project </dev/null >/dev/null 2>&1
wait_for 10 "stubborn claude is running" running_new my-project "$PID8"
PID9=$(child my-project)
START=$(date +%s)
rcd stop my-project >/dev/null
check "stop escalated to SIGTERM" event_for "$PID9" "got SIGTERM"
check "stop took about the stop timeout" [ $(($(date +%s) - START)) -le 15 ]
check "no claude left running" no_fakes
mode serve
rcd start my-project </dev/null >/dev/null
wait_for 10 "claude is running again" running_new my-project "$PID9"
PID10=$(child my-project)

section "supervisor killed outright"
SUP=$(launchctl print "$(domain)/$AFAR_RCD_LABEL_PREFIX.my-project" | awk '$1 == "pid" { print $3; exit }')
check "launchd knows the supervisor pid" [ -n "$SUP" ]
kill -KILL "$SUP"
wait_for 30 "launchd starts a new supervisor and claude" running_new my-project "$PID10"
check "the leftover claude was stopped" event_for "$PID10" "got SIGINT"
check "only one claude is running" one_fake

section "second service with extra arguments"
P2="$T/projects/second"
mkdir -p "$P2"
if rcd add "$P2" --name two --keep-awake ac -- --spawn worktree --capacity 4 </dev/null >"$T/add2.out" 2>&1; then pass "add with arguments succeeds"; else fail "add with arguments succeeds"; cat "$T/add2.out"; fi
wait_for 10 "second service is running" state_is two running
TWO=$(child two)
check "arguments reach claude remote-control" grep -q "^$TWO start mode=serve args=--spawn worktree --capacity 4 cwd=$P2\$" "$FAKE/events"
wait_for 5 "keep-awake ac uses caffeinate -s" caffeinated s "$TWO"
check "status lists both services" [ "$("$TOOL" status | grep -c running)" -eq 2 ]
check "status --json lists both services" [ "$(jsonq 'j.services.map(function (s) { return s.name }).join(",")')" = "my-project,two" ]
check "a command without NAME asks which service" sh -c "! '$TOOL' logs 2>/dev/null"
check "invalid names are refused" sh -c "! '$TOOL' add '$T' --name 'bad/name' </dev/null 2>/dev/null"
check "duplicate names are refused" sh -c "! '$TOOL' add '$T' --name two </dev/null 2>/dev/null"

section "doctor"
check "doctor passes" sh -c "'$TOOL' doctor </dev/null"
check "doctor explains what happens after a restart" sh -c "'$TOOL' doctor </dev/null | grep -q 'After a restart'"

section "remove"
cp -R "$AFAR_RCD_LOG_DIR" "$T/saved-logs" 2>/dev/null
rcd remove --all >/dev/null
check "agents are unloaded" sh -c "! launchctl print '$(domain)/$AFAR_RCD_LABEL_PREFIX.my-project' && ! launchctl print '$(domain)/$AFAR_RCD_LABEL_PREFIX.two'"
check "plists are gone" [ -z "$(ls "$AFAR_RCD_AGENTS_DIR")" ]
check "configs are gone" [ -z "$(ls "$AFAR_RCD_HOME/services")" ]
check "no claude left running" no_fakes

# ------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASSES" "$FAILS"
if [ "$FAILS" -gt 0 ]; then
  for n in my-project two; do show_log "$n"; done
  exit 1
fi
