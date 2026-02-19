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
SUIT_LOG="$HOME/.suit-up.log"

BREW_PREFIX_DEFAULT="/home/linuxbrew/.linuxbrew"

# ========== Pre-flight ==========
if ! is_ubuntu; then
  warn "This script targets Ubuntu. Continuing anyway..."
fi

if [ "$EUID" -eq 0 ]; then
  warn "Run this as a regular user; sudo will be used as needed."
fi

# ==========================================================
#  PHASE 1 — Foreground (fast)
#  Everything needed for a usable zsh session
# ==========================================================

log "=== Phase 1: Setting up base environment ==="

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
  if sudo chsh -s "$ZSH_PATH" "$USER"; then
    log "Default shell set via sudo chsh."
  else
    warn "Failed to set default shell. You can run: sudo chsh -s $ZSH_PATH $USER"
  fi
fi

log "=== Phase 1 complete! Zsh is ready. ==="

# ==========================================================
#  PHASE 2 — Background (slow)
#  Brew, dev tools, neovim config — runs asynchronously
# ==========================================================

phase2() {
  set -euo pipefail

  log() { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
  warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
  err() { printf "\n\033[1;31m[ERR]\033[0m  %s\n" "$*" >&2; }
  timestamp() { date +"%Y%m%d-%H%M%S"; }

  BREW_PREFIX_DEFAULT="/home/linuxbrew/.linuxbrew"
  NVIM_DIR="$HOME/.config/nvim"
  NVIM_REPO="https://github.com/YounesElhjouji/younes-nvim-config.git"

  echo "========================================"
  echo " Phase 2 started at $(date)"
  echo "========================================"

  # ========== Homebrew (Linuxbrew) ==========
  if ! command -v brew >/dev/null 2>&1; then
    log "Installing Homebrew (Linuxbrew)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -x "$BREW_PREFIX_DEFAULT/bin/brew" ]; then
      eval "$("$BREW_PREFIX_DEFAULT/bin/brew" shellenv)"
    fi

    # Persist shellenv for future shells
    BREW_ENV_SNIPPET='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'

    for rc_file in "$HOME/.zprofile" "$HOME/.profile"; do
      if ! grep -Fq "$BREW_ENV_SNIPPET" "$rc_file" 2>/dev/null; then
        log "Persisting brew shellenv to $rc_file"
        printf '\n# Added by vm/setup.sh for Linuxbrew\n%s\n' "$BREW_ENV_SNIPPET" >> "$rc_file"
      fi
    done
  else
    eval "$(brew shellenv 2>/dev/null || true)"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    err "brew not found after installation. Aborting phase 2."
    exit 1
  fi

  log "Updating Homebrew..."
  brew update

  # ========== Dev tools via brew ==========
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

  # shell-ai
  brew tap ibigio/tap
  brew install shell-ai

  # fzf key bindings and completion
  if [ -x "$(brew --prefix)/opt/fzf/install" ]; then
    log "Enabling fzf key bindings and completion..."
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --xdg
  fi

  # ========== Neovim config ==========
  mkdir -p "$HOME/.config"

  if [ -d "$NVIM_DIR/.git" ]; then
    ORIGIN_URL="$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || true)"
    if [ "$ORIGIN_URL" = "$NVIM_REPO" ]; then
      log "Updating existing nvim config..."
      git -C "$NVIM_DIR" pull --ff-only || true
    else
      BAK="$HOME/.config/nvim.bak-$(timestamp)"
      log "Backing up existing nvim config to $BAK"
      mv "$NVIM_DIR" "$BAK"
      git clone "$NVIM_REPO" "$NVIM_DIR"
    fi
  elif [ -e "$NVIM_DIR" ]; then
    BAK="$HOME/.config/nvim.bak-$(timestamp)"
    log "Backing up non-git nvim config to $BAK"
    mv "$NVIM_DIR" "$BAK"
    git clone "$NVIM_REPO" "$NVIM_DIR"
  else
    log "Cloning nvim config..."
    git clone "$NVIM_REPO" "$NVIM_DIR"
  fi

  # Lazy sync
  if command -v nvim >/dev/null 2>&1; then
    log "Bootstrapping Neovim plugins (Lazy sync)..."
    nvim --headless "+Lazy! sync" +qa || warn "Lazy sync reported issues; open nvim to see details."
  else
    warn "nvim not found in PATH after install."
  fi

  # ========== Cleanup ==========
  log "brew cleanup..."
  brew cleanup || true

  echo ""
  echo "========================================"
  echo " Phase 2 complete at $(date)"
  echo "========================================"
}

log "Launching Phase 2 (brew, neovim, dev tools) in background..."
log "Progress is logged to $SUIT_LOG"
phase2 >> "$SUIT_LOG" 2>&1 &
PHASE2_PID=$!
echo "$PHASE2_PID" > "$HOME/.suit-up.pid"

echo ""
echo "============================================"
echo "  Your shell is ready!"
echo ""
echo "  Phase 2 is installing dev tools in the"
echo "  background (brew, neovim, fzf, etc.)"
echo ""
echo "  Run 'suit-status' to check progress."
echo "  Full log: $SUIT_LOG"
echo "============================================"
echo ""

# ========== Drop into zsh ==========
if [ -n "${ZSH_VERSION:-}" ]; then
  log "Already in zsh."
else
  log "Starting zsh..."
  exec "$ZSH_PATH" -l
fi
