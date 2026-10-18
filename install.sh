#!/bin/bash
#
# Installs afar-cli into ~/.local/bin (set AFAR_CLI_PREFIX to change it).
#
#   curl -fsSL https://raw.githubusercontent.com/johannesreich1/afar-cli/main/install.sh | bash
#   ./install.sh               install from a clone of the repository
#   ./install.sh --uninstall   remove afar-cli and every service it created

set -eu

REPO=${AFAR_CLI_REPO:-johannesreich1/afar-cli}
REF=${AFAR_CLI_REF:-main}
PREFIX=${AFAR_CLI_PREFIX:-$HOME/.local}
BIN_DIR="$PREFIX/bin"
TARGET="$BIN_DIR/afar-cli"

if [ -t 1 ]; then
  C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_OFF=$'\033[0m'
else
  C_GREEN='' C_YELLOW='' C_RED='' C_OFF=''
fi
ok()   { printf '%s✔%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "afar-cli runs on macOS only."

if [ "${1-}" = --uninstall ]; then
  if [ -x "$TARGET" ]; then "$TARGET" remove --all || true; fi
  rm -f "$TARGET"
  rmdir "$HOME/.config/afar-cli/services" "$HOME/.config/afar-cli/run" "$HOME/.config/afar-cli" \
    "$HOME/Library/Logs/afar-cli" 2>/dev/null || true
  ok "Removed afar-cli"
  exit 0
fi

# From a clone, install the copy next to this script; otherwise download it.
# Piped from curl there is no script file (BASH_SOURCE is empty), so a
# bin/afar-cli in the current folder must not be mistaken for a clone.
src=''
if [ -n "${BASH_SOURCE[0]-}" ]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || here=''
  if [ -n "$here" ] && [ -f "$here/bin/afar-cli" ]; then src="$here/bin/afar-cli"; fi
fi

mkdir -p "$BIN_DIR"
tmp="$TARGET.new.$$"
trap 'rm -f "$tmp"' EXIT
if [ -n "$src" ]; then
  cp "$src" "$tmp"
else
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/bin/afar-cli" -o "$tmp" ||
    die "could not download afar-cli from github.com/$REPO"
fi
head -n 1 "$tmp" | grep -q '^#!/bin/bash' || die "the downloaded file is not afar-cli"
/bin/bash -n "$tmp" || die "the downloaded file is damaged"
chmod 0755 "$tmp"
# Rename into place so services running the old copy are not disturbed.
mv -f "$tmp" "$TARGET"
ok "Installed $("$TARGET" version) to $TARGET"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    warn "$BIN_DIR is not on your PATH. Add it with:"
    # shellcheck disable=SC2016 # $PATH is meant literally
    printf '    echo '\''export PATH="%s:$PATH"'\'' >> ~/.zshrc && exec zsh\n' "$BIN_DIR"
    ;;
esac

# Check for Claude Code and its sign-in, offering to fix them. When piped
# from curl, stdin is the script, so questions go to the terminal instead.
if [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
  "$TARGET" doctor </dev/tty || true
else
  "$TARGET" doctor </dev/null || true
fi

printf '\nNext: serve a project folder in the background:\n    afar-cli add ~/path/to/project\n'
