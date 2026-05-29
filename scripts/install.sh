#!/usr/bin/env bash
set -euo pipefail

# Idempotent Ubuntu 24.04 LTS server bootstrap script.
# Installs essential CLI tools, Node.js, pnpm, Docker Engine, and Docker Compose V2.

NODE_MAJOR="${NODE_MAJOR:-24}"

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
  if [ "$(id -u)" -eq 0 ]; then
    die "Do not run this script as root. Run it as your normal sudo-capable user."
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required but not installed."
  fi

  sudo -n true || die "Passwordless sudo is required. Run scripts/safety-check.sh --enable-passwordless-sudo first."
}

apt_install() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
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

  # Some Node.js distributions include Corepack; some may not.
  if ! command -v corepack >/dev/null 2>&1; then
    warn "corepack was not found. Installing Corepack globally with npm."
    sudo npm install -g corepack
  fi

  corepack enable
  corepack prepare pnpm@latest --activate
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
