#!/bin/bash
set -o errexit
set -o pipefail

LOCAL_BIN_DIR="${HOME}/.local/bin"
NPM_GLOBAL_DIR="${HOME}/.npm-global"

ensure_local_bin_on_path() {
  export PATH="${LOCAL_BIN_DIR}:${NPM_GLOBAL_DIR}/bin:${PATH}"
  mkdir -p "${LOCAL_BIN_DIR}"

  if ! grep -q 'export PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH' "${HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH' >> "${HOME}/.bashrc"
  fi
}

if [ "${ARG_INSTALL}" != "true" ]; then
  echo "Skipping Pi installation (install_pi = false)"
  exit 0
fi

# Check if pi is already installed
if command -v pi &>/dev/null; then
  echo "Pi is already installed: $(pi --version 2>/dev/null || echo 'unknown version')"
  exit 0
fi

echo "Installing Pi coding agent..."

ensure_local_bin_on_path
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node command not found. Install Node.js before running the Pi module."
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm command not found. Install npm before running the Pi module."
  exit 1
fi

mkdir -p "${NPM_GLOBAL_DIR}"
npm config set prefix "${NPM_GLOBAL_DIR}"
export PATH="${LOCAL_BIN_DIR}:${NPM_GLOBAL_DIR}/bin:${PATH}"

# Install pi
if [ -n "${ARG_PI_VERSION}" ]; then
  npm install -g "@mariozechner/pi-coding-agent@${ARG_PI_VERSION}"
else
  npm install -g @mariozechner/pi-coding-agent
fi

echo "Pi installed: $(pi --version 2>/dev/null || echo 'ok')"

# Write settings.json if provider/model specified
PI_DIR="${HOME}/.pi/agent"
mkdir -p "$PI_DIR"

if [ -n "${ARG_DEFAULT_PROVIDER}" ] || [ -n "${ARG_DEFAULT_MODEL}" ]; then
  SETTINGS_FILE="${PI_DIR}/settings.json"
  echo "{}" > "$SETTINGS_FILE"

  if [ -n "${ARG_DEFAULT_PROVIDER}" ]; then
    tmp=$(mktemp)
    jq --arg p "${ARG_DEFAULT_PROVIDER}" '.defaultProvider = $p' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
  fi

  if [ -n "${ARG_DEFAULT_MODEL}" ]; then
    tmp=$(mktemp)
    jq --arg m "${ARG_DEFAULT_MODEL}" '.defaultModel = $m' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
  fi

  echo "Wrote Pi settings: $(cat "$SETTINGS_FILE")"
fi
