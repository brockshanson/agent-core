#!/usr/bin/env bash
# Session Initialization Hook for Claude Code Logger
# This script initializes a new logging session

# Call the session logger. Surface a failure to stderr instead of failing silently
# (claude-dotfiles-zsa), but always exit 0 so a logging problem never blocks session start.
~/.claude/hooks/logger/master_logger.py
rc=$?
[ "$rc" -eq 0 ] || echo "[init_session] master_logger.py init failed (exit $rc)" >&2
# Retention: drop session logs older than $CLAUDE_LOG_RETENTION_DAYS (unset or 0
# keeps everything). Once per session start; never blocks it.
python3 ~/.claude/hooks/logger/log_paths.py prune >/dev/null 2>&1 || true
exit 0