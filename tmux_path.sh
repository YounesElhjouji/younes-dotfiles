#!/bin/bash

# Show remote cwd if in SSH session, otherwise local pane path

pane_cmd=$(tmux display-message -p '#{pane_current_command}' 2>/dev/null)

if [ "$pane_cmd" = "ssh" ]; then
  pane_title=$(tmux display-message -p '#{pane_title}' 2>/dev/null)

  if [ -n "$pane_title" ] && echo "$pane_title" | grep -q 'cwd:'; then
    echo "$pane_title" | sed 's/.*cwd://'
  else
    echo "-"
  fi
else
  tmux display-message -p '#{=60:pane_current_path}'
fi
