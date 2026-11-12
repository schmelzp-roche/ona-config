#!/usr/bin/env bash
# Merges our Claude Code preferences into ~/.claude/settings.json without
# touching the keys Ona writes there (env with the proxy URL and headers):
#   - no "Co-Authored-By: Claude" trailer in commits, no attribution in PRs
# Idempotent.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
log() { echo "[setup-claude-settings] $*"; }

command -v jq >/dev/null 2>&1 || { log "jq missing, skipping"; exit 0; }
mkdir -p "$(dirname "$SETTINGS")"
[[ -s "$SETTINGS" ]] || echo '{}' >"$SETTINGS"

tmp="$(mktemp)"
jq '.attribution = {"commit": "", "pr": ""} | .includeCoAuthoredBy = false' \
  "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
log "commit/PR attribution disabled in $SETTINGS"
