# younes-dotfiles

Public personal dotfiles and VM bootstrap for a ready-to-go dev environment.

This repository is intentionally safe to publish. It should contain only generic
personal environment configuration: shell ergonomics, editor/tmux setup, bootstrap
scripts, and public helper scripts.

Company-specific or operational tooling belongs in a separate private overlay
repository, conventionally checked out at `~/.ovs-dotfiles`.

## Quick Start

One-liner to set up a fresh Ubuntu VM:

```bash
curl -fsSL https://vm.elhjouji.com | bash
```

Equivalent manual form:

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

## Public vs OVS Overlay

Keep this repo public and generic. Do not add company-specific tooling or
operational metadata here, even when it does not contain passwords.

Examples that belong in the private `.ovs-dotfiles` overlay:

- names, paths, aliases, shortcuts, IDs, or conventions for professional systems
- helpers related to professional workflows or organization-specific tooling
- internal endpoints, object paths, service names, labels, or operational metadata
- CLI tools intended to be shared only inside the organization

Actual credentials should not be committed to either repo. Keep tokens, private
keys, passwords, API keys, and similar sensitive values in local secret stores
such as `~/.secrets`, a password manager, or provider-specific auth.

The public `zshrc` optionally loads an overlay from:

```zsh
${OVS_DOTFILES_DIR:-$HOME/.ovs-dotfiles}
```

Suggested private overlay layout:

```text
.ovs-dotfiles/
  zsh/
    00-path.zsh
    10-infra.zsh
    20-cloud.zsh
    30-aliases.zsh
  bin/
    ovs-helper
```

## Structure

```
AGENTS.md  # Instructions for coding agents working in this public repo
vm/
  setup.sh   # Bootstrap script (Phase 1 foreground + Phase 2 background)
  zshrc      # Zsh configuration (symlinked to ~/.zshrc)
```
