#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Allow ingress ports for common services via UFW
#   - HTTP      (80/tcp)
#   - HTTPS     (443/tcp)
#   - Hysteria2 (443/udp — change HYSTERIA2_PORT below if needed)
# ──────────────────────────────────────────────

HYSTERIA2_PORT="${HYSTERIA2_PORT:-443}"

if ! command -v ufw &>/dev/null; then
    echo "Error: ufw is not installed." >&2
    exit 1
fi

# Ensure UFW is active (won't error if already enabled)
ufw --force enable

echo "Allowing ingress ports..."

ufw allow 80/tcp    comment 'HTTP'
ufw allow 443/tcp   comment 'HTTPS'
ufw allow "${HYSTERIA2_PORT}/udp" comment 'Hysteria2'

echo ""
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  Current UFW rules:                                      │"
echo "└──────────────────────────────────────────────────────────┘"
ufw status numbered
