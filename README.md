# Dotfiles (chezmoi source)

This repository uses [chezmoi](https://www.chezmoi.io/) source naming:

- `dot_*` -> `~/.<name>`
- `executable_*` -> `~/<name>` with executable bit

## Audit (March 1, 2026)

Findings:

- This repo is in chezmoi format.
- Your active chezmoi source directory is currently `/Users/dayangraham/.local/share/chezmoi`.
- This repo was not your active source directory at audit time.
- Drift was found and synced from your home directory:
  - `dot_zshrc`
- Repo housekeeping was added:
  - `.chezmoiignore` to keep repo assets out of `$HOME`
  - `Brewfile` for package management
  - modular zsh config under `dot_config/zsh/`
  - `dot_gitconfig` + `dot_gitignore_global`
  - `private_dot_ssh/private_config` scaffold
  - `run_once_after_10-post-setup.sh.tmpl` for post-apply setup

## Use This Repo As Source

Preview differences between source and home:

```bash
chezmoi -S /Users/dayangraham/Projects/dotfiles diff
```

Apply this repo to your home directory:

```bash
chezmoi -S /Users/dayangraham/Projects/dotfiles apply
```

Add/update files from home into this repo:

```bash
chezmoi -S /Users/dayangraham/Projects/dotfiles add ~/.zshrc ~/.bashrc ~/.tmux.conf ~/better-commit.sh
```

## New Machine Bootstrap

Run the bootstrap script from this repo:

```bash
cd /Users/dayangraham/Projects/dotfiles
chmod +x ./install.sh
./install.sh
```

What it does:

- Installs required tooling (`zsh`, `git`, `gh`, `jq`, `fzf`, `tmux`, `ripgrep`, `bat`, `zoxide`, `go`, `rust`, `chezmoi`) with Homebrew on macOS.
- Uses `Brewfile` on macOS when present (`brew bundle --file ./Brewfile`).
- Applies dotfiles from this repo via `chezmoi -S <repo> init --apply`.
- Installs Oh My Zsh and zsh plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`).
- Installs tmux plugin manager (TPM) and tmux plugins.
- Installs `gijq` from `github.com/dgrah50/gijq` and clones the repo to `~/src/gijq`.

## Config Layout

Zsh is split into:

- `dot_zshrc` (loader only)
- `dot_config/zsh/path.zsh`
- `dot_config/zsh/omz.zsh`
- `dot_config/zsh/options.zsh`
- `dot_config/zsh/functions.zsh`
- `dot_config/zsh/aliases.zsh`

Git config files:

- `dot_gitconfig`
- `dot_gitignore_global`

Tracked `~/.config` apps:

- `dot_config/alacritty/alacritty.toml`
- `dot_config/gh/config.yml` (safe settings only; auth token file is not tracked)
- `dot_config/git/ignore`

## Secrets Notes

Keep secrets out of git. Set API tokens and machine-specific variables in a
local-only file (for example `~/.zshrc.local`) that is not tracked by chezmoi.

A starter file is included as `dot_zshrc.local.example`.

## Optional: Make This Repo Your Default chezmoi Source

If you want `chezmoi` without `-S` to use this repo, re-init with this local path:

```bash
chezmoi init --source=/Users/dayangraham/Projects/dotfiles
```

Then verify:

```bash
chezmoi source-path
```
