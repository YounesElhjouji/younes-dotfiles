# ===== OH-MY-ZSH CONFIGURATION =====
export ZSH="$HOME/.oh-my-zsh"
# ZSH_THEME="robbyrussell"

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
eval "$(zoxide init zsh)"

# ===== PATH AND ENVIRONMENT VARIABLES =====

# PNPM setup
export PNPM_HOME="/Users/youneselhjouji/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Personal variables
export zrc="$HOME/younes-dotfiles/zshrc"

# IMPORTANT: Store sensitive keys in a separate file that's not in version control
if [ -f "$HOME/.secrets" ]; then
  source "$HOME/.secrets"
fi

# ===== ALIASES =====

# AIChat
alias aic='aichat -c '
alias ait='aichat "Suggest the best devtool(s) to achieve the following task. If multiple options exist, list them from best to least good with a one-sentence description for each: " '
alias ain='aichat "Give me the Neovim keybindings or commands to: " '

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias cd='z'

# Python
alias avenv='source venv/bin/activate'
alias pin='pip install'
alias venv='python -m venv venv && source venv/bin/activate'

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
    tmux new-window -t "$session_name" -n "git" "lazygit; exec zsh"
    tmux select-window -t "$session_name:1"
  fi
  tmux attach-session -t "$session_name"
}

# Kill all local procceses
alias k='~/younes-dotfiles/kill_locals.sh'
alias edit_s3='~/younes-dotfiles/edit_s3.sh'

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

# Set nvim as defautl editor
export EDITOR="nvim"
export VISUAL="nvim"

# Custom TAB completion with auto suggest default and fzf fallback
bindkey '^y' autosuggest-accept

# Rebind keys to navigate command history
bindkey '^k' up-history
bindkey '^j' down-history


# The next line updates PATH for Nebius CLI.
if [ -f '/Users/youneselhjouji/.nebius/path.zsh.inc' ]; then
  source '/Users/youneselhjouji/.nebius/path.zsh.inc'
fi

