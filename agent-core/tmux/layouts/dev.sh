#!/usr/bin/env bash
# Dev Layout: Claude on left, terminal + editor stacked on right
# Usage: dev.sh [session] [directory]
#   If no directory specified, uses current pane's directory

SESSION="${1:-$(tmux display-message -p '#S')}"
START_DIR="${2:-${PWD:-$(tmux display-message -p '#{pane_current_path}')}}"

# Extract project name from directory for window title
PROJECT_NAME=$(basename "$START_DIR")
WINDOW_NAME="${PROJECT_NAME}:dev"

# Create new window (don't switch yet) and capture its ID
WINDOW_ID=$(tmux new-window -t "$SESSION" -d -c "$START_DIR" -P -F '#{window_id}')

# Disable automatic-rename BEFORE any commands run
tmux set-option -t "$WINDOW_ID" automatic-rename off
tmux rename-window -t "$WINDOW_ID" "$WINDOW_NAME"

# Split: main left pane stays, create right pane (35% width)
tmux split-window -t "$WINDOW_ID" -h -l 35% -c "$START_DIR"

# Split the right pane vertically: terminal top (60%), editor bottom (40%)
tmux split-window -t "$WINDOW_ID.1" -v -l 40% -c "$START_DIR"

# Name the panes (pane-base-index is 1)
tmux select-pane -t "$WINDOW_ID.1" -T "claude"
tmux select-pane -t "$WINDOW_ID.2" -T "terminal"
tmux select-pane -t "$WINDOW_ID.3" -T "editor"

# Select the main pane and start claude
tmux select-pane -t "$WINDOW_ID.1"
tmux send-keys -t "$WINDOW_ID.1" "claude" Enter

# Switch to the new window
tmux select-window -t "$WINDOW_ID"
