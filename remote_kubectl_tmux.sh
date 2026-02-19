#!/bin/bash
# Add this to your .bashrc or .zshrc on remote machines
# This updates the tmux pane title with kubectl context and cwd

# Function to update tmux pane title with kubectl context and cwd
__update_tmux_pane_title() {
  # Check if we're likely in a tmux session (works even over SSH)
  if [ -n "$TMUX" ] || [[ "$TERM" == tmux* ]] || [[ "$TERM" == screen* ]]; then
    local title=""
    local ctx=$(kubectl config current-context 2>/dev/null | sed 's/.*_//')
    if [ -n "$ctx" ]; then
      title="k8s:${ctx} "
    fi
    title="${title}cwd:${PWD}"
    printf '\033]2;%s\033\\' "$title"
  fi
}

# For Bash: add to PROMPT_COMMAND
if [ -n "$BASH_VERSION" ]; then
  PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;} __update_tmux_pane_title"
fi

# For Zsh: add to precmd hook
if [ -n "$ZSH_VERSION" ]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd __update_tmux_pane_title
fi
