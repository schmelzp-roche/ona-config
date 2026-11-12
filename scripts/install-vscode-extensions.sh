#!/usr/bin/env bash
# Installs the extensions of vscode-extensions.txt into the VS Code server on
# this Ona machine (~/.vscode-server, created on the first VS Code connection).
# Without a server it does nothing; shell/env.sh runs it again in the
# background, so the extensions follow as soon as VS Code has connected once.
# Skips quickly when the list and the server version are unchanged.
# Idempotent. Log: ~/.cache/ona-config/vscode-extensions.log
set -uo pipefail

DOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
LIST="$DOT/vscode-extensions.txt"
STATE="$HOME/.cache/ona-config"
STAMP="$STATE/vscode-extensions.stamp"
log() { echo "[vscode-extensions] $*"; }

mkdir -p "$STATE"
[[ -f "$LIST" ]] || { log "no $LIST"; exit 0; }

# Newest VS Code server CLI (the one VS Code connected with most recently)
server="$(ls -dt "$HOME"/.vscode-server/cli/servers/Stable-*/server/bin/code-server \
                 "$HOME"/.vscode-server/bin/*/bin/code-server 2>/dev/null | head -1)"
[[ -x "$server" ]] || { log "no VS Code server yet, skipping"; exit 0; }

stamp="$(sha256sum "$LIST" | cut -c1-16) $server"
[[ "${1:-}" != "--force" && -f "$STAMP" && "$(cat "$STAMP")" == "$stamp" ]] && exit 0

# Single run at a time (several terminals may start together)
exec 9>"$STATE/vscode-extensions.lock"
flock -n 9 || exit 0

installed="$("$server" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
failed=0
while read -r ext; do
  ext="${ext%%#*}"; ext="${ext//[[:space:]]/}"
  [[ -z "$ext" ]] && continue
  grep -qxF "${ext,,}" <<<"$installed" && continue
  if "$server" --install-extension "$ext" >/dev/null 2>&1; then log "installed $ext"
  else log "FAILED    $ext"; failed=1
  fi
done <"$LIST"

# Remember success only, so failures are retried in the next shell
[[ $failed -eq 0 ]] && echo "$stamp" >"$STAMP"
log "done (reload the VS Code window to activate new extensions)"
