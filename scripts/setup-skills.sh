#!/usr/bin/env bash
# Sets up the Claude Code skills from the private repo (linked to
# ~/.config/gacct/private by install.sh):
#   1. links every skill into ~/.claude/skills (via the repo's install.sh)
#   2. links the clones listed in its config/project-links.txt into ~/Projects,
#      where some skills expect them
# Idempotent. REPOS_DIR: where the repos are cloned (default: /workspaces/workspaces)
set -uo pipefail

REPOS_DIR="${REPOS_DIR:-/workspaces/workspaces}"
SKILLS="$HOME/.config/gacct/private"
LINKS="$SKILLS/config/project-links.txt"
log() { echo "[setup-skills] $*"; }

[[ -f "$SKILLS/install.sh" ]] || { log "no $SKILLS, skipping"; exit 0; }
bash "$SKILLS/install.sh"

mkdir -p "$HOME/Projects"
[[ -r "$LINKS" ]] || exit 0
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$LINKS" | while read -r repo _; do
  src="$REPOS_DIR/$repo" dst="$HOME/Projects/$repo"
  if [[ ! -d "$src" ]]; then log "WARNING: $src missing, $repo not linked"
  elif [[ -e "$dst" && ! -L "$dst" ]]; then log "keep     ~/Projects/$repo (not a link)"
  else ln -sfn "$src" "$dst"; log "linked   ~/Projects/$repo"
  fi
done
exit 0
