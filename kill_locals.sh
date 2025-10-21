#!/bin/bash
# Script to stop running PM2 processes, kill Python processes, and kill Node.js processes.

# Function to safely kill processes and report
safe_kill() {
  local process_name="$1"
  local kill_cmd="$2"

  # Find and kill processes
  processes=$(eval "$kill_cmd")

  if [[ -n "$processes" ]]; then
    echo "Killing $process_name processes: $processes"
    eval "$kill_cmd" && echo "Successfully killed $process_name processes." || echo "Failed to kill $process_name processes."
  else
    echo "No $process_name processes found."
  fi
}

# 1. Stop all processes managed by PM2
echo "Stopping PM2 processes..."
pm2 stop all
echo "PM2 processes stopped."

# 2. Kill all Python processes
safe_kill "Python" "pkill -f python"

# 3. Kill all Node.js processes
safe_kill "Node.js" "pkill -f node"

echo "Script completed."
