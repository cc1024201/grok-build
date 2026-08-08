#!/usr/bin/env bash
set -euo pipefail

PREFIX=${GROK_ULTRA_PREFIX:-"$HOME/.local"}
APP_DIR="$PREFIX/lib/grok-ultra"
LINK="$PREFIX/bin/grok-ultra"

rm -f "$LINK"
rm -rf "$APP_DIR"

echo "Removed the grok-ultra program."
echo "Isolated state was preserved at: ${GROK_ULTRA_HOME:-$HOME/.grok-ultra}"
echo "Delete that directory manually only when you also want to remove its login, sessions, memory, logs, caches, and worktrees."
