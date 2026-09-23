#!/usr/bin/env bash
# Install Claude Code and wire up the shared status line.
# Idempotent: safe to re-run. Called from vm/setup.sh and mac-setup.sh, or run directly.
set -euo pipefail

log()  { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE_SRC="$SCRIPT_DIR/statusline.sh"
STATUSLINE_DST="$CLAUDE_DIR/statusline.sh"

# ---- Claude Code (native installer, lands in ~/.local/bin) -------------------
if command -v claude >/dev/null 2>&1; then
  log "Claude Code already installed: $(claude --version 2>/dev/null || echo '?')"
else
  log "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
fi

# ---- jq is required by the status line script --------------------------------
if ! command -v jq >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing jq via apt..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jq
  elif command -v brew >/dev/null 2>&1; then
    log "Installing jq via brew..."
    brew install jq
  else
    warn "jq not found and no package manager available; the status line needs it."
  fi
fi

# ---- status line script: symlink so repo updates propagate -------------------
mkdir -p "$CLAUDE_DIR"
if [ -e "$STATUSLINE_DST" ] && [ ! -L "$STATUSLINE_DST" ]; then
  BAK="$STATUSLINE_DST.bak-$(date +%Y%m%d-%H%M%S)"
  log "Backing up existing status line script to $BAK"
  mv "$STATUSLINE_DST" "$BAK"
fi
ln -sfn "$STATUSLINE_SRC" "$STATUSLINE_DST"
log "Status line: $STATUSLINE_DST -> $STATUSLINE_SRC"

# ---- settings.json: merge the statusLine block, keep everything else ---------
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
if command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp)"
  jq --arg cmd "$STATUSLINE_DST" \
     '.statusLine = {type: "command", command: $cmd, padding: 1, hideVimModeIndicator: true}' \
     "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
  log "Wrote statusLine block to $SETTINGS"
else
  warn "jq missing; add this to $SETTINGS by hand:"
  printf '  "statusLine": {"type": "command", "command": "%s", "padding": 1, "hideVimModeIndicator": true}\n' "$STATUSLINE_DST"
fi
