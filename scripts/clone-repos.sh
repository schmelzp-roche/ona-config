#!/usr/bin/env bash
# Clones every repo listed in repos.txt of the private repo (linked to
# ~/.config/gacct/private by install.sh) into $REPOS_DIR (parallel, idempotent).
# Existing directories are skipped, so local work is never touched.
#   REPOS_DIR   target directory      (default: /workspaces/workspaces)
#   CLONE_JOBS  parallel clones       (default: 6)
set -uo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${1:-$HOME/.config/gacct/private/config/repos.txt}"
REPOS_DIR="${REPOS_DIR:-/workspaces/workspaces}"
JOBS="${CLONE_JOBS:-6}"
export PATH="$HOME/.local/bin:$PATH" GIT_TERMINAL_PROMPT=0 REPOS_DIR

[[ -r "$LIST" ]] || { echo "[clone-repos] no $LIST, nothing to do"; exit 0; }
mkdir -p "$REPOS_DIR"

clone_one() {
  local url="$1" dir="${2:-}"
  [[ -n "$dir" ]] || { dir="$(basename "$url")"; dir="${dir%.git}"; }
  local path="$REPOS_DIR/$dir"
  if [[ -e "$path" ]]; then echo "[clone-repos] skip   $dir (exists)"; return 0; fi
  if git clone --quiet "$url" "$path" 2>"/tmp/clone-$dir.err"; then
    (cd "$path" && gacct here >/dev/null 2>&1)
    echo "[clone-repos] cloned $dir"
  else
    echo "[clone-repos] FAILED $dir: $(grep -v '^$' "/tmp/clone-$dir.err" | tail -1)"
    rm -rf "$path"; return 1
  fi
  rm -f "/tmp/clone-$dir.err"
}
export -f clone_one

# Hide clones from the enclosing repo's `git status` (local exclude, not committed)
if parent_git="$(git -C "$REPOS_DIR" rev-parse --git-dir 2>/dev/null)"; then
  [[ "$parent_git" = /* ]] || parent_git="$REPOS_DIR/$parent_git"
  exclude="$parent_git/info/exclude"; mkdir -p "$(dirname "$exclude")"
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$LIST" | while read -r url dir _; do
    [[ -n "${dir:-}" ]] || { dir="$(basename "$url")"; dir="${dir%.git}"; }
    grep -qxF "/$dir/" "$exclude" 2>/dev/null || echo "/$dir/" >>"$exclude"
  done
fi

total=$(grep -cv -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$LIST")
echo "[clone-repos] $total repos -> $REPOS_DIR ($JOBS parallel)"
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$LIST" \
  | xargs -P "$JOBS" -L 1 bash -c 'clone_one "$@"' _
rc=$?
[[ $rc -eq 0 ]] && echo "[clone-repos] done" || echo "[clone-repos] done, with failures (see above)"
exit 0
