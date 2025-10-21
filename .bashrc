# Exit if non-interactive
case $- in *i*) ;; *) return ;; esac

# Early path/env
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export EDITOR="nvim"
export VISUAL="nvim"
[ -f "$HOME/.secrets" ] && . "$HOME/.secrets"

# Shell options
shopt -s histappend
shopt -s cmdhist
shopt -s checkwinsize
shopt -s extglob
shopt -s globstar 2>/dev/null || true

# History
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoredups:erasedups
export HISTIGNORE="ls:bg:fg:history:clear"
export HISTTIMEFORMAT="%F %T "
PROMPT_COMMAND='history -a; history -c; history -r; '"$PROMPT_COMMAND"

# Vi mode and cursor shaping (best effort)
set -o vi
__bash_cursor_ins() { printf "\e[4 q"; }
__bash_cursor_vi()  { printf "\e[2 q"; }
PROMPT_COMMAND='__bash_cursor_ins; '"$PROMPT_COMMAND"

# Debian chroot name if any
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# Colors and prompt
__git_branch() {
  git rev-parse --is-inside-work-tree &>/dev/null || return
  local b
  b=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  [ -n "$b" ] && printf " (%s)" "$b"
}
__c_reset='\[\e[0m\]'
__c_green='\[\e[32m\]'
__c_blue='\[\e[34m\]'
__c_gray='\[\e[90m\]'
PS1="${debian_chroot:+($debian_chroot)}${__c_blue}\u@\h${__c_reset} ${__c_green}\w${__c_reset}${__c_gray}\$(__git_branch)${__c_reset} \$ "

# Terminal title for xterm/rxvt
case "$TERM" in
  xterm*|rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1" ;;
esac

# Less and dircolors
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if command -v dircolors >/dev/null 2>&1; then
  [ -r ~/.dircolors ] && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

# Colors and ls/grep defaults (with fallback)
export CLICOLOR=1
alias ls='ls --color=auto 2>/dev/null || ls'
alias grep='grep --color=auto'

# Bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Optional aliases file
[ -f ~/.bash_aliases ] && . ~/.bash_aliases

# Nebius CLI path and completion (if installed)
[ -f "$HOME/.nebius/path.bash.inc" ] && . "$HOME/.nebius/path.bash.inc"
[ -f "$HOME/.nebius/completion.bash.inc" ] && . "$HOME/.nebius/completion.bash.inc"

# Homebrew (Linuxbrew)
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# FZF integration
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
  export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always {} 2>/dev/null || sed -n \"1,200p\" {} 2>/dev/null || file -b {}'"
  export FZF_ALT_C_OPTS="--preview 'ls -la --color=always {} 2>/dev/null || eza -la --color=always {} 2>/dev/null'"

  __fzf_try_source() { [ -f "$1" ] && . "$1"; }
  __fzf_try_source /usr/share/doc/fzf/examples/key-bindings.bash
  __fzf_try_source /usr/share/fzf/key-bindings.bash
  __fzf_try_source "$HOME/.fzf.bash"

  if ! bind -q fzf-file-widget 2>/dev/null; then
    __fzf_select_file() { local file; file=$(fzf) && printf '%q' "$file"; }
    bind -x '"\C-t":"READLINE_LINE=\"$READLINE_LINE $(__fzf_select_file)\"; READLINE_POINT=${#READLINE_LINE}"'
  fi
fi

# Zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
  alias cd='z'
fi

# Navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Python / venv helpers
alias avenv='[ -d venv ] && . venv/bin/activate || echo "venv/ not found"'
venv() { python3 -m venv venv && . venv/bin/activate; }

# Tools
alias n='nvim'
alias lg='lazygit'
alias lss='eza --long --no-user --no-time --git --no-permissions --no-filesize --icons --group-directories-first'
alias treee='eza --tree'

# Misc helpers
zrc="$HOME/.bashrc"
editrc() { ${EDITOR:-vi} "$zrc" && . "$zrc"; }

# Functions
mkcd() { mkdir -p -- "$1" && cd -- "$1"; }

# Ensure Ctrl+L clears in all keymaps
bind -m emacs-standard '"\C-l":clear-screen'
bind -m vi-command     '"\C-l":clear-screen'
bind -m vi-insert      '"\C-l":clear-screen'

