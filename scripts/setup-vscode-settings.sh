#!/usr/bin/env bash
# Merges vscode-machine-settings.json into the remote settings of the VS Code
# server on this Ona machine (~/.vscode-server/data/Machine/settings.json).
# Remote settings override the laptop's User settings, e.g. a laptop path to
# plantuml.jar. Other keys in the file (Ona writes some) are kept. A string
# value starting with "~/" is expanded to $HOME.
# Without a server it does nothing; shell/env.sh runs it again in the
# background, so the settings follow as soon as VS Code has connected once.
# Idempotent: writes only when a value differs.
set -uo pipefail

DOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SRC="$DOT/vscode-machine-settings.json"
DST="$HOME/.vscode-server/data/Machine/settings.json"
log() { echo "[vscode-settings] $*"; }

[[ -f "$SRC" ]] || { log "no $SRC"; exit 0; }
[[ -d "$HOME/.vscode-server" ]] || { log "no VS Code server yet, skipping"; exit 0; }
command -v python3 >/dev/null 2>&1 || { log "WARNING: python3 missing, skipping"; exit 0; }
mkdir -p "$(dirname "$DST")"

python3 -I - "$SRC" "$DST" <<'EOF'
import json
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
home = os.path.expanduser("~")


def expand(value):
    if isinstance(value, str) and value.startswith("~/"):
        return home + value[1:]
    return value


with open(src) as f:
    wanted = {key: expand(value) for key, value in json.load(f).items()}

current = {}
if os.path.exists(dst) and os.path.getsize(dst) > 0:
    try:
        with open(dst) as f:
            current = json.load(f)
    except json.JSONDecodeError as error:
        print(f"[vscode-settings] WARNING: {dst} is not plain JSON ({error}), left unchanged")
        sys.exit(0)

changed = {key: value for key, value in wanted.items() if current.get(key) != value}
if not changed:
    sys.exit(0)

current.update(changed)
tmp = dst + ".tmp"
with open(tmp, "w") as f:
    json.dump(current, f, indent=4)
    f.write("\n")
os.replace(tmp, dst)
for key in changed:
    print(f"[vscode-settings] set {key}")
EOF
