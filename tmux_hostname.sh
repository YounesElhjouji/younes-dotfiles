#!/bin/bash

# Show SSH target hostname if in SSH session, otherwise local hostname

pane_cmd=$(tmux display-message -p '#{pane_current_command}' 2>/dev/null)

if [ "$pane_cmd" = "ssh" ]; then
  # Get the pane's PID and find the ssh process to extract hostname
  pane_pid=$(tmux display-message -p '#{pane_pid}' 2>/dev/null)

  # Find ssh child process and get its arguments
  ssh_args=$(ps -o args= -p $(pgrep -P "$pane_pid" ssh 2>/dev/null | head -1) 2>/dev/null)

  if [ -n "$ssh_args" ]; then
    # Extract hostname from ssh command (last argument that's not a flag)
    hostname=$(echo "$ssh_args" | awk '{for(i=NF;i>0;i--) if($i !~ /^-/) {print $i; exit}}')
    echo "${hostname}"
  else
    echo "ssh"
  fi
else
  # Local hostname
  hostname -s
fi
