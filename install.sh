#!/usr/bin/env bash
#
# Bootstrap a machine for these dotfiles (macOS via Homebrew, Linux via apt).
#
# Safe to re-run: every step inspects the current state first and only does the
# work that is missing, so a second run on a finished machine changes nothing
# and does not ask for sudo.
#
# Failure model:
#   * Steps that are optional (Oh My Zsh, TPM, gijq, default shell, ...) warn and
#     the script carries on; a summary at the end lists what to retry.
#   * Essential tools (git, curl, chezmoi) are verified before dotfiles are applied.
#   * The script exits non-zero if anything failed. Just run it again.
#
# Environment:
#   DOTFILES_FORCE=1   let chezmoi overwrite files in $HOME that differ from this
#                      repo. Without it chezmoi asks on a terminal and fails fast
#                      (instead of hanging) when there is none.
#   DOTFILES_UPGRADE=1 also update what is already installed to the latest
#                      version: Homebrew/apt packages, uv, bun, chezmoi, nvm,
#                      gijq, Oh My Zsh, its plugins, TPM and tmux plugins.
#                      Without it a re-run only fills in what is missing.
#                      Pull this repo yourself first to get newer dotfiles.
#
# Written to run on macOS's stock bash 3.2 as well (no mapfile, no assoc arrays).

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
NVM_VERSION="v0.40.3"
MAIN_PID=$$
STATE_DIR=""
FAILURES=()
UPGRADE=0
if [[ "${DOTFILES_UPGRADE:-}" == 1 ]]; then
  UPGRADE=1
fi

# Never block on a credentials prompt in the middle of a clone.
export GIT_TERMINAL_PROMPT=0

# --------------------------------------------------------------------------
# Logging and error handling
# --------------------------------------------------------------------------

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '\n[%s] WARNING: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

err() {
  printf '\n[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

die() {
  err "$*"
  exit 1
}

on_err() {
  local rc=$1 line=$2 cmd=$3
  # `exit`/die and the run_step wrapper are already reported by their own message.
  case "$cmd" in
    exit* | return* | "( set -e"*) return 0 ;;
  esac
  err "command failed (exit $rc) at line $line: $cmd"
}

cleanup() {
  local rc=$?
  if [[ -n "$STATE_DIR" && -d "$STATE_DIR" ]]; then
    if [[ -f "$STATE_DIR/sudo-keepalive.pid" ]]; then
      kill "$(cat "$STATE_DIR/sudo-keepalive.pid")" 2>/dev/null || true
    fi
    rm -rf "$STATE_DIR"
  fi
  return $rc
}

trap 'on_err "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'err "Interrupted"; exit 130' INT TERM

have() {
  command -v "$1" >/dev/null 2>&1
}

