typeset -U path PATH

path=(
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/homebrew/bin"
  /usr/local/bin
  $path
)

[[ -d "$HOME/.codeium/windsurf/bin" ]] && path+=("$HOME/.codeium/windsurf/bin")
[[ -d "$HOME/.antigravity/antigravity/bin" ]] && path+=("$HOME/.antigravity/antigravity/bin")

export PNPM_HOME="$HOME/Library/pnpm"
[[ -d "$PNPM_HOME" ]] && path=("$PNPM_HOME" $path)

export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && path=("$BUN_INSTALL/bin" $path)
[[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"

export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

export DOTNET_ROOT="$HOME/.dotnet"
[[ -d "$DOTNET_ROOT" ]] && path=("$DOTNET_ROOT" $path)
