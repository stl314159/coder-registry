#!/bin/bash
set -o errexit
set -o pipefail

NODE_VERSION=22
LOCAL_BIN_DIR="${HOME}/.local/bin"
LOCAL_NODE_DIR="${HOME}/.local/node"
NPM_GLOBAL_DIR="${HOME}/.npm-global"

ensure_local_bin_on_path() {
  export PATH="${LOCAL_BIN_DIR}:${NPM_GLOBAL_DIR}/bin:${PATH}"
  mkdir -p "${LOCAL_BIN_DIR}"

  if ! grep -q 'export PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH' "${HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH' >> "${HOME}/.bashrc"
  fi
}

install_node_binary() {
  local arch=""
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac

  local shasums="/tmp/node-shasums.txt"
  local tarball=""
  local install_root="${LOCAL_NODE_DIR}/current"

  mkdir -p "${LOCAL_NODE_DIR}" "${LOCAL_BIN_DIR}"

  curl --retry 5 --retry-delay 3 -fsSL \
    "https://nodejs.org/dist/latest-v${NODE_VERSION}.x/SHASUMS256.txt" \
    -o "${shasums}"
  tarball=$(grep "linux-${arch}.tar.xz" "${shasums}" | awk '{print $2}')

  if [ -z "${tarball}" ]; then
    echo "Could not determine Node.js tarball for architecture ${arch}"
    exit 1
  fi

  curl --retry 5 --retry-delay 3 -fsSL \
    "https://nodejs.org/dist/latest-v${NODE_VERSION}.x/${tarball}" \
    -o "/tmp/${tarball}"
  grep "${tarball}" "${shasums}" | (cd /tmp && sha256sum -c -)

  rm -rf "${install_root}.tmp"
  mkdir -p "${install_root}.tmp"
  tar -xJf "/tmp/${tarball}" -C "${install_root}.tmp" --strip-components=1
  rm -rf "${install_root}"
  mv "${install_root}.tmp" "${install_root}"

  ln -sf "${install_root}/bin/node" "${LOCAL_BIN_DIR}/node"
  ln -sf "${install_root}/bin/npm" "${LOCAL_BIN_DIR}/npm"
  ln -sf "${install_root}/bin/npx" "${LOCAL_BIN_DIR}/npx"
  if [ -x "${install_root}/bin/corepack" ]; then
    ln -sf "${install_root}/bin/corepack" "${LOCAL_BIN_DIR}/corepack"
  fi

  rm -f "/tmp/${tarball}" "${shasums}"
}

ensure_node_and_npm() {
  ensure_local_bin_on_path

  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing prebuilt Node.js ${NODE_VERSION}.x..."
  install_node_binary
  echo "Node.js installed: $(node --version)"
  echo "npm installed: $(npm --version)"
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

ensure_node_and_npm
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
