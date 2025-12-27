#!/bin/bash
# ~/.tmux/copy_previous.sh
#
# Copies the previous command block (prompt line + output) as a fenced ```zsh block.
# Matches prompts by a regex marker. Default matches either ➜ or ➭.
#
# Override example:
#   export TMUX_PROMPT_REGEX='(➜|➭|^\$ )'

set -euo pipefail

# Default: match either arrow commonly used by prompts
regex="${TMUX_PROMPT_REGEX:-➜|➭}"

pane=$(tmux capture-pane -J -p -S -1000)

prompt_lines=()
while IFS= read -r line; do
  prompt_lines+=("$line")
done < <(printf '%s\n' "$pane" | grep -n -E "$regex" | cut -d: -f1)

if [ "${#prompt_lines[@]}" -lt 2 ]; then
  output="$pane"
else
  start=${prompt_lines[$((${#prompt_lines[@]} - 2))]}
  end=${prompt_lines[$((${#prompt_lines[@]} - 1))]}

  if [ "$end" -le "$start" ]; then
    output="$pane"
  else
    output=$(printf '%s\n' "$pane" | sed -n "${start},$((end - 1))p")
  fi
fi

wrapped=$(printf '```zsh\n%s\n```\n' "$output")

if command -v xclip >/dev/null 2>&1; then
  printf '%s' "$wrapped" | xclip -sel clip
elif command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$wrapped" | pbcopy
else
  tmux display-message "No clipboard tool (xclip or pbcopy) found."
  exit 1
fi

tmux display-message "Previous command + output copied"
