#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -m 644 "$REPO_ROOT/bash/.bashrc" "$HOME/.bashrc"

echo "Installed shared .bashrc to $HOME/.bashrc"
