#!/usr/bin/env bash
# Installs the GitHub CLI (gh), Azure CLI (az + azure-devops extension),
# python3 + PyYAML (needed by the Claude Code skills), and Node.js (npx, for
# cspell) + cargo-nextest (both needed by the custom-pre-pr-checks skill), and
# Java + Graphviz + a pinned PlantUML jar (for PlantUML diagrams in Markdown docs),
# and poppler-utils (pdftoppm, pdftotext: Claude Code reads PDF files with them).
# Idempotent: skips anything already installed.
# gh comes from the GitHub release tarball. The apt packages are collected and
# installed with ONE apt-get update + install (the Ubuntu mirrors are slow
# over plain HTTP from the Ona network, so they are switched to HTTPS). Without
# apt + sudo, az and python3 fall back to a no-root install into ~/.local.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

BIN="$HOME/.local/bin"; mkdir -p "$BIN"; export PATH="$BIN:$PATH"
log()  { echo "[install-tools] $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [[ $EUID -ne 0 ]]; then
  if have sudo && sudo -n true 2>/dev/null; then SUDO="sudo"; else SUDO="NONE"; fi
fi
can_apt() { have apt-get && have dpkg && [[ "$SUDO" != "NONE" ]]; }
ARCH_DEB="$(dpkg --print-architecture 2>/dev/null || true)"
APT_PKGS=()

# Ubuntu mirrors: HTTPS instead of HTTP (plain HTTP goes through a slow proxy:
# 32 s vs 1.6 s for the same index file), no backports, no translation files.
apt_tune() {
  local f
  printf 'Acquire::Languages "none";\nAcquire::Retries "3";\n' \
    | $SUDO tee /etc/apt/apt.conf.d/99ona-config >/dev/null
  dpkg -s ca-certificates >/dev/null 2>&1 || return 0
  for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list; do
    [[ -f "$f" ]] || continue
    $SUDO sed -i -E -e 's#http://(archive|security)\.ubuntu\.com#https://\1.ubuntu.com#g' \
      -e '/^Suites:/s/ [a-z]+-backports//g' -e '/^deb .*-backports /d' "$f"
  done
}

# ---------------------------------------------------------------- gh
install_gh_local() {
  local arch ver tmp
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;; esac
  # The latest-release redirect avoids the rate limit of the GitHub API.
  ver="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)"
  ver="${ver##*/v}"
  [[ -n "$ver" ]] || return 1
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_${arch}.tar.gz" \
    | tar -xz -C "$tmp" && install -m 755 "$tmp"/gh_*/bin/gh "$BIN/gh"
  rm -rf "$tmp"
}

# ---------------------------------------------------------------- az
# Adds the Microsoft apt repo; azure-cli is installed with the other apt packages.
add_az_repo() {
  . /etc/os-release
  $SUDO install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | $SUDO tee /etc/apt/keyrings/microsoft.asc >/dev/null || return 1
  $SUDO chmod go+r /etc/apt/keyrings/microsoft.asc
  printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: %s\nComponents: main\nArchitectures: %s\nSigned-by: /etc/apt/keyrings/microsoft.asc\n' \
    "${VERSION_CODENAME:?}" "$ARCH_DEB" | $SUDO tee /etc/apt/sources.list.d/azure-cli.sources >/dev/null
}
install_az_local() {
  # uv brings its own Python, so this works without root or system Python
  have uv || curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null
  uv tool install --quiet azure-cli
}

# ---------------------------------------------------------------- python3 (for the Claude Code skills)
install_python_local() {
  # uv-managed Python, exposed as ~/.local/bin/python3
  have uv || curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null
  uv python install --quiet --default --preview && have python3 \
    && uv pip install --quiet --system --break-system-packages --python python3 pyyaml
}

# ---------------------------------------------------------------- node + npx (for cspell)
# The current LTS from nodejs.org into ~/.local/node, without root; the Ubuntu
# apt package is too old for cspell. Needs python3 (installed above).
install_node_local() {
  local arch ver file tmp rc
  case "$(uname -m)" in x86_64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;; esac
  ver="$(curl -fsSL https://nodejs.org/dist/index.json \
    | python3 -c 'import json, sys; print(next(r["version"] for r in json.load(sys.stdin) if r["lts"]))')"
  [[ -n "$ver" ]] || return 1
  file="node-${ver}-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/$file" "https://nodejs.org/dist/${ver}/${file}" \
    && curl -fsSL "https://nodejs.org/dist/${ver}/SHASUMS256.txt" | grep "  ${file}\$" \
      | (cd "$tmp" && sha256sum -c --quiet -) \
    && rm -rf "$HOME/.local/node" && mkdir -p "$HOME/.local/node" \
    && tar -xzf "$tmp/$file" -C "$HOME/.local/node" --strip-components=1 \
    && for b in node npm npx; do ln -sf "$HOME/.local/node/bin/$b" "$BIN/$b"; done
  rc=$?
  rm -rf "$tmp"
  return $rc
}

# ---------------------------------------------------------------- cargo-nextest
# The prebuilt binary into the cargo bin directory (https://nexte.st, "Pre-built binaries").
install_nextest() {
  local target dir="${CARGO_HOME:-$HOME/.cargo}/bin"
  case "$(uname -m)" in x86_64) target=linux ;; aarch64|arm64) target=linux-arm ;; *) return 1 ;; esac
  mkdir -p "$dir"
  curl -fsSL "https://get.nexte.st/latest/$target" | tar -xz -C "$dir"
}

