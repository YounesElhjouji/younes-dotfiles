#!/bin/bash
# ~/.tmux/copy_previous.sh
#
# This script captures the current tmux pane contents, finds the last two
# occurrences of a prompt marker (default: "➜"), and copies the block of text
# starting at the previous command (including its prompt) and ending just
# before the current prompt.
#
# You can override the marker by setting the TMUX_PROMPT_REGEX environment
# variable. For example:
#   export TMUX_PROMPT_REGEX='\$'
# would use the dollar sign as your prompt marker.

# Use the marker provided by the environment or default to "➜"
regex="${TMUX_PROMPT_REGEX:-➜}"

# Capture the last 1000 lines from the current pane (adjust -S if needed)
pane=$(tmux capture-pane -J -p -S -1000)

# Populate an array with line numbers that contain the prompt marker.
prompt_lines=()
while IFS= read -r line; do
  prompt_lines+=("$line")
done < <(echo "$pane" | grep -n "$regex" | cut -d: -f1)

# If less than 2 prompt occurrences are found, copy all 1000 lines.
if [ "${#prompt_lines[@]}" -lt 2 ]; then
  output="$pane"
else
  # The penultimate occurrence marks the beginning of the previous command.
  start=${prompt_lines[$((${#prompt_lines[@]} - 2))]}
  # The last occurrence is the current prompt, so we will extract until the line before it.
  end=${prompt_lines[$((${#prompt_lines[@]} - 1))]}

  if [ "$end" -le "$start" ]; then
    output="$pane"
  else
    # Extract the text from the start line to one line before the current prompt.
    output=$(echo "$pane" | sed -n "${start},$((end - 1))p")
  fi
fi

# Copy the extracted text to clipboard, using xclip (Linux) or pbcopy (macOS)
if command -v xclip >/dev/null 2>&1; then
  echo "$output" | xclip -sel clip
elif command -v pbcopy >/dev/null 2>&1; then
  echo "$output" | pbcopy
else
  tmux display-message "No clipboard tool (xclip or pbcopy) found."
  exit 1
fi

tmux display-message "Previous command and its output copied to clipboard."
