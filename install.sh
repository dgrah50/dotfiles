#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

brew_install_if_missing() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    return 0
  fi
  log "Installing $formula"
  brew install "$formula"
}

install_homebrew() {
  if have brew; then
    return 0
  fi
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_base_packages_macos() {
  install_homebrew

  brew update
  if [[ -f "$REPO_ROOT/Brewfile" ]]; then
    log "Installing Homebrew bundle from Brewfile"
    brew bundle --file "$REPO_ROOT/Brewfile"
  else
    brew_install_if_missing zsh
    brew_install_if_missing git
    brew_install_if_missing gh
    brew_install_if_missing curl
    brew_install_if_missing jq
    brew_install_if_missing node
    brew_install_if_missing nvm
    brew_install_if_missing bun
    brew_install_if_missing python
    brew_install_if_missing uv
    brew_install_if_missing fzf
    brew_install_if_missing tmux
    brew_install_if_missing ripgrep
    brew_install_if_missing bat
    brew_install_if_missing zoxide
    brew_install_if_missing go
    brew_install_if_missing rust
    brew_install_if_missing chezmoi
    brew_install_if_missing delta
  fi
}

install_base_packages_linux() {
  if have apt-get; then
    log "Installing packages with apt"
    sudo apt-get update
    sudo apt-get install -y zsh git gh curl jq fzf tmux ripgrep bat golang-go rustc cargo nodejs npm python3 python3-venv
    if ! command -v uv >/dev/null 2>&1; then
      curl -LsSf https://astral.sh/uv/install.sh | sh
      export PATH="$HOME/.local/bin:$PATH"
    fi
    if ! command -v bun >/dev/null 2>&1; then
      curl -fsSL https://bun.sh/install | bash
      export PATH="$HOME/.bun/bin:$PATH"
    fi
    if [[ ! -d "$HOME/.nvm" ]]; then
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    fi
    if ! have chezmoi; then
      sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  else
    log "Unsupported Linux package manager. Install dependencies manually."
    exit 1
  fi
}

install_oh_my_zsh() {
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My Zsh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  if [[ ! -d "$custom/plugins/zsh-autosuggestions" ]]; then
    log "Installing zsh-autosuggestions"
    git clone https://github.com/zsh-users/zsh-autosuggestions \
      "$custom/plugins/zsh-autosuggestions"
  fi
  if [[ ! -d "$custom/plugins/zsh-syntax-highlighting" ]]; then
    log "Installing zsh-syntax-highlighting"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$custom/plugins/zsh-syntax-highlighting"
  fi
}

install_fzf_extras() {
  if [[ "$OS" == "Darwin" ]]; then
    local fzf_install
    fzf_install="$(brew --prefix)/opt/fzf/install"
    if [[ -x "$fzf_install" ]]; then
      log "Installing fzf shell integration"
      "$fzf_install" --all --no-bash --no-fish >/dev/null
    fi
  fi
}

install_tmux_plugin_manager() {
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    log "Installing tmux plugin manager (TPM)"
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi

  if [[ -f "$HOME/.tmux.conf" ]]; then
    log "Installing tmux plugins from ~/.tmux.conf"
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" || true
  fi
}

install_gijq() {
  log "Installing gijq release from dgrah50/gijq"
  curl -fsSL https://raw.githubusercontent.com/dgrah50/gijq/main/scripts/install.sh | sh

  mkdir -p "$HOME/src"
  if [[ ! -d "$HOME/src/gijq/.git" ]]; then
    log "Cloning gijq repo to ~/src/gijq"
    git clone https://github.com/dgrah50/gijq.git "$HOME/src/gijq"
  else
    log "Updating ~/src/gijq"
    git -C "$HOME/src/gijq" pull --ff-only
  fi
}

apply_dotfiles_with_chezmoi() {
  log "Applying dotfiles with chezmoi source: $REPO_ROOT"
  chezmoi -S "$REPO_ROOT" init --apply
}

ensure_zsh_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    return 0
  fi

  if [[ "$SHELL" != "$zsh_path" ]]; then
    log "Current shell is $SHELL; attempting to switch to $zsh_path"
    if ! grep -qx "$zsh_path" /etc/shells; then
      log "Adding $zsh_path to /etc/shells"
      echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi
    chsh -s "$zsh_path" || true
  fi
}

main() {
  log "Bootstrapping system for dotfiles"

  case "$OS" in
    Darwin)
      install_base_packages_macos
      ;;
    Linux)
      install_base_packages_linux
      ;;
    *)
      log "Unsupported OS: $OS"
      exit 1
      ;;
  esac

  apply_dotfiles_with_chezmoi
  install_oh_my_zsh
  install_fzf_extras
  install_tmux_plugin_manager
  install_gijq
  ensure_zsh_default_shell

  log "Bootstrap complete. Open a new terminal session."
}

main "$@"
