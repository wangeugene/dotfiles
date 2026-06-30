#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Allow ingress ports for common services via UFW
#   - HTTP      (80/tcp)
#   - HTTPS     (443/tcp)
#   - Hysteria2 (443/udp — change HYSTERIA2_PORT below if needed)
# ──────────────────────────────────────────────

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: please run this script with sudo."
  echo "Example: sudo $0"
  exit 1
fi

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

echo "No need to reload the UFW service to make the change take effect"

echo "Showing the iptable information before updating:"
sudo iptables -L INPUT -n -v --line-numbers

# Allow ingress ports before Oracle/Ubuntu's default REJECT rule.
#
# Services:
#   HTTP      TCP 80
#   HTTPS     TCP 443
#   Hysteria2 UDP 443
#
# Usage:
#   sudo ./allow-ingress-ports.sh

echo "Updating iptables rules to allow ingress ports before REJECT rules..."

allow_before_reject() {
  local proto="$1"
  local port="$2"
  local comment="$3"

  # If the rule already exists, do nothing.
  if iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
    echo "Already allowed: $proto/$port ($comment)"
    return 0
  fi

  # Find the first REJECT rule in the INPUT chain.
  local reject_line
  reject_line="$(iptables -L INPUT --line-numbers -n | awk '$2 == "REJECT" {print $1; exit}')"

  if [[ -n "${reject_line}" ]]; then
    iptables -I INPUT "${reject_line}" -p "$proto" --dport "$port" -j ACCEPT
    echo "Inserted before REJECT: $proto/$port ($comment)"
  else
    iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
    echo "Appended rule: $proto/$port ($comment)"
  fi
}

allow_before_reject tcp 80 "HTTP"
allow_before_reject tcp 443 "HTTPS"
allow_before_reject udp 443 "Hysteria2"

echo
echo "Current INPUT rules:"
iptables -L INPUT -n -v --line-numbers