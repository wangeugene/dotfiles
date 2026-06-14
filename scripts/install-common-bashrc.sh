#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASHRC_TARGET="$HOME/.bashrc"

if [ -f "$BASHRC_TARGET" ]; then
  backup_path="$BASHRC_TARGET.backup.$(date +%Y%m%d%H%M%S)"
  cp "$BASHRC_TARGET" "$backup_path"
  echo "Backed up existing .bashrc to $backup_path"
fi

install -m 644 "$REPO_ROOT/.bashrc" "$BASHRC_TARGET"

echo "Installed shared .bashrc to $BASHRC_TARGET"
echo "Run 'source ~/.bashrc' in an interactive Bash shell to apply it now."
