#!/usr/bin/env bash
set -euo pipefail

# ========== Helpers ==========
log() { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\n\033[1;31m[ERR]\033[0m  %s\n" "$*" >&2; }
timestamp() { date +"%Y%m%d-%H%M%S"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    return 1
  fi
}

is_ubuntu() {
  [ -f /etc/os-release ] && grep -qi "ubuntu" /etc/os-release
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSHRC_SOURCE="$REPO_ROOT/vm/zshrc"
ZSHRC_TARGET="$HOME/.zshrc"
NVIM_DIR="$HOME/.config/nvim"
NVIM_REPO="https://github.com/YounesElhjouji/younes-nvim-config.git"

# We prefer brew for modern versions, apt for base/system
BREW_PREFIX_DEFAULT="/home/linuxbrew/.linuxbrew"

# ========== Pre-flight ==========
if ! is_ubuntu; then
  warn "This script targets Ubuntu. Continuing anyway..."
fi

if [ "$EUID" -eq 0 ]; then
  warn "Run this as a regular user; sudo will be used as needed."
fi

log "Updating apt package lists..."
sudo apt-get update -y

# ========== Base packages via apt ==========
log "Installing base packages via apt..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential curl file git ca-certificates \
  unzip xz-utils \
  zsh \
  python3 python3-venv python3-pip python-is-python3 \
  ripgrep fd-find stow

# Provide `fd` name if only `fdfind` exists
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  log "Creating fd -> fdfind symlink in ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  if ! grep -q "$HOME/.local/bin" <<<"$PATH"; then
    warn "~/.local/bin not on PATH for current session; it will be on next login if your shell sources it."
  fi
fi

# ========== Homebrew (Linuxbrew) ==========
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew (Linuxbrew)..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Shellenv for current session
  if [ -x "$BREW_PREFIX_DEFAULT/bin/brew" ]; then
    eval "$("$BREW_PREFIX_DEFAULT/bin/brew" shellenv)"
  elif [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  else
    # Fallback: try to find brew
    if command -v brew >/dev/null 2>&1; then
      eval "$(brew shellenv)"
    fi
  fi

  # Persist shellenv for future login shells (zsh: ~/.zprofile, bash/posix: ~/.profile)
  BREW_ENV_SNIPPET='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'

  ZPROFILE_FILE="$HOME/.zprofile"
  if ! grep -Fq "$BREW_ENV_SNIPPET" "$ZPROFILE_FILE" 2>/dev/null; then
    log "Persisting brew shellenv to $ZPROFILE_FILE"
    {
      echo ""
      echo "# Added by vm/setup.sh for Linuxbrew (zsh login shell)"
      echo "$BREW_ENV_SNIPPET"
    } >>"$ZPROFILE_FILE"
  else
    log "brew shellenv already present in $ZPROFILE_FILE"
  fi

  PROFILE_FILE="$HOME/.profile"
  if ! grep -Fq "$BREW_ENV_SNIPPET" "$PROFILE_FILE" 2>/dev/null; then
    log "Persisting brew shellenv to $PROFILE_FILE"
    {
      echo ""
      echo "# Added by vm/setup.sh for Linuxbrew (POSIX login shell)"
      echo "$BREW_ENV_SNIPPET"
    } >>"$PROFILE_FILE"
  else
    log "brew shellenv already present in $PROFILE_FILE"
  fi
else
  # Ensure available in current process
  eval "$(brew shellenv 2>/dev/null || true)"
fi

require_cmd brew || {
  err "brew not found after installation. Aborting."
  exit 1
}

log "Updating Homebrew..."
brew update

# ========== Developer tools via brew ==========
# ripgrep and git already via apt, but brew ensures newer versions in PATH.
BREW_PKGS=(
  neovim
  fzf
  eza
  zoxide
  lazygit
  bat
  ripgrep
  git
)

log "Installing tools via brew: ${BREW_PKGS[*]}"
brew install "${BREW_PKGS[@]}"

# Install shell-ai
brew tap ibigio/tap
brew install shell-ai

# fzf key bindings and completion (non-interactive)
if [ -x "$(brew --prefix)/opt/fzf/install" ]; then
  log "Enabling fzf key bindings and completion..."
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --xdg
fi

# ========== Oh My Zsh ==========
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  log "Installing Oh My Zsh (non-interactive)..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  log "Oh My Zsh already installed."
fi

# zsh-autosuggestions plugin
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
  log "Installing zsh-autosuggestions plugin..."
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
else
  log "zsh-autosuggestions already present. Updating..."
  git -C "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" pull --ff-only || true
fi

# ========== Symlink zshrc ==========
if [ ! -f "$ZSHRC_SOURCE" ]; then
  err "Expected zshrc at $ZSHRC_SOURCE not found. Aborting."
  exit 1
fi

if [ -e "$ZSHRC_TARGET" ] && { [ ! -L "$ZSHRC_TARGET" ] || [ "$(readlink -f "$ZSHRC_TARGET")" != "$(readlink -f "$ZSHRC_SOURCE")" ]; }; then
  BAK="$HOME/.zshrc.bak-$(timestamp)"
  log "Backing up existing ~/.zshrc to $BAK"
  mv "$ZSHRC_TARGET" "$BAK"
fi

if [ -L "$ZSHRC_TARGET" ] && [ "$(readlink -f "$ZSHRC_TARGET")" = "$(readlink -f "$ZSHRC_SOURCE")" ]; then
  log "~/.zshrc already correctly symlinked."
else
  log "Symlinking $ZSHRC_SOURCE -> $ZSHRC_TARGET"
  ln -sfn "$ZSHRC_SOURCE" "$ZSHRC_TARGET"
fi

# ========== Default shell: zsh ==========
ZSH_PATH="$(command -v zsh)"
if ! grep -qx "$ZSH_PATH" /etc/shells; then
  log "Adding $ZSH_PATH to /etc/shells"
  echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

CURRENT_SHELL="$(getent passwd "$USER" | awk -F: '{print $7}')"
if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
  log "Setting default shell to zsh for $USER (current: $CURRENT_SHELL)"
    # For cloud users with locked passwords, use sudo
    if sudo chsh -s "$ZSH_PATH" "$USER"; then
      log "Default shell set via sudo chsh."
    else
      warn "Failed to set default shell. You can run: sudo chsh -s $ZSH_PATH $USER"
    fi
fi


# ========== Neovim config ==========
mkdir -p "$HOME/.config"

if [ -d "$NVIM_DIR/.git" ]; then
  # Check if it's your repo
  ORIGIN_URL="$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || true)"
  if [ "$ORIGIN_URL" = "$NVIM_REPO" ]; then
    log "Updating existing nvim config..."
    git -C "$NVIM_DIR" pull --ff-only || true
  else
    BAK="$HOME/.config/nvim.bak-$(timestamp)"
    log "Existing ~/.config/nvim differs. Backing up to $BAK"
    mv "$NVIM_DIR" "$BAK"
    log "Cloning your nvim config..."
    git clone "$NVIM_REPO" "$NVIM_DIR"
  fi
elif [ -e "$NVIM_DIR" ]; then
  BAK="$HOME/.config/nvim.bak-$(timestamp)"
  log "Backing up non-git ~/.config/nvim to $BAK"
  mv "$NVIM_DIR" "$BAK"
  log "Cloning your nvim config..."
  git clone "$NVIM_REPO" "$NVIM_DIR"
else
  log "Cloning your nvim config..."
  git clone "$NVIM_REPO" "$NVIM_DIR"
fi

# ========== Preinstall Neovim plugins (Lazy) ==========
if command -v nvim >/dev/null 2>&1; then
  log "Bootstrapping Neovim plugins (Lazy sync)..."
  nvim --headless "+Lazy! sync" +qa || warn "Lazy sync reported issues; open nvim to see details."
else
  warn "nvim not found in PATH after install. Check brew shellenv/paths."
fi

# ========== Cleanup ==========
log "brew cleanup..."
brew cleanup || true

# ========== Summary ==========
log "Setup complete."
echo "- Homebrew installed: $(command -v brew || echo 'not found')"
echo "- zsh path: $ZSH_PATH (default shell set)"
echo "- zshrc symlink: $ZSHRC_SOURCE -> $ZSHRC_TARGET"
echo "- Neovim config: $NVIM_DIR"
echo "- fzf keybindings/completion installed"

# ========== Start zsh ==========
# If already in zsh, exec no-op; otherwise start zsh.
if [ -n "${ZSH_VERSION:-}" ]; then
  log "Already in zsh."
else
  log "Starting zsh..."
  exec "$ZSH_PATH" -l
fi
