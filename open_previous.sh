#!/usr/bin/env bash
# ~/.tmux/open_previous.sh
#
# This script captures the contents of the current tmux pane, extracts
# the logs for the previous command (using a prompt marker),
# writes the output into a temporary file, and opens it with nvim.
#
# The user can then:
#   - copy the entire contents
#   - exit without saving easily (:q!)
#   - save the logs to a file (:w filename)
#   - visually select and copy parts of the text
#
# You can override the prompt marker by setting TMUX_PROMPT_REGEX.
# Default is "➜".

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
  logs="$pane"
else
  # The penultimate occurrence marks the beginning of the previous command.
  start=${prompt_lines[$((${#prompt_lines[@]} - 2))]}
  # The last occurrence is the current prompt, so extract until one line before it.
  end=${prompt_lines[$((${#prompt_lines[@]} - 1))]}

  if [ "$end" -le "$start" ]; then
    logs="$pane"
  else
    # Extract the text from the start line to one line before the current prompt.
    logs=$(echo "$pane" | sed -n "${start},$((end - 1))p")
  fi
fi

if [ -z "$logs" ]; then
  tmux display-message "No logs extracted."
  exit 1
fi

# Create a temporary file to hold the logs.
# Use a macOS-friendly template.
mkdir -p /tmp/logs
tmpfile=$(mktemp /tmp/logs/grab.XXXX)
if [ -z "$tmpfile" ] || [ ! -f "$tmpfile" ]; then
  tmux display-message "Failed to create temporary file."
  exit 1
fi

echo "$logs" > "$tmpfile"

# Open the file in nvim.
tmux send-keys -t "$TMUX_PANE" "nvim '$tmpfile'" Enter
