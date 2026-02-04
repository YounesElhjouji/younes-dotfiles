#!/bin/bash

# Function to format context with appropriate styling
format_context() {
  local ctx="$1"

  if [ -z "$ctx" ] || [ "$ctx" = "-" ]; then
    echo "-"
  elif echo "$ctx" | grep -qi 'dev\|together'; then
    echo "$ctx"
  else
    echo "#[fg=red,bold]${ctx}#[fg=default,nobold]"
  fi
}

# Check if current pane is running SSH
pane_cmd=$(tmux display-message -p '#{pane_current_command}' 2>/dev/null)

if [ "$pane_cmd" = "ssh" ]; then
  # Check if pane has a title set (remote kubectl context)
  pane_title=$(tmux display-message -p '#{pane_title}' 2>/dev/null)

  if [ -n "$pane_title" ] && echo "$pane_title" | grep -qE '^k8s:'; then
    remote_ctx=$(echo "$pane_title" | sed 's/^k8s://')
    format_context "$remote_ctx"
  else
    echo "-"
  fi
else
  # Local: show local kubectl context
  ctx=$(kubectl config current-context 2>/dev/null)

  # Simplify context names for display
  if echo "$ctx" | grep -q 't-ee4544ca'; then
    ctx="together-h100"
  else
    ctx=$(echo "$ctx" | sed 's/.*_//')
  fi

  format_context "$ctx"
fi