require_commands() {
  local missing=() c
  for c in "$@"; do
    have "$c" || missing+=("$c")
  done
  if (( ${#missing[@]} > 0 )); then
    die "Required tools are still missing: ${missing[*]}. Fix the warnings above and re-run."
  fi
}

# run_step <required|optional> <description> <function> [args...]
#
# Runs the function in a subshell with errexit on, so the first failing command
# ends the step (a plain `if ! fn` would silently switch errexit off inside fn).
# Because of the subshell, steps must not rely on setting variables for later steps.
run_step() {
  local kind="$1" desc="$2" rc=0
  shift 2

  set +e
  ( set -e; "$@" )
  rc=$?
  set -e

  if (( rc == 0 )); then
    return 0
  fi
  if [[ "$kind" == required ]]; then
    die "$desc failed (exit $rc)"
  fi
  warn "$desc failed (exit $rc); continuing. Re-run this script to retry."
  FAILURES+=("$desc")
}

# --------------------------------------------------------------------------
# sudo handling
# --------------------------------------------------------------------------

# Prime sudo once and keep the credential fresh for the rest of the run, so a
# long install can't expire it mid-way. Lazy: nothing asks for a password unless
# a step really needs root. Returns 1 if root can't be obtained, including when
# a password would be needed but there is no terminal to type it on.
acquire_sudo() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi
  have sudo || return 1
  if [[ -e "$STATE_DIR/sudo-ready" ]]; then
    return 0
  fi

  if ! sudo -n true 2>/dev/null; then
    [[ -t 0 ]] || return 1
    log "Administrator access is needed for the next step; sudo may ask for your password"
    sudo -v || return 1
  fi
  : >"$STATE_DIR/sudo-ready"

  (
    while kill -0 "$MAIN_PID" 2>/dev/null; do
      sudo -n true 2>/dev/null || exit 0
      sleep 50
    done
  ) >/dev/null 2>&1 &
  echo $! >"$STATE_DIR/sudo-keepalive.pid"
}

# Run a command as root: directly if already root, otherwise through sudo.
as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
    return
  fi
  if ! acquire_sudo; then
    err "root access is required to run: $*"
    err "Run as a user with sudo rights from a terminal, or run 'sudo -v' first (or as root)."
    return 1
  fi
  if [[ -t 0 ]]; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

# --------------------------------------------------------------------------
# Helpers: downloads, git, PATH
# --------------------------------------------------------------------------

retry() {
  local attempts="$1" i=1
  shift
  until "$@"; do
    if (( i >= attempts )); then
      return 1
    fi
    warn "attempt $i/$attempts failed: $*; retrying"
    sleep $(( i * 2 ))
    i=$(( i + 1 ))
  done
}

download() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 300 \
    -o "$2" "$1"
}

# run_remote_script <url> <shell> [args...]
# Downloads to a file first and only runs it if the download fully succeeded.
# (`sh -c "$(curl ...)"` and `curl | sh` happily "succeed" on a failed download.)
run_remote_script() {
  local url="$1" shell="$2" script
  shift 2
  script="$(mktemp "$STATE_DIR/script.XXXXXX")"
  download "$url" "$script"
  if [[ ! -s "$script" ]]; then
    err "downloaded an empty file from $url"
    return 1
  fi
  "$shell" "$script" "$@"
}

# git_clone <url> <dest> [depth]
# No-op if dest is already a git checkout. Clones into a temp dir and moves it
# into place, so an interrupted run can't leave a half-cloned dest behind that
# would make every later run fail. Never deletes or overwrites existing data.
git_clone() {
  local url="$1" dest="$2" depth="${3:-}" tmp
  local depth_args=()
  if [[ -n "$depth" ]]; then
    depth_args=(--depth "$depth")
  fi

  if [[ -d "$dest/.git" ]]; then
    return 0
  fi
  if [[ -e "$dest" ]]; then
    # An empty directory is fine to replace; anything else is somebody's data.
    if ! rmdir "$dest" 2>/dev/null; then
      warn "$dest exists but is not a git checkout; leaving it untouched"
      return 0
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  tmp="$dest.partial.$$"
  rm -rf "$tmp"
  log "Cloning $url -> $dest"
  if ! retry 3 git clone ${depth_args[@]+"${depth_args[@]}"} "$url" "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi
  mv "$tmp" "$dest"
}

# git_update <dir>: fast-forward an existing checkout; never fatal, never destructive.
git_update() {
  local dir="$1"
  if [[ ! -d "$dir/.git" ]]; then
    return 0
  fi
  git -C "$dir" pull --ff-only --quiet ||
    warn "Could not fast-forward $dir (local changes or diverged history); left as is"
}

# Make user-level install locations visible to *this* run. Without this, tools
# installed into ~/.local/bin or ~/.bun/bin on one run are invisible to `have`
# on the next (non-login shells don't have them on PATH) and get reinstalled.
ensure_path() {
  local d
  mkdir -p "$HOME/.local/bin"
  for d in "$HOME/.local/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin"; do
    case ":$PATH:" in
      *":$d:"*) ;;
      *) PATH="$d:$PATH" ;;
    esac
  done
  export PATH
}

# Put an existing Homebrew on PATH. A fresh shell on a machine that already has
# Homebrew often can't see `brew`, which used to trigger a pointless reinstall.
setup_brew_env() {
  local b
  if have brew; then
    return 0
  fi
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew \
    "$HOME/homebrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
    if [[ -x "$b" ]]; then
      eval "$("$b" shellenv)"
      return 0
    fi
  done
}

# --------------------------------------------------------------------------
# macOS
# --------------------------------------------------------------------------

install_homebrew() {
  setup_brew_env
  if have brew; then
    return 0
  fi

  log "Installing Homebrew"
  if ! acquire_sudo; then
    die "Homebrew's installer needs administrator access and sudo isn't usable here. Run 'sudo -v' in this terminal and re-run, or install Homebrew from https://brew.sh first."
  fi
  NONINTERACTIVE=1 run_remote_script \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh bash
  setup_brew_env
  have brew || die "Homebrew installed but 'brew' is still not on PATH"
}

