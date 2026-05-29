

#!/usr/bin/env bash
set -euo pipefail

# Safety check routine for Ubuntu 24.04 VPS servers.
#
# Default behavior:
#   - Audits SSH and sudo safety-related settings.
#   - Does not change system configuration.
#
# Optional behavior:
#   - Use --enable-passwordless-sudo to create/update:
#       /etc/sudoers.d/eugene-nopasswd
#
# Usage:
#   ./scripts/safety-check.sh
#   ./scripts/safety-check.sh --enable-passwordless-sudo
#   DEFAULT_USER=eugene ./scripts/safety-check.sh

DEFAULT_USER="${DEFAULT_USER:-eugene}"
ENABLE_PASSWORDLESS_SUDO=false

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

ok() {
  printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

fail() {
  printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $0 [--enable-passwordless-sudo]

Environment variables:
  DEFAULT_USER=eugene

Examples:
  $0
  $0 --enable-passwordless-sudo
  DEFAULT_USER=eugene $0 --enable-passwordless-sudo
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --enable-passwordless-sudo)
        ENABLE_PASSWORDLESS_SUDO=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

require_ubuntu() {
  if [ ! -r /etc/os-release ]; then
    die "Cannot detect OS because /etc/os-release is missing."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [ "${ID:-}" != "ubuntu" ]; then
    die "This script supports Ubuntu only. Detected: ${PRETTY_NAME:-unknown}."
  fi

  if [ "${VERSION_ID:-}" != "24.04" ]; then
    warn "Expected Ubuntu 24.04 LTS, detected: ${PRETTY_NAME:-unknown}. Continuing anyway."
  else
    ok "Detected ${PRETTY_NAME:-Ubuntu 24.04 LTS}."
  fi
}

require_user_exists() {
  if id "$DEFAULT_USER" >/dev/null 2>&1; then
    ok "User exists: $DEFAULT_USER"
  else
    die "User does not exist: $DEFAULT_USER"
  fi
}

require_sudo_command() {
  if command -v sudo >/dev/null 2>&1; then
    ok "sudo is installed."
  else
    die "sudo is not installed."
  fi
}

get_sshd_effective_value() {
  local key="$1"

  if command -v sshd >/dev/null 2>&1; then
    sudo sshd -T 2>/dev/null | awk -v target="${key,,}" '$1 == target { print $2; exit }'
  fi
}

check_sshd_config_syntax() {
  log "Checking sshd configuration syntax"

  if sudo sshd -t; then
    ok "sshd configuration syntax is valid."
  else
    fail "sshd configuration syntax check failed."
    return 1
  fi
}

check_ssh_password_login_disabled() {
  log "Checking SSH password login settings"

  local password_auth
  local kbd_auth
  local challenge_auth

  password_auth="$(get_sshd_effective_value PasswordAuthentication || true)"
  kbd_auth="$(get_sshd_effective_value KbdInteractiveAuthentication || true)"
  challenge_auth="$(get_sshd_effective_value ChallengeResponseAuthentication || true)"

  if [ "$password_auth" = "no" ]; then
    ok "PasswordAuthentication is disabled."
  else
    fail "PasswordAuthentication is not disabled. Effective value: ${password_auth:-unknown}"
  fi

  if [ "$kbd_auth" = "no" ]; then
    ok "KbdInteractiveAuthentication is disabled."
  else
    fail "KbdInteractiveAuthentication is not disabled. Effective value: ${kbd_auth:-unknown}"
  fi

  # On newer OpenSSH, ChallengeResponseAuthentication may be absent/merged into KbdInteractiveAuthentication.
  if [ -n "$challenge_auth" ]; then
    if [ "$challenge_auth" = "no" ]; then
      ok "ChallengeResponseAuthentication is disabled."
    else
      warn "ChallengeResponseAuthentication effective value: $challenge_auth"
    fi
  fi
}

check_root_login_policy() {
  log "Checking SSH root login policy"

  local permit_root_login
  permit_root_login="$(get_sshd_effective_value PermitRootLogin || true)"

  case "$permit_root_login" in
    no)
      ok "PermitRootLogin is disabled."
      ;;
    prohibit-password|without-password)
      ok "PermitRootLogin allows key-only root login. This is acceptable, but 'no' is stricter."
      ;;
    yes)
      fail "PermitRootLogin is fully enabled. Consider setting it to 'no'."
      ;;
    *)
      warn "PermitRootLogin effective value: ${permit_root_login:-unknown}"
      ;;
  esac
}

