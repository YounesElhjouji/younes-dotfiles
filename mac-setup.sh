#!/usr/bin/env bash
set -euo pipefail

# ========== Helpers ==========
log()  { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\n\033[1;31m[ERR]\033[0m  %s\n" "$*" >&2; }
timestamp() { date +"%Y%m%d-%H%M%S"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

ZSHRC_SOURCE="$REPO_ROOT/zshrc"
ZSHRC_TARGET="$HOME/.zshrc"
TMUX_SOURCE="$REPO_ROOT/tmux.conf"
TMUX_TARGET="$HOME/.config/tmux/tmux.conf"
GHOSTTY_SOURCE="$REPO_ROOT/ghostty.conf"
GHOSTTY_TARGET="$HOME/.config/ghostty/config"
NVIM_DIR="$HOME/.config/nvim"
NVIM_REPO="https://github.com/YounesElhjouji/younes-nvim-config.git"

# ========== Pre-flight ==========
if [[ "$(uname)" != "Darwin" ]]; then
  err "This script is for macOS only."
  exit 1
fi

# ==========================================================
#  PHASE 1 — Homebrew + shell basics (foreground)
# ==========================================================

log "=== Phase 1: Setting up base environment ==="

# ========== Xcode Command Line Tools ==========
if ! xcode-select -p &>/dev/null; then
  log "Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Press Enter after Xcode CLT installation completes..."
  read -r
else
  log "Xcode Command Line Tools already installed."
fi

# ========== Homebrew ==========
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for this session (Apple Silicon vs Intel)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  log "Homebrew already installed."
fi

# Persist brew shellenv in .zprofile if not already there
BREW_BIN="$(brew --prefix)/bin/brew"
BREW_ENV_SNIPPET="eval \"\$(${BREW_BIN} shellenv)\""
if ! grep -Fq "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
  log "Adding brew shellenv to ~/.zprofile"
  printf '\n# Homebrew\n%s\n' "$BREW_ENV_SNIPPET" >> "$HOME/.zprofile"
fi

log "Updating Homebrew..."
brew update

# ========== All packages via brew ==========
BREW_PKGS=(
  git zsh tmux
  neovim fzf eza zoxide lazygit
  bat ripgrep fd
  python3 pnpm kubectl aichat
)

log "Installing packages via brew: ${BREW_PKGS[*]}"
brew install "${BREW_PKGS[@]}"

# shell-ai
if ! command -v shell-ai &>/dev/null; then
  log "Installing shell-ai..."
  brew tap ibigio/tap && brew install shell-ai || warn "shell-ai install failed, skipping."
fi

# fzf key bindings and completion
if [ -x "$(brew --prefix)/opt/fzf/install" ]; then
  log "Enabling fzf key bindings and completion..."
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --xdg
fi

# ========== TPM (tmux plugin manager) ==========
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  log "Installing TPM (tmux plugin manager)..."
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
  log "TPM already installed."
fi

# ========== Oh My Zsh ==========
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  log "Installing Oh My Zsh..."
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
  log "zsh-autosuggestions already present."
fi

# fzf-tab plugin
if [ ! -d "$ZSH_CUSTOM_DIR/plugins/fzf-tab" ]; then
  log "Installing fzf-tab plugin..."
  git clone https://github.com/Aloxaf/fzf-tab "$ZSH_CUSTOM_DIR/plugins/fzf-tab"
else
  log "fzf-tab already present."
fi

# ========== Symlink zshrc ==========
symlink_config() {
  local src="$1" dst="$2" label="$3"

  if [ ! -f "$src" ]; then
    warn "Expected $label at $src not found. Skipping."
    return
  fi

  mkdir -p "$(dirname "$dst")"

  if [ -e "$dst" ] && { [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$src" ]; }; then
    local bak="${dst}.bak-$(timestamp)"
    log "Backing up existing $label to $bak"
    mv "$dst" "$bak"
  fi

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    log "$label already correctly symlinked."
  else
    log "Symlinking $src -> $dst"
    ln -sfn "$src" "$dst"
  fi
}

symlink_config "$ZSHRC_SOURCE"   "$ZSHRC_TARGET"   "zshrc"
symlink_config "$TMUX_SOURCE"    "$TMUX_TARGET"     "tmux.conf"
symlink_config "$GHOSTTY_SOURCE" "$GHOSTTY_TARGET"  "ghostty config"

# ========== Create empty k8s-helpers if missing ==========
# zshrc sources this; create a stub so zsh doesn't error
if [ ! -f "$HOME/.k8s-helpers.zsh" ]; then
  log "Creating empty ~/.k8s-helpers.zsh stub"
  touch "$HOME/.k8s-helpers.zsh"
fi

# ========== Default shell: zsh ==========
ZSH_PATH="$(command -v zsh)"
CURRENT_SHELL="$(dscl . -read /Users/"$USER" UserShell | awk '{print $2}')"
if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
  log "Setting default shell to zsh..."
  chsh -s "$ZSH_PATH"
else
  log "Default shell is already zsh."
fi

log "=== Phase 1 complete! ==="

# ==========================================================
#  PHASE 2 — Dev tools (background)
# ==========================================================

SUIT_LOG="$HOME/.mac-suit-up.log"

phase2() {
  set -euo pipefail

  log()  { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
  warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }

  NVIM_DIR="$HOME/.config/nvim"
  NVIM_REPO="https://github.com/YounesElhjouji/younes-nvim-config.git"

  echo "========================================"
  echo " Phase 2 started at $(date)"
  echo "========================================"

  # ========== Dev tools via brew ==========
  BREW_PKGS=(
    neovim
    fzf
    eza
    zoxide
    lazygit
    bat
    ripgrep
    fd
    python3
    pnpm
    kubectl
    aichat
  )

  log "Installing tools via brew: ${BREW_PKGS[*]}"
  brew install "${BREW_PKGS[@]}" || true

  # shell-ai
  if ! command -v shell-ai &>/dev/null; then
    log "Installing shell-ai..."
    brew tap ibigio/tap && brew install shell-ai || warn "shell-ai install failed, skipping."
  fi

  # fzf key bindings and completion
  if [ -x "$(brew --prefix)/opt/fzf/install" ]; then
    log "Enabling fzf key bindings and completion..."
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --xdg
  fi

  # ========== TPM (tmux plugin manager) ==========
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    log "Installing TPM (tmux plugin manager)..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  else
    log "TPM already installed."
  fi

  # ========== Neovim config ==========
  mkdir -p "$HOME/.config"

  if [ -d "$NVIM_DIR/.git" ]; then
    ORIGIN_URL="$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || true)"
    if [ "$ORIGIN_URL" = "$NVIM_REPO" ]; then
      log "Updating existing nvim config..."
      git -C "$NVIM_DIR" pull --ff-only || true
    else
      BAK="$HOME/.config/nvim.bak-$(date +%Y%m%d-%H%M%S)"
      log "Backing up existing nvim config to $BAK"
      mv "$NVIM_DIR" "$BAK"
      git clone "$NVIM_REPO" "$NVIM_DIR"
    fi
  elif [ -e "$NVIM_DIR" ]; then
    BAK="$HOME/.config/nvim.bak-$(date +%Y%m%d-%H%M%S)"
    log "Backing up non-git nvim config to $BAK"
    mv "$NVIM_DIR" "$BAK"
    git clone "$NVIM_REPO" "$NVIM_DIR"
  else
    log "Cloning nvim config..."
    git clone "$NVIM_REPO" "$NVIM_DIR"
  fi

  # Lazy sync
  if command -v nvim &>/dev/null; then
    log "Bootstrapping Neovim plugins (Lazy sync)..."
    nvim --headless "+Lazy! sync" +qa || warn "Lazy sync reported issues; open nvim to see details."
  fi

  # ========== Cleanup ==========
  log "brew cleanup..."
  brew cleanup || true

  echo ""
  echo "========================================"
  echo " Phase 2 complete at $(date)"
  echo "========================================"
}

log "Launching Phase 2 (dev tools, neovim, TPM) in background..."
log "Progress is logged to $SUIT_LOG"
phase2 >> "$SUIT_LOG" 2>&1 &
PHASE2_PID=$!
echo "$PHASE2_PID" > "$HOME/.mac-suit-up.pid"

echo ""
echo "============================================"
echo "  Your Mac shell is ready!"
echo ""
echo "  Phase 2 is installing dev tools in the"
echo "  background (neovim, fzf, lazygit, etc.)"
echo ""
echo "  Check progress:  tail -f $SUIT_LOG"
echo "  Full log:        $SUIT_LOG"
echo ""
echo "  After Phase 2 finishes:"
echo "    - Open tmux and press prefix + I to"
echo "      install tmux plugins via TPM"
echo "    - Install Ghostty: https://ghostty.org"
echo "    - Install Docker Desktop manually"
echo "============================================"
echo ""