install_base_packages_macos() {
  local brewfile="$REPO_ROOT/Brewfile"
  [[ -f "$brewfile" ]] || die "Brewfile not found at $brewfile"

  install_homebrew

  if (( UPGRADE )); then
    local name names=()
    log "Updating Homebrew and upgrading the formulae in the Brewfile"
    brew update || warn "brew update failed; continuing with the existing formula index"
    brew bundle --file "$brewfile"
    while IFS= read -r name; do
      if [[ -n "$name" ]]; then
        names+=("$name")
      fi
    done < <(brew bundle list --formula --file "$brewfile")
    if (( ${#names[@]} > 0 )); then
      brew upgrade --formula "${names[@]}"
    fi
    return 0
  fi

  if brew bundle check --file "$brewfile" >/dev/null 2>&1; then
    log "Homebrew bundle already satisfied"
    return 0
  fi

  log "Installing Homebrew bundle from Brewfile"
  brew update || warn "brew update failed; continuing with the existing formula index"
  brew bundle --file "$brewfile"
}

install_fzf_extras() {
  local fzf_install
  have brew || return 0
  fzf_install="$(brew --prefix)/opt/fzf/install"
  if [[ ! -x "$fzf_install" ]]; then
    return 0
  fi
  log "Installing fzf shell integration"
  # --no-update-rc: ~/.zshrc is managed by chezmoi; letting fzf append to it
  # makes the next `chezmoi apply` see drift. options.zsh sources ~/.fzf.zsh.
  "$fzf_install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null
}

# --------------------------------------------------------------------------
# Linux (apt)
# --------------------------------------------------------------------------

APT_PACKAGES=(
  git curl ca-certificates unzip zsh
  gh jq fzf tmux ripgrep bat zoxide git-delta
  golang-go rustc cargo nodejs npm python3 python3-venv
)

apt_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

apt_has_candidate() {
  local candidate
  candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

apt_update_once() {
  if [[ -e "$STATE_DIR/apt-updated" ]]; then
    return 0
  fi
  # A stale third-party repo makes `update` fail even though the rest works.
  as_root env DEBIAN_FRONTEND=noninteractive apt-get update -o DPkg::Lock::Timeout=120 ||
    warn "apt-get update failed; trying with the existing package lists"
  : >"$STATE_DIR/apt-updated"
}

upgrade_apt_packages() {
  local pkg installed=()
  for pkg in "${APT_PACKAGES[@]}"; do
    if apt_pkg_installed "$pkg"; then
      installed+=("$pkg")
    fi
  done
  if (( ${#installed[@]} == 0 )); then
    return 0
  fi
  log "Upgrading apt packages"
  if ! acquire_sudo; then
    err "Root access is needed to upgrade apt packages (run 'sudo -v' first, or run as root)."
    return 1
  fi
  apt_update_once
  apt_install --only-upgrade "${installed[@]}"
}

apt_install() {
  # --force-conf*: keep locally edited config files instead of stopping at a
  # dpkg "which version do you want?" prompt (fatal without a terminal).
  as_root env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -o DPkg::Lock::Timeout=120 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

install_base_packages_linux() {
  local pkg missing=() available=() unavailable=() failed=()

  have apt-get || die "Unsupported Linux package manager (apt-get not found). Install manually: ${APT_PACKAGES[*]}"

  for pkg in "${APT_PACKAGES[@]}"; do
    apt_pkg_installed "$pkg" || missing+=("$pkg")
  done

  if (( ${#missing[@]} == 0 )); then
    log "All apt packages already installed"
  else
    log "Installing missing apt packages: ${missing[*]}"
    if ! acquire_sudo; then
      err "Root access is needed to install: ${missing[*]}"
      err "sudo isn't usable here (not installed, no sudo rights, or a password is needed but there is no terminal)."
      err "Run 'sudo -v' in this terminal and re-run, ask an admin to install them, or run as root."
      return 1
    fi
    apt_update_once

    # One package that doesn't exist on this release (e.g. gh on older Ubuntu)
    # would otherwise abort the whole `apt-get install`.
    for pkg in "${missing[@]}"; do
      if apt_has_candidate "$pkg"; then
        available+=("$pkg")
      else
        unavailable+=("$pkg")
      fi
    done
    if (( ${#unavailable[@]} > 0 )); then
      warn "Not available from this system's apt repositories, skipping: ${unavailable[*]}"
    fi

    if (( ${#available[@]} > 0 )) && ! apt_install "${available[@]}"; then
      warn "Batch install failed; retrying packages one at a time to isolate the problem"
      for pkg in "${available[@]}"; do
        apt_pkg_installed "$pkg" || apt_install "$pkg" || failed+=("$pkg")
      done
      if (( ${#failed[@]} > 0 )); then
        warn "Could not install: ${failed[*]}"
      fi
    fi
  fi

  if (( UPGRADE )); then
    upgrade_apt_packages || failed+=("apt upgrade")
  fi

  # Debian/Ubuntu ship bat as `batcat`.
  if ! have bat && have batcat; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi

  # Packages missing from the repos only warn; ones apt tried and failed on are a failure.
  if (( ${#failed[@]} > 0 )); then
    return 1
  fi
}

install_uv() {
  if have uv && (( ! UPGRADE )); then
    return 0
  fi
  log "Installing uv (latest)"
  UV_NO_MODIFY_PATH=1 run_remote_script https://astral.sh/uv/install.sh sh
  have uv || die "uv installed but is not on PATH"
}

install_bun() {
  if have bun; then
    if (( UPGRADE )); then
      log "Upgrading bun"
      bun upgrade
    fi
    return 0
  fi
  have unzip || die "bun's installer needs 'unzip'"
  log "Installing bun"
  # An unrecognised $SHELL makes bun skip editing ~/.zshrc / ~/.bashrc, which
  # chezmoi manages (path.zsh already puts ~/.bun/bin on PATH).
  SHELL=/bin/sh run_remote_script https://bun.sh/install bash
  have bun || die "bun installed but is not on PATH"
}

# Latest nvm release tag via the releases redirect (no API rate limit); falls
# back to the pinned version if it can't be resolved.
latest_nvm_version() {
  local url tag
  url="$(curl -fsSLI --connect-timeout 15 -o /dev/null -w '%{url_effective}' \
    https://github.com/nvm-sh/nvm/releases/latest 2>/dev/null)" || url=""
  tag="${url##*/}"
  case "$tag" in
    v[0-9]*) printf '%s\n' "$tag" ;;
    *) printf '%s\n' "$NVM_VERSION" ;;
  esac
}

install_nvm() {
  local NVM_VERSION="$NVM_VERSION"
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    if (( ! UPGRADE )); then
      return 0
    fi
    NVM_VERSION="$(latest_nvm_version)"
  fi
  log "Installing nvm $NVM_VERSION"
  # PROFILE=/dev/null: don't append to shell rc files (path.zsh loads nvm).
  PROFILE=/dev/null NVM_DIR="$HOME/.nvm" run_remote_script \
    "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" bash
  [[ -s "$HOME/.nvm/nvm.sh" ]] || die "nvm installer finished but ~/.nvm/nvm.sh is missing"
}

install_chezmoi() {
  if have chezmoi && (( ! UPGRADE )); then
    return 0
  fi
  log "Installing chezmoi (latest)"
  run_remote_script https://get.chezmoi.io sh -b "$HOME/.local/bin"
  have chezmoi || die "chezmoi installed but is not on PATH"
}

# --------------------------------------------------------------------------
# Common
# --------------------------------------------------------------------------

apply_dotfiles_with_chezmoi() {
  local args=()
  if [[ "${DOTFILES_FORCE:-}" == 1 ]]; then
    args+=(--force)
  fi
  if [[ ! -t 0 ]]; then
    # No terminal to answer "file has changed, overwrite?": fail instead of hang.
    args+=(--no-tty)
  fi

  log "Applying dotfiles with chezmoi source: $REPO_ROOT"
  if ! chezmoi -S "$REPO_ROOT" init --apply ${args[@]+"${args[@]}"}; then
    err "chezmoi could not apply everything. Inspect conflicts with:"
    err "  chezmoi -S '$REPO_ROOT' diff"
    err "then re-run with DOTFILES_FORCE=1 to overwrite the files in \$HOME."
    return 1
  fi
}

install_oh_my_zsh() {
  have git || die "git is required to install Oh My Zsh"
  git_clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" 1

  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  git_clone https://github.com/zsh-users/zsh-autosuggestions.git \
    "$custom/plugins/zsh-autosuggestions" 1
  git_clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$custom/plugins/zsh-syntax-highlighting" 1

  if (( UPGRADE )); then
    log "Updating Oh My Zsh and plugins"
    git_update "$HOME/.oh-my-zsh"
    git_update "$custom/plugins/zsh-autosuggestions"
    git_update "$custom/plugins/zsh-syntax-highlighting"
  fi
}

install_tmux_plugin_manager() {
  if ! have tmux; then
    warn "tmux is not installed; skipping TPM"
    return 0
  fi
  git_clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" 1

  if [[ -f "$HOME/.tmux.conf" && -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    log "Installing tmux plugins from ~/.tmux.conf"
    "$HOME/.tmux/plugins/tpm/bin/install_plugins"
  fi

  if (( UPGRADE )); then
    log "Updating TPM and tmux plugins"
    git_update "$HOME/.tmux/plugins/tpm"
    if [[ -f "$HOME/.tmux.conf" && -x "$HOME/.tmux/plugins/tpm/bin/update_plugins" ]]; then
      "$HOME/.tmux/plugins/tpm/bin/update_plugins" all
    fi
  fi
}

install_gijq_binary() {
  if have gijq && (( ! UPGRADE )); then
    return 0
  fi
  log "Installing gijq release from dgrah50/gijq into ~/.local/bin"
  # The installer is a bash script (it fails under dash, i.e. `| sh` on
  # Debian/Ubuntu) and defaults to /usr/local/bin, where it silently shells out
  # to `sudo` mid-run. ~/.local/bin is user-writable, so no sudo is needed.
  INSTALL_DIR="$HOME/.local/bin" run_remote_script \
    https://raw.githubusercontent.com/dgrah50/gijq/main/scripts/install.sh bash
  have gijq || die "gijq installed but is not on PATH"
}

sync_gijq_repo() {
  mkdir -p "$HOME/src"
  git_clone https://github.com/dgrah50/gijq.git "$HOME/src/gijq"
  if [[ -d "$HOME/src/gijq/.git" ]]; then
    log "Updating ~/src/gijq"
    git_update "$HOME/src/gijq"
  fi
}

current_login_shell() {
  local user="${USER:-$(id -un)}" shell=""
  if [[ "$OS" == Darwin ]]; then
    shell="$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}')" || true
  else
    shell="$(getent passwd "$user" 2>/dev/null | cut -d: -f7)" || true
  fi
  printf '%s\n' "${shell:-${SHELL:-}}"
}

ensure_zsh_default_shell() {
  local zsh_path user="${USER:-$(id -un)}"
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    return 0
  fi
  if [[ "$(current_login_shell)" == "$zsh_path" ]]; then
    return 0
  fi

  log "Login shell is not $zsh_path; switching"
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    log "Adding $zsh_path to /etc/shells"
    printf '%s\n' "$zsh_path" | as_root tee -a /etc/shells >/dev/null
  fi

  if ! have chsh; then
    warn "chsh not found; set your login shell to $zsh_path manually"
    return 1
  fi
  if [[ $EUID -eq 0 ]] || acquire_sudo; then
    # Through root: no second password prompt from chsh/PAM.
    as_root chsh -s "$zsh_path" "$user"
  elif [[ -t 0 ]]; then
    chsh -s "$zsh_path"
  else
    warn "Cannot change the login shell non-interactively. Run: chsh -s $zsh_path"
    return 1
  fi
}

main() {
  if [[ "$OS" == Darwin && $EUID -eq 0 ]]; then
    die "Don't run this as root on macOS (Homebrew refuses to run as root). Run it as your normal user."
  fi
  case "$OS" in
    Darwin | Linux) ;;
    *) die "Unsupported OS: $OS" ;;
  esac

  STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX")"
  ensure_path
  setup_brew_env

  log "Bootstrapping system for dotfiles"
  if (( UPGRADE )); then
    log "DOTFILES_UPGRADE=1: also updating installed tools to their latest versions"
  fi

  if [[ "$OS" == Darwin ]]; then
    run_step optional "Homebrew packages" install_base_packages_macos
    setup_brew_env
  else
    run_step optional "apt packages" install_base_packages_linux
    run_step optional "uv" install_uv
    run_step optional "bun" install_bun
    run_step optional "nvm" install_nvm
    run_step optional "chezmoi" install_chezmoi
  fi

  require_commands git curl chezmoi

  run_step optional "Apply dotfiles (chezmoi)" apply_dotfiles_with_chezmoi
  run_step optional "Oh My Zsh and plugins" install_oh_my_zsh
  if [[ "$OS" == Darwin ]]; then
    run_step optional "fzf shell integration" install_fzf_extras
  fi
  run_step optional "tmux plugin manager" install_tmux_plugin_manager
  run_step optional "gijq binary" install_gijq_binary
  run_step optional "gijq repo" sync_gijq_repo
  run_step optional "zsh as login shell" ensure_zsh_default_shell

  if (( ${#FAILURES[@]} > 0 )); then
    err "Bootstrap finished with ${#FAILURES[@]} problem(s):"
    printf '  - %s\n' "${FAILURES[@]}" >&2
    err "Everything else is done; fix the cause (see warnings above) and re-run, it is safe to repeat."
    exit 1
  fi

  log "Bootstrap complete. Open a new terminal session."
}

main "$@"
