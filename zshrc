export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# Docker Desktop completions: must be set BEFORE oh-my-zsh initializes completion
fpath=(/Users/youneselhjouji/.docker/completions $fpath)

# Enhanced plugin list
plugins=(
  zsh-autosuggestions     # Requires installation
  docker
  docker-compose
  fzf
  fzf-tab
)

source $ZSH/oh-my-zsh.sh

# ===== HISTORY SETTINGS =====
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS

# ===== VI MODE with Cursor Shape =====
bindkey -v

# Use jk to enter normal mode from insert mode
bindkey -M viins 'jk' vi-cmd-mode

# Reduce ESC delay
export KEYTIMEOUT=20

# Function to update the cursor style based on current keymap.
update_cursor() {
  if [[ $KEYMAP == vicmd ]]; then
    print -Pn "\e[2 q"
  else
    print -Pn "\e[4 q"
  fi
}

# Call update_cursor when the ZLE line is initialized
function zle-line-init() {
  update_cursor
}

# And whenever the keymap is switched
function zle-keymap-select() {
  update_cursor
}

# Bind the widgets
zle -N zle-line-init
zle -N zle-keymap-select

# ===== TOOL CONFIGURATION =====

# fzf-tab minimal config
zstyle ':fzf-tab:*' switch-group ',' '.'

# Zoxide (modern alternative to cd)
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# ===== PATH AND ENVIRONMENT VARIABLES =====

# PNPM setup
export PNPM_HOME="/Users/youneselhjouji/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Personal variables
export nvc="/Users/youneselhjouji/.config/nvim"
export zrc="$HOME/younes-dotfiles/zshrc"

# IMPORTANT: Store sensitive keys in a separate file that's not in version control
if [ -f "$HOME/.secrets" ]; then
  source "$HOME/.secrets"
fi

# ===== ALIASES =====
# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
if command -v zoxide &>/dev/null; then
  alias cd='z'
fi

# Python
alias avenv='source venv/bin/activate'
alias pin='pip install'
alias venv='python3 -m venv venv && source venv/bin/activate'

# Neovim
alias n='nvim'
h() {
  nvim ~/help/"$1"
}

# Eza
alias lss='eza --long --no-user --no-time --git --no-permissions --no-filesize --icons --group-directories-first '
alias treee='eza --tree'

# Tmux
alias tn='tmux new-session -A -s "$(basename "$PWD")"'
ts() {
  tmux list-sessions | fzf | cut -d: -f1 | xargs tmux switch-client -t
}
alias t='tmux a'
function dev() {
  local session_name
  session_name=$(basename "$PWD")
  tmux has-session -t "$session_name" 2>/dev/null
  if [ $? != 0 ]; then
    tmux new-session -d -s "$session_name" -n "editor" "nvim .; exec zsh"
    tmux new-window -t "$session_name" "exec zsh"
    tmux select-window -t "$session_name:editor"
  fi
  tmux attach-session -t "$session_name"
}

