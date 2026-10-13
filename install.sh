#!/usr/bin/env bash
set -euo pipefail

# local-embed one-click installer for macOS, Linux, and WSL.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/juzcn/local-embed/main/install.sh | bash
#
# No prerequisites — the script installs uv if needed, then uses
# ``uv tool install --force`` in an isolated environment.  --force makes
# the script idempotent: first run installs, re-runs upgrade to the latest
# PyPI release.  Python is managed automatically by uv.
#
# The model backend is deliberately NOT installed here — it is platform-
# specific (gguf / transformer extras, see the README for per-OS commands).

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO="https://github.com/juzcn/local-embed"

echo -e "${CYAN}local-embed Installer${NC}"
echo ""
echo "Install method : uv tool install --force (isolated environment; re-run = update)"
echo "User data      : ~/.local-embed/local_embed.yaml (config)"
echo "Model cache    : ~/.cache/huggingface (pre-downloaded weights)"
echo "Python         : 3.13+ (managed by uv)"
echo ""

# [1/2] Ensure uv is available.
if ! command -v uv &>/dev/null; then
    echo -e "${YELLOW}[1/2] Installing uv…${NC}"
    curl --progress-bar -Lf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi
echo -e "${GREEN}  ✓${NC} uv $(uv --version 2>&1)"

# [2/2] Install/update local-embed from PyPI.  --force: re-running this
# script upgrades an existing install (a plain ``uv tool install`` no-ops
# with "already installed").
#
# --python states the interpreter the tool environment needs.  Without it
# uv picks whichever interpreter it prefers, and local-embed requires
# >= 3.13 — an older environment has no compatible release to install at
# all.  With the constraint uv fetches a suitable interpreter, or fails
# loudly.
echo -e "${YELLOW}[2/2] Installing/updating local-embed…${NC}"
if uv tool install --force --python '>=3.13' local-embed; then
    echo -e "${GREEN}  ✓${NC} local-embed ready"
else
    echo -e "${RED}Error: local-embed installation failed.${NC}"
    echo -e "${YELLOW}Help: $REPO${NC}"
    exit 1
fi

export PATH="$HOME/.local/bin:$PATH"

# When piped to bash, the export above only affects this subshell.
if ! command -v local-embed &>/dev/null; then
    echo ""
    echo -e "${YELLOW}IMPORTANT: local-embed is installed but not on your current PATH.${NC}"
    echo -e "${YELLOW}  Run: source "$HOME/.local/bin/env"${NC}"
    echo -e "${YELLOW}  Or simply open a new terminal.${NC}"
fi

echo ""
echo -e "${YELLOW}The embedding backend is NOT installed.  It is a per-platform install —${NC}"
echo -e "${YELLOW}the command differs by OS and GPU.  See the matrix in the README.${NC}"
echo ""
echo -e "${GREEN}local-embed installed successfully!${NC}"
echo ""
echo -e "${CYAN}Get started:${NC}"
echo "  local-embed set-gguf bge-m3 --path /path/to/model.gguf   # point at a local .gguf model"
echo "  local-embed                                              # serve OpenAI-compatible /v1/embeddings"
echo ""
echo -e "${CYAN}More info:${NC} $REPO"