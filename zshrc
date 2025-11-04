# ===== OH-MY-ZSH CONFIGURATION =====
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"


# Enhanced plugin list
plugins=(
  git
  zsh-autosuggestions     # Requires installation
  zsh-syntax-highlighting # Requires installation
  docker
  docker-compose
  fzf
  npm
  node
  python
  pip
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
# Note: These escape sequences (DECSCUSR) are supported in many modern terminal emulators
# (e.g., iTerm2, recent xterm, etc.) but may not work in every terminal.
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

# FZF setup
eval "$(fzf --zsh)"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
export FZF_CTRL_T_OPTS="--preview 'cat {}'"
export FZF_ALT_C_OPTS="--preview 'ls -la {}'"


# Zoxide (modern alternative to cd)
eval "$(zoxide init zsh)"

# ===== PATH AND ENVIRONMENT VARIABLES =====

# Conda setup
# >>> conda initialize >>>
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# PNPM setup
export PNPM_HOME="/Users/youneselhjouji/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Android SDK setup
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin

# Personal variables
export nvc="/Users/youneselhjouji/.config/nvim"
export zrc="$HOME/younes-dotfiles/zshrc"

# IMPORTANT: Store sensitive keys in a separate file that's not in version control
# Create a file like ~/.secrets and source it here
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

# PM2
alias plog='pm2 logs --raw'
alias pls='pm2 ls'
alias pstall='pm2 stop all'


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

# Function to extract various archive formats
function extract() {
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1     ;;
      *.tar.gz)    tar xzf $1     ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       unrar e $1     ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar xf $1      ;;
      *.tbz2)      tar xjf $1     ;;
      *.tgz)       tar xzf $1     ;;
      *.zip)       unzip $1       ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}


# Minimal syntax highlighting - only highlight errors and comments
ZSH_HIGHLIGHT_STYLES[default]='none'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=131'  # Muted brick red for unknown commands
ZSH_HIGHLIGHT_STYLES[command]='none'          # No highlighting for valid commands
ZSH_HIGHLIGHT_STYLES[alias]='none'            # No highlighting for aliases
ZSH_HIGHLIGHT_STYLES[builtin]='none'          # No highlighting for builtins
ZSH_HIGHLIGHT_STYLES[function]='none'         # No highlighting for functions
ZSH_HIGHLIGHT_STYLES[precommand]='none'       # No highlighting for precommands
ZSH_HIGHLIGHT_STYLES[commandseparator]='none' # No highlighting for command separators
ZSH_HIGHLIGHT_STYLES[hashed-command]='none'   # No highlighting for hashed commands
ZSH_HIGHLIGHT_STYLES[path]='none'             # No highlighting for paths
ZSH_HIGHLIGHT_STYLES[globbing]='none'         # No highlighting for glob patterns
ZSH_HIGHLIGHT_STYLES[history-expansion]='none' # No highlighting for history expansion
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='none' # No highlighting for short options
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='none' # No highlighting for long options
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='none' # No highlighting for backticks
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='none' # No highlighting for single quotes
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='none' # No highlighting for double quotes
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='none' # No highlighting for dollar quotes
ZSH_HIGHLIGHT_STYLES[comment]='fg=245'        # Light gray for comments


# Set nvim as defautl editor
export EDITOR="nvim"
export VISUAL="nvim" 

# Custom TAB completion with auto suggest default and fzf fallback 
bindkey '^y' autosuggest-accept 

# Rebind keys to navigate command history
bindkey '^k' up-history
bindkey '^j' down-history

alias shadcn="npx shadcn@latest add"
# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/youneselhjouji/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions

# The next line updates PATH for Nebius CLI.
if [ -f '/Users/youneselhjouji/.nebius/path.zsh.inc' ]; then source '/Users/youneselhjouji/.nebius/path.zsh.inc'; fi