autoload -Uz add-zsh-hook
_tmux_ssh_target() {
  local -a args
  args=("$@")

  local i token
  for (( i = 1; i <= ${#args}; i++ )); do
    token="${args[$i]}"

    if [[ "$token" == "--" ]]; then
      (( i++ ))
      break
    fi

    if [[ "$token" != -* ]]; then
      print -r -- "${token##*@}"
      return
    fi

    case "$token" in
      -b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-p|-Q|-R|-S|-W|-w)
        (( i++ ))
        ;;
      -[bcDEeFIiJLlmOoQpRSWw]?*)
        ;;
    esac
  done

  if (( i <= ${#args} )); then
    print -r -- "${args[$i]##*@}"
  fi
}

_tmux_rename_window_temporarily() {
  [[ -n "${TMUX:-}" && -n "$1" ]] || return

  if [[ -z "${_TMUX_TEMP_WINDOW_ID:-}" ]]; then
    typeset -g _TMUX_TEMP_WINDOW_ID
    typeset -g _TMUX_TEMP_WINDOW_NAME
    typeset -g _TMUX_TEMP_AUTOMATIC_RENAME

    _TMUX_TEMP_WINDOW_ID="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
    _TMUX_TEMP_WINDOW_NAME="$(tmux display-message -p '#W' 2>/dev/null)"
    _TMUX_TEMP_AUTOMATIC_RENAME="$(tmux show-options -wqv automatic-rename 2>/dev/null)"
  fi

  tmux rename-window "$1" 2>/dev/null
}

_tmux_restore_window_name() {
  [[ -n "${TMUX:-}" && -n "${_TMUX_TEMP_WINDOW_ID:-}" ]] || return

  local current_window_id
  current_window_id="$(tmux display-message -p '#{window_id}' 2>/dev/null)"

  if [[ "$current_window_id" == "$_TMUX_TEMP_WINDOW_ID" ]]; then
    if [[ -n "${_TMUX_TEMP_WINDOW_NAME:-}" ]]; then
      tmux rename-window "$_TMUX_TEMP_WINDOW_NAME" 2>/dev/null
    fi

    case "${_TMUX_TEMP_AUTOMATIC_RENAME:-}" in
      on|off)
        tmux set-option -w automatic-rename "$_TMUX_TEMP_AUTOMATIC_RENAME" 2>/dev/null
        ;;
    esac
  fi

  unset _TMUX_TEMP_WINDOW_ID
  unset _TMUX_TEMP_WINDOW_NAME
  unset _TMUX_TEMP_AUTOMATIC_RENAME
}

_tmux_name_agent_window() {
  [[ -n "${TMUX:-}" ]] || return

  local -a words
  words=("${(z)1}")

  local i word next_word
  for (( i = 1; i <= ${#words}; i++ )); do
    word="${words[$i]}"
    next_word="${words[$((i + 1))]:-}"

    case "$word" in
      command|exec|env|noglob|time|*=*)
        continue
        ;;
      claude|*/claude)
        _tmux_rename_window_temporarily claude
        return
        ;;
      codex|*/codex)
        _tmux_rename_window_temporarily codex
        return
        ;;
      nvim|*/nvim)
        _tmux_rename_window_temporarily editor
        return
        ;;
      npm|*/npm)
        if [[ "$next_word" == "run" ]]; then
          _tmux_rename_window_temporarily npm
        fi
        return
        ;;
      ssh|*/ssh)
        local target
        target="$(_tmux_ssh_target "${words[@]:$i}")"
        if [[ -n "$target" ]]; then
          _tmux_rename_window_temporarily "$target"
        fi
        return
        ;;
      *)
        return
        ;;
    esac
  done
}
add-zsh-hook -d precmd _tmux_restore_window_name 2>/dev/null
add-zsh-hook -d preexec _tmux_name_agent_window 2>/dev/null
add-zsh-hook precmd _tmux_restore_window_name
add-zsh-hook preexec _tmux_name_agent_window

# Misc
alias lg='lazygit'
editrc() {
  nvim "$zrc" && source "$zrc"
}

# ===== FUNCTIONS =====

# Create and activate Python virtual environment
function venv() {
  python -m venv venv && source venv/bin/activate
}

# Function to create a new directory and cd into it
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Optional private/org overlay. Keep overshoot-specific helpers out of this public repo.
OVS_DOTFILES_DIR="${OVS_DOTFILES_DIR:-$HOME/.ovs-dotfiles}"
if [ -d "$OVS_DOTFILES_DIR/bin" ]; then
  export PATH="$OVS_DOTFILES_DIR/bin:$PATH"
fi
if [ -d "$OVS_DOTFILES_DIR/zsh" ]; then
  for ovs_file in "$OVS_DOTFILES_DIR"/zsh/*.zsh(N); do
    source "$ovs_file"
  done
  unset ovs_file
fi

# Set nvim as defautl editor
export EDITOR="nvim"
export VISUAL="nvim"

# Custom TAB completion with auto suggest default and fzf fallback
bindkey '^y' autosuggest-accept

# Rebind keys to navigate command history
bindkey '^k' up-history
bindkey '^j' down-history

export PATH="$HOME/.local/bin:$PATH"

# The next line updates PATH for Nebius CLI.
if [ -f '/Users/youneselhjouji/.nebius/path.zsh.inc' ]; then source '/Users/youneselhjouji/.nebius/path.zsh.inc'; fi

# opencode
export PATH=/Users/youneselhjouji/.opencode/bin:$PATH
