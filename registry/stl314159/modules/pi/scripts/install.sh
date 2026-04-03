#!/bin/bash
set -o errexit
set -o pipefail

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

# Ensure npm is available
if ! command -v npm &>/dev/null; then
  echo "npm not found, installing Node.js via nvm..."
  export NVM_DIR="${HOME}/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm use --lts
fi

# When nvm is not managing npm, set a user-local prefix to avoid EACCES on
# system-owned /usr/lib/node_modules.
if ! command -v nvm &>/dev/null; then
  mkdir -p "$HOME/.npm-global"
  npm config set prefix "$HOME/.npm-global"
  export PATH="$HOME/.npm-global/bin:$PATH"

  if ! grep -q 'export PATH=$HOME/.npm-global/bin:$PATH' ~/.bashrc 2>/dev/null; then
    echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
  fi
fi

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
