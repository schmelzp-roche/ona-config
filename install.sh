#!/usr/bin/env bash
# Ona dotfiles entry point: runs automatically when this repo is linked as
# your dotfiles repository. Safe to re-run.
set -euo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CFG="$HOME/.config/gacct"

REPOS_DIR="${REPOS_DIR:-/workspaces/workspaces}"
PRIVATE_URL="${ONA_PRIVATE_REPO:-https://github.com/schmelzp-roche/ona-config-private.git}"
PRIVATE_DIR="${ONA_PRIVATE_DIR:-$REPOS_DIR/ona-config-private}"
export REPOS_DIR

mkdir -p "$BIN" "$CFG"

# 0. Private config (accounts.conf, repos.txt, ...) and the Claude skills live in a
#    private repo. Clone it with PRIVATE_GITHUB_TOKEN directly: the credential
#    helper needs accounts.conf, which is in that repo. An existing clone is kept.
#    Without it, the public parts are still installed.
if [[ ! -d "$PRIVATE_DIR/.git" ]]; then
  mkdir -p "$(dirname "$PRIVATE_DIR")"
  if [[ -n "${PRIVATE_GITHUB_TOKEN:-}" ]]; then
    # The helper reads the token from the environment, so it never shows up in argv.
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
      -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$PRIVATE_GITHUB_TOKEN"; }; f' \
      clone --quiet "$PRIVATE_URL" "$PRIVATE_DIR" \
      || echo "warning: could not clone $PRIVATE_URL" >&2
  else
    echo "warning: PRIVATE_GITHUB_TOKEN not set, $PRIVATE_URL not cloned" >&2
  fi
fi
if [[ -d "$PRIVATE_DIR/config" ]]; then
  ln -sfn "$PRIVATE_DIR" "$CFG/private"
  ln -sf "$CFG/private/config/accounts.conf" "$CFG/accounts.conf"
else
  echo "warning: no private config in $PRIVATE_DIR: no accounts, repos or skills" >&2
fi
ACCOUNTS="$CFG/accounts.conf"

# 1. Install tools (symlinks so `git pull` in the dotfiles updates them)
for f in "$DOT"/bin/*; do
  chmod +x "$f"
  ln -sf "$f" "$BIN/$(basename "$f")"
done

# 2. Shell environment (PATH, ADO token for az devops, aliases)
ln -sf "$DOT/shell/env.sh" "$CFG/env.sh"
ln -sf "$DOT/shell/aliases.sh" "$CFG/aliases.sh"
ln -sf "$DOT/scripts/setup-claude-settings.sh" "$CFG/setup-claude-settings.sh"
ln -sf "$DOT/scripts/install-vscode-extensions.sh" "$CFG/install-vscode-extensions.sh"
ln -sf "$DOT/scripts/setup-vscode-settings.sh" "$CFG/setup-vscode-settings.sh"
# ls colors (no background on the o+w dirs under /workspaces); keep a real file as backup
[[ -f "$HOME/.dircolors" && ! -L "$HOME/.dircolors" ]] && mv "$HOME/.dircolors" "$HOME/.dircolors.bak"
ln -sf "$DOT/shell/dircolors" "$HOME/.dircolors"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || touch "$rc"
  grep -q 'ona-config: env' "$rc" || \
    printf '\n# ona-config: env\n[ -f "$HOME/.config/gacct/env.sh" ] && . "$HOME/.config/gacct/env.sh"\n' >>"$rc"
done
export PATH="$BIN:$PATH"

# 3. Register the credential helper FIRST for GitHub and Azure DevOps, keeping
#    any existing helpers (e.g. Ona's) as fallback. An empty helper value
#    resets the inherited list, so we re-append the previous ones after ours.
setup_helper() {
  local scope="credential.$1"
  local existing
  existing="$( { git config --get-all credential.helper; git config --get-all "$scope.helper"; } 2>/dev/null \
              | grep -v -e '^$' -e 'gacct' | awk '!seen[$0]++' || true)"
  git config --global --unset-all "$scope.helper" 2>/dev/null || true
  git config --global --add "$scope.helper" ""
  git config --global --add "$scope.helper" "$BIN/git-credential-gacct"
  while IFS= read -r h; do
    [[ -n "$h" ]] && git config --global --add "$scope.helper" "$h"
  done <<<"$existing"
  git config --global "$scope.useHttpPath" true
}
setup_helper "https://github.com"
setup_helper "https://dev.azure.com"

# 4. Commit author name (if set in accounts.conf)
name="$(sed -n 's/^#@name[[:space:]]\+//p' "$ACCOUNTS" 2>/dev/null | head -1 || true)"
if [[ -n "$name" && "$name" != "Your Name" ]]; then git config --global user.name "$name"; fi

# 5. Default active account (override with GACCT_DEFAULT secret/env var)
if [[ -n "${GACCT_DEFAULT:-}" ]]; then
  "$BIN/gacct" use "$GACCT_DEFAULT" || true
fi

# 6. CLI tools: gh + az (with azure-devops extension). Skip with SKIP_TOOLS=1.
if [[ -z "${SKIP_TOOLS:-}" ]]; then
  bash "$DOT/scripts/install-tools.sh" || echo "warning: tool installation had errors"
fi

# 7. az devops defaults (org from the ado line, project from #@ado_project)
if command -v az >/dev/null 2>&1 && [[ -r "$ACCOUNTS" ]]; then
  ado_org="$(awk '!/^[[:space:]]*#/ && $2=="dev.azure.com" {print $3; exit}' "$ACCOUNTS")"
  ado_project="$(sed -n 's/^#@ado_project[[:space:]]\+//p' "$ACCOUNTS" | head -1)"
  if [[ -n "$ado_org" ]]; then
    az devops configure --defaults "organization=https://dev.azure.com/$ado_org" \
      ${ado_project:+"project=$ado_project"} --only-show-errors || true
  fi
fi

# 8. Clone the repos listed in the private repos.txt (needs the credential helper from step 3).
#    Skip with SKIP_CLONE=1; target dir via REPOS_DIR.
if [[ -z "${SKIP_CLONE:-}" ]]; then
  bash "$DOT/scripts/clone-repos.sh" || echo "warning: repo cloning had errors"
fi

# 9. Claude Code skills of the private repo: link them into ~/.claude/skills and
#    the clones of project-links.txt into ~/Projects. Skip with SKIP_SKILLS=1.
if [[ -z "${SKIP_SKILLS:-}" ]]; then
  bash "$DOT/scripts/setup-skills.sh" || echo "warning: skills setup had errors"
fi

# 10. Claude Code settings: no Co-Authored-By trailer / PR attribution.
bash "$DOT/scripts/setup-claude-settings.sh" || echo "warning: Claude settings setup had errors"

# 11. VS Code extensions (vscode-extensions.txt) into the VS Code server, if one
#     exists yet; shell/env.sh retries in the background. Skip with SKIP_VSCODE_EXT=1.
if [[ -z "${SKIP_VSCODE_EXT:-}" ]]; then
  bash "$DOT/scripts/install-vscode-extensions.sh" || echo "warning: VS Code extension setup had errors"
fi

# 12. VS Code remote settings (vscode-machine-settings.json, e.g. the PlantUML jar)
#     into the VS Code server, if one exists yet; shell/env.sh retries in the background.
bash "$DOT/scripts/setup-vscode-settings.sh" || echo "warning: VS Code settings setup had errors"

echo "ona-config installed. Run 'gacct list' to see your accounts."
