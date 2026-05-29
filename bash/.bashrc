

#!/usr/bin/env bash
# ~/.bashrc managed by dotfiles
# Shared Bash configuration for Ubuntu VPS servers.

# Return early for non-interactive shells.
case $- in
  *i*) ;;
  *) return ;;
esac

# -----------------------------------------------------------------------------
# PATH
# -----------------------------------------------------------------------------

# User-installed binaries, for example the fd -> fdfind symlink created by
# scripts/install.sh.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# -----------------------------------------------------------------------------
# Editor defaults
# -----------------------------------------------------------------------------

if command -v nvim >/dev/null 2>&1; then
  export EDITOR="nvim"
  export VISUAL="nvim"
elif command -v vim >/dev/null 2>&1; then
  export EDITOR="vim"
  export VISUAL="vim"
else
  export EDITOR="vi"
  export VISUAL="vi"
fi

# -----------------------------------------------------------------------------
# History
# -----------------------------------------------------------------------------

export HISTCONTROL="ignoreboth:erasedups"
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend

# Append to history after each command and reload new commands from other shells.
export PROMPT_COMMAND="history -a; history -n${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# -----------------------------------------------------------------------------
# Shell behavior
# -----------------------------------------------------------------------------

shopt -s checkwinsize

# Enable programmable completion when available.
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# -----------------------------------------------------------------------------
# General aliases
# -----------------------------------------------------------------------------

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

alias ..='cd ..'
alias ...='cd ../..'

if command -v nvim >/dev/null 2>&1; then
  alias v='nvim'
  alias vim='nvim'
fi

# -----------------------------------------------------------------------------
# Tool aliases
# -----------------------------------------------------------------------------

if command -v fd >/dev/null 2>&1; then
  alias f='fd'
elif command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
  alias f='fdfind'
fi

if command -v rg >/dev/null 2>&1; then
  alias r='rg'
fi

if command -v delta >/dev/null 2>&1; then
  export GIT_PAGER='delta'
fi

# -----------------------------------------------------------------------------
# Git aliases
# -----------------------------------------------------------------------------

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate --all'
alias gp='git push'
alias gpl='git pull'

# -----------------------------------------------------------------------------
# Docker aliases
# -----------------------------------------------------------------------------

alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dlog='docker logs -f'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dcp='docker compose ps'

# -----------------------------------------------------------------------------
# tmux aliases
# -----------------------------------------------------------------------------

alias ta='tmux attach -t'
alias tls='tmux ls'
alias tn='tmux new -s'

# -----------------------------------------------------------------------------
# Common project paths
# -----------------------------------------------------------------------------

if [ -d /app ]; then
  alias app='cd /app'
fi

# -----------------------------------------------------------------------------
# Machine-specific local config
# -----------------------------------------------------------------------------

# Keep secrets and host-specific settings here. Do not commit this file.
if [ -f "$HOME/.bashrc.local" ]; then
  . "$HOME/.bashrc.local"
fi