# ---------------------------------------------------------------- PlantUML (for diagrams in Markdown docs)
# Java + Graphviz from apt, and the PlantUML MIT jar of the pinned GitHub release
# (checksum-verified) into ~/.local/share/plantuml/plantuml.jar. bin/plantuml and the
# VS Code extensions (vscode-machine-settings.json) use this jar. To update, change
# the version and the sha256 (the "digest" of the asset in the GitHub release).
PLANTUML_VERSION="1.2025.4"
PLANTUML_SHA256="cb8bca6301c114eb66c6e6c55b4cd1962f380616c622e964596a24f94246bc41"
PLANTUML_JAR="$HOME/.local/share/plantuml/plantuml.jar"
plantuml_ok() { [[ -f "$PLANTUML_JAR" ]] && echo "$PLANTUML_SHA256  $PLANTUML_JAR" | sha256sum -c --quiet - >/dev/null 2>&1; }
install_plantuml_jar() {
  local tmp rc
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/plantuml.jar" \
    "https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-mit-${PLANTUML_VERSION}.jar" \
    && echo "$PLANTUML_SHA256  $tmp/plantuml.jar" | sha256sum -c --quiet - \
    && mkdir -p "$(dirname "$PLANTUML_JAR")" \
    && install -m 644 "$tmp/plantuml.jar" "$PLANTUML_JAR"
  rc=$?
  rm -rf "$tmp"
  return $rc
}

# ---------------------------------------------------------------- poppler-utils (for reading PDF files)
# pdftoppm renders PDF pages for the Read tool of Claude Code; pdftotext extracts the text.

# ---------------------------------------------------------------- run
if have gh; then log "gh already installed ($(gh --version | head -1))"
else
  log "installing gh..."
  install_gh_local || log "WARNING: gh install failed"
fi

# Collect the missing apt packages, then one apt-get update + install for all.
if can_apt; then
  if ! have az; then
    if add_az_repo; then APT_PKGS+=(azure-cli); else log "WARNING: could not add the azure-cli apt repo"; fi
  fi
  have python3 && python3 -c 'import yaml' 2>/dev/null || APT_PKGS+=(python3 python3-yaml)
  have java && have dot || APT_PKGS+=(default-jre-headless graphviz fonts-dejavu-core)
  have pdftoppm && have pdftotext || APT_PKGS+=(poppler-utils)
  if [[ ${#APT_PKGS[@]} -gt 0 ]]; then
    log "installing via apt: ${APT_PKGS[*]}..."
    apt_tune
    $SUDO apt-get update -qq || log "WARNING: apt-get update had errors"
    $SUDO apt-get install -y -qq --no-install-recommends "${APT_PKGS[@]}" >/dev/null \
      || log "WARNING: apt install had errors"
  fi
fi

if have az; then log "az available"
else
  log "installing az without root (takes a minute)..."
  install_az_local || log "WARNING: az install failed"
fi

if have az; then
  if az extension show --name azure-devops >/dev/null 2>&1; then
    log "az devops extension already installed"
  else
    log "installing az devops extension..."
    az extension add --name azure-devops --only-show-errors || log "WARNING: azure-devops extension failed"
  fi
fi

if have python3 && python3 -c 'import yaml' 2>/dev/null; then log "python3 available ($(python3 --version))"
else
  log "installing python3 + pyyaml without root..."
  install_python_local || log "WARNING: python3 install failed"
fi

if have node && have npx; then log "node already installed ($(node --version))"
else
  log "installing node (LTS) + npx..."
  install_node_local || log "WARNING: node install failed"
fi

if ! have cargo; then log "cargo not found, skipping cargo-nextest"
elif cargo nextest --version >/dev/null 2>&1; then log "cargo-nextest already installed"
else
  log "installing cargo-nextest..."
  install_nextest || log "WARNING: cargo-nextest install failed"
fi

have java && have dot || log "WARNING: java + graphviz missing (PlantUML needs apt + sudo)"

if plantuml_ok; then log "plantuml $PLANTUML_VERSION already installed"
else
  log "installing plantuml $PLANTUML_VERSION..."
  install_plantuml_jar || log "WARNING: plantuml install failed"
fi

have pdftoppm && have pdftotext || log "WARNING: poppler-utils missing (needs apt + sudo)"

have gh && log "gh: $(command -v gh)"
have az && log "az: $(command -v az)"
have python3 && log "python3: $(command -v python3)"
have npx && log "npx: $(command -v npx) (node $(node --version))"
have cargo && cargo nextest --version >/dev/null 2>&1 && log "cargo-nextest: $(cargo nextest --version | head -1)"
plantuml_ok && have java && log "plantuml: $PLANTUML_JAR ($PLANTUML_VERSION)"
have pdftoppm && log "pdftoppm: $(command -v pdftoppm)"
exit 0
