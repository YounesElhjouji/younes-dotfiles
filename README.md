# younes-dotfiles

Personal dotfiles and VM bootstrap for a ready-to-go dev environment.

## Quick Start

One-liner to set up a fresh Ubuntu VM:

```bash
git clone https://github.com/YounesElhjouji/younes-dotfiles.git ~/.dotfiles && bash ~/.dotfiles/vm/setup.sh
```

This will:
1. Install base packages and configure zsh (fast, ~1-2 min)
2. Drop you into a working zsh shell immediately
3. Install brew, neovim, and dev tools in the background (~5-10 min)

Run `suit-status` at any time to see what's ready.

## What's Included

- **zsh** with Oh My Zsh, vi mode, and zsh-autosuggestions
- **neovim** with custom config ([younes-nvim-config](https://github.com/YounesElhjouji/younes-nvim-config))
- **CLI tools**: fzf, eza, zoxide, lazygit, bat, ripgrep, fd, shell-ai
- **Homebrew** (Linuxbrew) for package management

## Structure

```
vm/
  setup.sh   # Bootstrap script (Phase 1 foreground + Phase 2 background)
  zshrc      # Zsh configuration (symlinked to ~/.zshrc)
```
