#!/usr/bin/env bash
set -euo pipefail

# Idempotent Ubuntu 24.04 LTS server bootstrap script.
# Installs essential CLI tools, Node.js, pnpm, Docker Engine, and Docker Compose V2.

NODE_MAJOR="${NODE_MAJOR:-24}"
DEFAULT_USER="${DEFAULT_USER:-eugene}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARN: %s\033[0m\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

require_ubuntu_2404() {
  if [ ! -r /etc/os-release ]; then
    die "Cannot detect OS because /etc/os-release is missing."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
    die "This script supports Ubuntu 24.04 LTS only. Detected: ${PRETTY_NAME:-unknown}."
  fi
}

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required but not installed."
  fi

  if [ "$(id -u)" -eq 0 ]; then
    warn "Running as root. This is allowed only for first-time VPS bootstrap."
    return
  fi

  sudo -n true || die "Passwordless sudo is required. Run scripts/safety-check.sh --enable-passwordless-sudo first."
}

apt_install() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

resolve_default_user_ssh_key() {
  if [ -n "${SSH_PUBLIC_KEY}" ]; then
    printf '%s\n' "${SSH_PUBLIC_KEY}"
    return
  fi

  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ] && [ -r "/home/${SUDO_USER}/.ssh/authorized_keys" ]; then
    head -n 1 "/home/${SUDO_USER}/.ssh/authorized_keys"
    return
  fi

  if [ -r "$HOME/.ssh/authorized_keys" ]; then
    head -n 1 "$HOME/.ssh/authorized_keys"
    return
  fi

  die "No SSH public key found. Set SSH_PUBLIC_KEY='ssh-ed25519 ...' before running this script."
}

create_default_user() {
  log "Creating default user: ${DEFAULT_USER}"

  if ! getent group root >/dev/null 2>&1; then
    die "The root group does not exist on this system."
  fi

  if id "${DEFAULT_USER}" >/dev/null 2>&1; then
    log "User ${DEFAULT_USER} already exists"
  else
    sudo useradd \
      --create-home \
      --shell /bin/bash \
      --groups sudo,root \
      "${DEFAULT_USER}"
  fi

  sudo usermod -aG sudo,root "${DEFAULT_USER}"

  sudo install -d -m 0700 -o "${DEFAULT_USER}" -g "${DEFAULT_USER}" "/home/${DEFAULT_USER}/.ssh"

  local public_key
  public_key="$(resolve_default_user_ssh_key)"

  if ! sudo test -f "/home/${DEFAULT_USER}/.ssh/authorized_keys"; then
    printf '%s\n' "${public_key}" | sudo tee "/home/${DEFAULT_USER}/.ssh/authorized_keys" >/dev/null
  elif ! sudo grep -qxF "${public_key}" "/home/${DEFAULT_USER}/.ssh/authorized_keys"; then
    printf '%s\n' "${public_key}" | sudo tee -a "/home/${DEFAULT_USER}/.ssh/authorized_keys" >/dev/null
  fi

  sudo chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}/.ssh"
  sudo chmod 0700 "/home/${DEFAULT_USER}/.ssh"
  sudo chmod 0600 "/home/${DEFAULT_USER}/.ssh/authorized_keys"

  sudo install -d -m 0750 /etc/sudoers.d
  printf '%s\n' "${DEFAULT_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-${DEFAULT_USER}-nopasswd" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/90-${DEFAULT_USER}-nopasswd"
  sudo visudo -cf "/etc/sudoers.d/90-${DEFAULT_USER}-nopasswd" >/dev/null
}

harden_ssh_public_key_only() {
  log "Configuring SSH public-key-only authentication"

  sudo install -d -m 0755 /etc/ssh/sshd_config.d

  sudo tee /etc/ssh/sshd_config.d/99-public-key-only.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
UsePAM yes
EOF

  sudo sshd -t
  sudo systemctl reload ssh || sudo systemctl reload sshd
}

install_base_packages() {
  log "Installing base packages and common CLI tools"

  sudo apt-get update

  apt_install \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    git \
    tmux \
    neovim \
    tree \
    ripgrep \
    fd-find \
    git-delta \
    unzip \
    zip \
    jq \
    htop \
    rsync \
    stow
}

