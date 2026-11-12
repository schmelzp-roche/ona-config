# Sourced from ~/.bashrc / ~/.zshrc by install.sh. Keep it fast and quiet.

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# The team works in Switzerland: show Swiss time (CET/CEST) instead of the container's UTC.
export TZ="Europe/Zurich"

# Azure DevOps CLI (az devops / az repos / az boards) authenticates with this.
# Fallback order: ADO_TOKEN (Ona secret) -> already-set value.
[ -n "${ADO_TOKEN:-}" ] && export AZURE_DEVOPS_EXT_PAT="$ADO_TOKEN"

# Private environment variables (config/env.sh of the private repo).
[ -f "$HOME/.config/gacct/private/config/env.sh" ] && . "$HOME/.config/gacct/private/config/env.sh"

# gh uses GH_TOKEN / GITHUB_TOKEN automatically (GITHUB_TOKEN = work account).
# For the private account use:  gacct gh personal <args>

# ls colors from ~/.dircolors (linked to shell/dircolors by install.sh); also
# covers zsh, whose rc does not run dircolors itself.
if command -v dircolors >/dev/null 2>&1 && [ -r "$HOME/.dircolors" ]; then
  eval "$(dircolors -b "$HOME/.dircolors")"
fi

# Ona's welcome-claude.sh (sourced earlier in ~/.bashrc / ~/.zshrc) rewrites
# ~/.claude/settings.json in every new shell and drops our keys: add them back.
if command -v jq >/dev/null 2>&1 && [ -f "$HOME/.claude/settings.json" ] \
   && ! jq -e '.attribution' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  bash "$HOME/.config/gacct/setup-claude-settings.sh" >/dev/null 2>&1
fi

# VS Code extensions of vscode-extensions.txt: installs missing ones into the
# VS Code server in the background (returns at once when nothing changed).
if [ -x "$HOME/.config/gacct/install-vscode-extensions.sh" ]; then
  ( "$HOME/.config/gacct/install-vscode-extensions.sh" \
      >>"$HOME/.cache/ona-config/vscode-extensions.log" 2>&1 & ) 2>/dev/null
fi

# VS Code remote settings of vscode-machine-settings.json (e.g. the PlantUML jar):
# merged in the background once the VS Code server exists (no-op when unchanged).
if [ -x "$HOME/.config/gacct/setup-vscode-settings.sh" ]; then
  ( "$HOME/.config/gacct/setup-vscode-settings.sh" \
      >>"$HOME/.cache/ona-config/vscode-settings.log" 2>&1 & ) 2>/dev/null
fi

# Aliases (linked next to this file by install.sh).
[ -f "$HOME/.config/gacct/aliases.sh" ] && . "$HOME/.config/gacct/aliases.sh"
