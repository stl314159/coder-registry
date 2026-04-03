#!/bin/bash
set -o errexit
set -o pipefail

# Ensure npm-installed binaries are on PATH
export NVM_DIR="${HOME}/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Fall back to user-local npm prefix when nvm is not available
if ! command -v nvm &>/dev/null; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

if ! command -v pi &>/dev/null; then
  echo "ERROR: pi command not found"
  exit 1
fi

cd "${ARG_WORKDIR}"

# Build the command
CMD="pi"

# Decode and pass initial prompt if provided
PROMPT=""
if [ -n "${ARG_AI_PROMPT}" ]; then
  PROMPT=$(echo -n "${ARG_AI_PROMPT}" | base64 -d)
fi

# Add provider/model flags if set
if [ -n "${ARG_DEFAULT_PROVIDER}" ]; then
  CMD="${CMD} --provider ${ARG_DEFAULT_PROVIDER}"
fi
if [ -n "${ARG_DEFAULT_MODEL}" ]; then
  CMD="${CMD} --model ${ARG_DEFAULT_MODEL}"
fi

# If we have a prompt, pass it with -p for non-interactive use
if [ -n "$PROMPT" ]; then
  CMD="${CMD} -p \"${PROMPT}\""
fi

echo "Starting Pi: ${CMD}"
eval exec agentapi server --term-width 67 --term-height 1190 -- ${CMD}
