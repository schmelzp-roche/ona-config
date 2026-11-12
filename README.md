# ona-config

Personal dotfiles for [Ona](https://ona.com) environments. Its main job is to make
working with **multiple GitHub accounts and Azure DevOps** painless.

> This repo is public: it contains **no tokens and no private configuration**. Tokens live
> in Ona secrets; the accounts, the repository list and the Claude Code skills live in the
> private repo [`ona-config-private`](https://github.com/schmelzp-roche/ona-config-private).

## Setup

1. **Create Ona secrets** (User settings → Secrets, as environment variables):
   | Secret                 | Value                                                      |
   |------------------------|------------------------------------------------------------|
   | `GITHUB_TOKEN`         | PAT for the work GitHub account                            |
   | `PRIVATE_GITHUB_TOKEN` | PAT for the personal GitHub account; also clones the private repo |
   | `ADO_TOKEN`            | Azure DevOps PAT (scope: Code → Read & write)              |
   | `GACCT_DEFAULT`        | *(optional)* account to activate on startup, e.g. `work`   |
2. **Link this repo** as your dotfiles repository in Ona (User settings → Preferences →
   Dotfiles). Ona runs `install.sh` automatically in each new environment. Ona can only
   clone a public dotfiles repo, which is why the private parts are split off.

## Public and private parts

`install.sh` first clones the private repo (`ONA_PRIVATE_REPO`, default
`schmelzp-roche/ona-config-private`) into `/workspaces/workspaces/ona-config-private`
(`ONA_PRIVATE_DIR`). It uses `PRIVATE_GITHUB_TOKEN` directly, because the credential helper
needs `accounts.conf`, which is in that repo. An existing clone is kept. It links the clone to
`~/.config/gacct/private` and reads from it:

| File in the private repo    | Used by                                                       |
|-----------------------------|---------------------------------------------------------------|
| `config/accounts.conf`      | `gacct`, `git-credential-gacct`, commit author, `az` defaults (template: [`accounts.conf.example`](accounts.conf.example)) |
| `config/repos.txt`          | `scripts/clone-repos.sh`                                      |
| `config/project-links.txt`  | `scripts/setup-skills.sh`                                     |
| `config/env.sh`             | `shell/env.sh` (private environment variables)                |
| the skills and `install.sh` | `scripts/setup-skills.sh`                                     |

If the private repo can't be cloned, `install.sh` prints a warning and installs the public
parts only. Git then falls back to Ona's built-in credential helper.

## How it works

`install.sh` installs a git credential helper (`git-credential-gacct`) for
`github.com` and `dev.azure.com`. For each git operation it picks the account like this:

1. Username in the URL: `https://<user>@github.com/...`
2. Repo owner/org listed in the account's `owners` column
3. Repo owner equal to an account's username
4. The active account (`gacct use <name>`), else the first account for that host

If the selected token isn't set, git falls back to any previously configured
helper (e.g. Ona's built-in one).

**So usually you just `git clone` / `git push`, and the right token is used.**

## `gacct` command

```bash
gacct list                       # accounts, token present ✓/✗, active marked *
gacct use personal               # default account + global commit email
gacct here                       # set this repo's commit email/credential user from origin
gacct here personal              # ...or force a specific account
gacct clone personal https://github.com/someone/repo.git
gacct gh work pr list            # GitHub CLI as a specific account
gacct test                       # verify all tokens against the APIs
```

Tip: run `gacct here` after cloning, so your commits use the matching email.
(`gacct clone` does this for you.)

## CLI tools (installed on startup)

`install.sh` also installs **gh** (GitHub CLI) and **az** (Azure CLI + `azure-devops`
extension) via the official apt repos (falls back to a no-root install). Set
`SKIP_TOOLS=1` to skip.

It also installs **Java**, **Graphviz** and **PlantUML** (see [PlantUML diagrams](#plantuml-diagrams)).

- **gh** authenticates via `GITHUB_TOKEN` (work account). Personal account:
  `gacct gh personal <args>`.
- **az devops** authenticates via `ADO_TOKEN` (exported as `AZURE_DEVOPS_EXT_PAT` by
  `shell/env.sh`). Defaults: org from the `dev.azure.com` line, project from
  `#@ado_project` in `accounts.conf`.

## Shell aliases

`shell/aliases.sh` holds the shell aliases (git, cargo, navigation). `install.sh`
links it to `~/.config/gacct/aliases.sh` and `shell/env.sh` sources it, so the aliases
work in bash and zsh. Since it is a symlink, `git pull` in this repo updates them; open a
new shell to pick up the changes.

## Repositories cloned on startup

`install.sh` clones every URL in `config/repos.txt` of the private repo into
`/workspaces/workspaces` (6 in parallel; GitHub and ADO tokens are picked automatically).
Existing clones are skipped, so local work is never touched. Each clone gets the right commit
email (`gacct here`) and is hidden from the enclosing repo's `git status`.

- Add/remove repos: edit `config/repos.txt` in the private repo (one HTTPS URL per line,
  optional dir name after it)
- Re-run any time: `bash ~/…/ona-config/scripts/clone-repos.sh`
- Options: `REPOS_DIR=/some/dir`, `CLONE_JOBS=8`, `SKIP_CLONE=1`

## Claude Code skills

After cloning, `install.sh` runs `scripts/setup-skills.sh`, which runs the `install.sh` of
the private repo (it links the skills into `~/.claude/skills`) and links the clones listed in
its `config/project-links.txt` into `~/Projects`, where some skills expect them.
`scripts/install-tools.sh` installs `python3` + PyYAML, which several skills need, and
Node.js (`npx`, current LTS in `~/.local/node`) + `cargo-nextest`.

- Re-run any time: `bash ~/…/ona-config/scripts/setup-skills.sh`
- Skip with `SKIP_SKILLS=1`

## ls colors

`install.sh` links `shell/dircolors` to `~/.dircolors` (an existing real file is moved to
`~/.dircolors.bak`), and `shell/env.sh` loads it in bash and zsh. Other-writable directories
(everything under `/workspaces`) are shown like normal directories (bold blue, no background).
Change colors in `shell/dircolors`; they apply in new shells.

## VS Code extensions

`vscode-extensions.txt` lists the VS Code extensions for the Ona machine. VS Code runs a
server on the Ona machine when you connect, and most extensions must be installed there.
`scripts/install-vscode-extensions.sh` installs the missing ones into that server
(`~/.vscode-server`). A fresh instance has no server until VS Code connects the first time, so
`shell/env.sh` reruns the script in the background in every new shell; it returns at once
when the list and the server version are unchanged. Reload the VS Code window afterwards to
activate new extensions.

- Add/remove extensions: edit `vscode-extensions.txt` (IDs from `code --list-extensions`)
- Run now: `bash ~/…/ona-config/scripts/install-vscode-extensions.sh --force`
- Log: `~/.cache/ona-config/vscode-extensions.log`; skip in `install.sh` with `SKIP_VSCODE_EXT=1`
- UI-only extensions (themes, icons, Remote-SSH, Ona, speech) belong on the laptop

## PlantUML diagrams

To render ` ```plantuml ` blocks and `.puml` files locally in the Ona VS Code:

- `scripts/install-tools.sh` installs Java and Graphviz (apt) and the PlantUML MIT jar of a
  pinned release, checksum-verified, into `~/.local/share/plantuml/plantuml.jar`. To update,
  change `PLANTUML_VERSION` and `PLANTUML_SHA256` (the asset's `digest` in the GitHub release).
- `bin/plantuml` runs that jar: `plantuml -tsvg diagram.puml`.
- `scripts/setup-vscode-settings.sh` merges `vscode-machine-settings.json` into the remote
  settings of the VS Code server (`~/.vscode-server/data/Machine/settings.json`). They override
  the laptop's User settings, so a laptop path to `plantuml.jar` doesn't break the preview, and
  they keep both extensions rendering locally (no diagram content goes to a public server).
  Like the extensions, `shell/env.sh` reruns it in the background until the server exists.
- Preview a `.puml` file: **Alt+D** (`jebbs.plantuml`). Preview Markdown with diagrams:
  **Markdown Preview Enhanced: Open Preview to the Side** (Ctrl+K V).
- Add more remote settings: edit `vscode-machine-settings.json` (plain JSON, `~/` is expanded).
  Log: `~/.cache/ona-config/vscode-settings.log`

## Claude Code settings

`install.sh` runs `scripts/setup-claude-settings.sh`, which merges
`"attribution": {"commit": "", "pr": ""}` (and the legacy `"includeCoAuthoredBy": false`)
into `~/.claude/settings.json`, so Claude Code adds no `Co-Authored-By: Claude …` trailer to
commits and no "Generated with Claude Code" line to PRs. The keys Ona writes there
(`env` with the proxy) are kept. Ona's `/usr/local/bin/welcome-claude.sh` rewrites the file
in every new shell, so `shell/env.sh` (sourced after it) adds the keys back when they are missing.

- Re-run any time: `bash ~/…/ona-config/scripts/setup-claude-settings.sh`