check_public_key_auth() {
  log "Checking public key authentication"

  local pubkey_auth
  pubkey_auth="$(get_sshd_effective_value PubkeyAuthentication || true)"

  if [ "$pubkey_auth" = "yes" ]; then
    ok "PubkeyAuthentication is enabled."
  else
    fail "PubkeyAuthentication is not enabled. Effective value: ${pubkey_auth:-unknown}"
  fi

  local authorized_keys
  authorized_keys="$(eval echo "~$DEFAULT_USER/.ssh/authorized_keys")"

  if [ -s "$authorized_keys" ]; then
    ok "$authorized_keys exists and is not empty."
  else
    fail "$authorized_keys is missing or empty. SSH key login may not work for $DEFAULT_USER."
  fi
}

check_user_password_state() {
  log "Checking local password state for $DEFAULT_USER"

  local passwd_status
  passwd_status="$(sudo passwd -S "$DEFAULT_USER" 2>/dev/null || true)"

  if [ -z "$passwd_status" ]; then
    warn "Could not read password status for $DEFAULT_USER."
    return
  fi

  printf '%s\n' "$passwd_status"

  # passwd -S second field examples:
  #   P  = usable password
  #   L  = locked password
  #   NP = no password
  local status_field
  status_field="$(printf '%s\n' "$passwd_status" | awk '{ print $2 }')"

  case "$status_field" in
    P)
      ok "$DEFAULT_USER has a local password set."
      ;;
    L)
      ok "$DEFAULT_USER password is locked. This is common for SSH-key-only cloud users."
      ;;
    NP)
      warn "$DEFAULT_USER has no local password set. sudo may require passwordless sudo for automation."
      ;;
    *)
      warn "Unknown password status field for $DEFAULT_USER: $status_field"
      ;;
  esac
}

check_sudo_membership() {
  log "Checking sudo membership for $DEFAULT_USER"

  if id -nG "$DEFAULT_USER" | tr ' ' '\n' | grep -qx sudo; then
    ok "$DEFAULT_USER is in the sudo group."
  else
    fail "$DEFAULT_USER is not in the sudo group."
  fi
}

check_passwordless_sudo() {
  log "Checking passwordless sudo for $DEFAULT_USER"

  if sudo -n -u "$DEFAULT_USER" sudo -n true >/dev/null 2>&1; then
    ok "$DEFAULT_USER can run sudo without a password."
  else
    warn "$DEFAULT_USER cannot currently run sudo without a password."
  fi
}

enable_passwordless_sudo() {
  log "Enabling passwordless sudo for $DEFAULT_USER"

  require_sudo_command
  require_user_exists

  local sudoers_file
  sudoers_file="/etc/sudoers.d/${DEFAULT_USER}-nopasswd"

  local sudoers_line
  sudoers_line="${DEFAULT_USER} ALL=(ALL) NOPASSWD:ALL"

  printf '%s\n' "$sudoers_line" | sudo tee "$sudoers_file" >/dev/null
  sudo chmod 0440 "$sudoers_file"

  if sudo visudo -cf "$sudoers_file" >/dev/null; then
    ok "sudoers file is valid: $sudoers_file"
  else
    sudo rm -f "$sudoers_file"
    die "Invalid sudoers file generated. Removed: $sudoers_file"
  fi

  if sudo -n -u "$DEFAULT_USER" sudo -n true >/dev/null 2>&1; then
    ok "Passwordless sudo is now enabled for $DEFAULT_USER."
  else
    warn "sudoers file was installed, but passwordless sudo test did not pass in this session."
  fi
}

print_summary() {
  log "Summary"

  cat <<EOF
Checked user: $DEFAULT_USER

Expected secure baseline:
  - SSH public key authentication enabled
  - SSH password authentication disabled
  - keyboard-interactive password login disabled
  - root SSH login disabled or at least key-only
  - $DEFAULT_USER exists and belongs to sudo group
  - optional passwordless sudo for automation

Manual inspection commands:
  sudo sshd -T | grep -E 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication'
  sudo passwd -S $DEFAULT_USER
  id $DEFAULT_USER
  sudo -l -U $DEFAULT_USER
EOF
}

main() {
  parse_args "$@"

  require_ubuntu
  require_sudo_command
  require_user_exists

  check_sshd_config_syntax
  check_ssh_password_login_disabled
  check_root_login_policy
  check_public_key_auth
  check_user_password_state
  check_sudo_membership
  check_passwordless_sudo

  if [ "$ENABLE_PASSWORDLESS_SUDO" = true ]; then
    enable_passwordless_sudo
    check_passwordless_sudo
  fi

  print_summary
}

main "$@"