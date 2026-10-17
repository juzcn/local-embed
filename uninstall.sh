#!/usr/bin/env bash
set -euo pipefail

# local-embed uninstaller for macOS, Linux, and WSL.
# Usage:
#   ./uninstall.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

echo ""
echo -e "${CYAN}local-embed Uninstaller${NC}"
echo ""

# 1. Uninstall from uv tool
if uv tool list 2>/dev/null | grep -qF "local-embed"; then
    echo -e "${YELLOW}Uninstalling local-embed…${NC}"
    if uv tool uninstall local-embed 2>&1; then
        echo -e "  ${GREEN}✓${NC} local-embed removed"
    else
        echo -e "  ${RED}✗${NC} uninstall failed"
    fi
else
    echo -e "${GRAY}local-embed is not installed.${NC}"
fi

# 2. Clean up wrapper binaries
LOCAL_BIN="$HOME/.local/bin"
for bin in "$LOCAL_BIN/local-embed"; do
    if [ -f "$bin" ] || [ -L "$bin" ]; then
        rm -f "$bin"
        echo -e "  ${GRAY}Removed: $bin${NC}"
    fi
done

# 3. Remaining data
echo ""
DATA_DIR="$HOME/.local-embed"
if [ -d "$DATA_DIR" ]; then
    SIZE=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
    echo -e "${YELLOW}Data files NOT removed (delete manually if desired):${NC}"
    echo -e "${GRAY}  ~/.local-embed/        (${SIZE:-?}) — local_embed.yaml config${NC}"
else
    echo -e "${GREEN}  ✓${NC} No remaining data files."
fi

echo ""
echo -e "${GRAY}Model weights under ~/.cache/huggingface/hub are shared with other tools${NC}"
echo -e "${GRAY}and are never touched by this script.${NC}"
echo ""
echo -e "${CYAN}Done.${NC}"
