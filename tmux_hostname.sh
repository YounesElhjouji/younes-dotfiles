#!/bin/bash

# Show SSH target hostname if in SSH session, otherwise local hostname

pane_cmd=$(tmux display-message -p '#{pane_current_command}' 2>/dev/null)

if [ "$pane_cmd" = "ssh" ]; then
  # Get the pane's PID and find the ssh process in that pane's process tree.
  pane_pid=$(tmux display-message -p '#{pane_pid}' 2>/dev/null)

  ssh_args=$(
    ps -axo pid=,ppid=,comm=,args= |
      awk -v root="$pane_pid" '
        {
          pid=$1
          ppid=$2
          comm=$3
          args=$0
          sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", args)
          parent[pid]=ppid
          command[pid]=comm
          argv[pid]=args
        }
        END {
          for (pid in parent) {
            cur=pid
            while (cur != "" && cur != 0) {
              if (cur == root) {
                if (command[pid] ~ /(^|\/)ssh$/) {
                  print argv[pid]
                  exit
                }
                break
              }
              cur=parent[cur]
            }
          }
        }
      '
  )

  if [ -n "$ssh_args" ]; then
    python3 - "$ssh_args" <<'PY'
import os
import shlex
import sys

try:
    tokens = shlex.split(sys.argv[1])
except ValueError:
    tokens = sys.argv[1].split()

if tokens and os.path.basename(tokens[0]) == "ssh":
    tokens = tokens[1:]

options_with_args = {
    "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m",
    "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w",
}
short_options_with_args = set("bcDEeFIiJLlmOoQpRSWw")

i = 0
host = ""
while i < len(tokens):
    token = tokens[i]
    if token == "--":
        i += 1
        break
    if not token.startswith("-"):
        host = token
        break
    if token in options_with_args:
        i += 2
        continue
    if len(token) > 2 and token[0] == "-" and token[1] in short_options_with_args:
        i += 1
        continue
    i += 1

if not host and i < len(tokens):
    host = tokens[i]

if host:
    print(host.rsplit("@", 1)[-1])
else:
    print("ssh")
PY
  else
    echo "ssh"
  fi
else
  # Local hostname
  hostname -s
fi
