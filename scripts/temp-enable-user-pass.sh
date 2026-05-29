

#!/usr/bin/env bash
set -euo pipefail

# Temporarily enable a local Unix password for a VPS user, then remove/lock it later.
#
# Purpose:
#   - Useful when sudo still prompts for a password during initial VPS setup.
#   - Assumes SSH password login is disabled, so the temporary password is for local sudo only.
#
# Default user:
#   eugene
#
# Usage:
#   ./scripts/temp-enable-user-pass.sh status
#   ./scripts/temp-enable-user-pass.sh enable
#   ./scripts/temp-enable-user-pass.sh disable
#   ./scripts/temp-enable-user-pass.sh check-ssh
#   DEFAULT_USER=eugene ./scripts/temp-enable-user-pass.sh status

DEFAULT_USER="${DEFAULT_USER:-eugene}"

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

ok() {
  printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $0 <command>

Commands:
  status     Show password/sudo/SSH baseline status for the default user
  enable     Set a temporary local password for the default user
  disable    Delete and lock the default user's local password
  check-ssh  Show effective sshd authentication settings

Environment variables:
  DEFAULT_USER=eugene

Examples:
  $0 status
  $0 enable
  $0 disable
  $0 check-ssh
  DEFAULT_USER=eugene $0 status
EOF
}

require_user_exists() {
  if ! id "$DEFAULT_USER" >/dev/null 2>&1; then
    die "User does not exist: $DEFAULT_USER"
  fi
}

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required but not installed."
  fi
}

show_password_status() {
  log "Password status for $DEFAULT_USER"
  sudo passwd -S "$DEFAULT_USER"

  cat <<EOF

passwd -S status field meaning:
  P  = usable local password exists
  L  = password is locked
  NP = no local password exists
EOF
}

show_sudo_status() {
  log "sudo status for $DEFAULT_USER"

  if sudo -n -u "$DEFAULT_USER" sudo -n true >/dev/null 2>&1; then
    ok "$DEFAULT_USER can run sudo without a password."
  else
    warn "$DEFAULT_USER cannot run sudo without a password, or sudo requires interactive authentication."
  fi

  log "sudo rules for $DEFAULT_USER"
  sudo -l -U "$DEFAULT_USER" || true
}

show_ssh_status() {
  log "Effective sshd authentication settings"

  if ! command -v sshd >/dev/null 2>&1; then
    die "sshd is not installed or not available in PATH."
  fi

  sudo sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|permitrootlogin|pubkeyauthentication) ' || true

  cat <<EOF

Expected secure baseline:
  passwordauthentication no
  kbdinteractiveauthentication no
  pubkeyauthentication yes
  permitrootlogin no

Note:
  permitrootlogin prohibit-password is also common on cloud images, but 'no' is stricter.
EOF
}

enable_temp_password() {
  log "Setting a temporary local password for $DEFAULT_USER"

  cat <<EOF
You will now be prompted to enter a temporary password twice.

Use this only for local sudo recovery/setup.
After setup, run:
  $0 disable
EOF

  sudo passwd "$DEFAULT_USER"

  log "Temporary password status after enabling"
  sudo passwd -S "$DEFAULT_USER"
}

disable_temp_password() {
  log "Deleting local password for $DEFAULT_USER"
  sudo passwd -d "$DEFAULT_USER"

  log "Locking local password for $DEFAULT_USER"
  sudo passwd -l "$DEFAULT_USER"

  log "Password status after disable/lock"
  sudo passwd -S "$DEFAULT_USER"

  log "Rechecking SSH password-login baseline"
  show_ssh_status
}

status() {
  show_password_status
  show_sudo_status
  show_ssh_status
}

main() {
  local command="${1:-}"

  if [ -z "$command" ]; then
    usage
    exit 1
  fi

  require_sudo
  require_user_exists

  case "$command" in
    status)
      status
      ;;
    enable)
      enable_temp_password
      ;;
    disable)
      disable_temp_password
      ;;
    check-ssh)
      show_ssh_status
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"