ensure_fd_command() {
  log "Ensuring fd command is available"

  mkdir -p "$HOME/.local/bin"

  if command -v fd >/dev/null 2>&1; then
    return
  fi

  if command -v fdfind >/dev/null 2>&1; then
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
    log "Created symlink: $HOME/.local/bin/fd -> $(command -v fdfind)"
  else
    warn "fdfind was not found after installing fd-find."
  fi
}

ensure_local_bin_in_path() {
  log "Checking ~/.local/bin PATH availability"

  case ":$PATH:" in
    *":$HOME/.local/bin:"*)
      return
      ;;
    *)
      warn "~/.local/bin is not currently in PATH. Add this to your shell config if needed: export PATH=\"$HOME/.local/bin:$PATH\""
      ;;
  esac
}

install_nodejs() {
  log "Installing Node.js ${NODE_MAJOR}.x from NodeSource"

  sudo install -d -m 0755 /etc/apt/keyrings

  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg.tmp

  sudo mv /etc/apt/keyrings/nodesource.gpg.tmp /etc/apt/keyrings/nodesource.gpg
  sudo chmod 0644 /etc/apt/keyrings/nodesource.gpg

  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null

  sudo apt-get update
  apt_install nodejs
}

install_pnpm() {
  log "Installing pnpm via Corepack"

  if ! command -v node >/dev/null 2>&1; then
    die "Node.js is required before installing pnpm."
  fi

  if ! command -v npm >/dev/null 2>&1; then
    die "npm is required before installing pnpm."
  fi

  # Some Node.js distributions include Corepack; some may not.
  if ! command -v corepack >/dev/null 2>&1; then
    warn "corepack was not found. Installing Corepack globally with npm."
    sudo -n npm install -g corepack
  fi

  # Corepack creates pnpm/yarn shims next to the Node.js binary.
  # On this VPS, that target is /usr/bin/pnpm, so it requires sudo.
  sudo -n corepack enable
  sudo -n corepack prepare pnpm@latest --activate

  # Refresh Bash's command lookup cache in case pnpm was just created.
  hash -r || true

  if command -v pnpm >/dev/null 2>&1; then
    ok_pnpm_version="$(pnpm --version)"
    log "pnpm installed: ${ok_pnpm_version}"
  else
    die "pnpm installation failed: pnpm command is still not available."
  fi
}

install_docker() {
  log "Installing Docker Engine and Docker Compose V2 from Docker apt repository"

  sudo install -d -m 0755 /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg.tmp

  sudo mv /etc/apt/keyrings/docker.gpg.tmp /etc/apt/keyrings/docker.gpg
  sudo chmod 0644 /etc/apt/keyrings/docker.gpg

  local arch
  arch="$(dpkg --print-architecture)"

  # shellcheck disable=SC1091
  . /etc/os-release

  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update

  apt_install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  sudo systemctl enable --now docker

  if ! groups "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    warn "Added $USER to the docker group. Log out and log back in before running Docker without sudo."
  fi
}

print_versions() {
  log "Installed versions"

  printf 'git: '; git --version || true
  printf 'delta: '; delta --version || true
  printf 'rg: '; rg --version | head -n 1 || true
  printf 'fd: '; fd --version || fdfind --version || true
  printf 'tmux: '; tmux -V || true
  printf 'nvim: '; nvim --version | head -n 1 || true
  printf 'tree: '; tree --version || true
  printf 'node: '; node --version || true
  printf 'npm: '; npm --version || true
  printf 'pnpm: '; pnpm --version || true
  printf 'docker: '; docker --version || true
  printf 'docker compose: '; docker compose version || true
}

main() {
  require_ubuntu_2404
  require_sudo

  create_default_user
  harden_ssh_public_key_only
  install_base_packages
  ensure_fd_command
  ensure_local_bin_in_path
  install_nodejs
  install_pnpm
  install_docker
  print_versions

  log "Bootstrap completed"
}

main "$@"
