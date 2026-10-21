#!/usr/bin/env python3
# Tool Logging Hook for Claude Code Logger
# Handles PreToolUse and PostToolUse events

import sys
from pathlib import Path

# Run master_logger in-process instead of spawning a second Python interpreter.
# master_logger.main() reads sys.stdin and calls sys.exit() itself, so its exit
# code propagates exactly as the old subprocess path did — minus one ~20ms
# interpreter startup per call (this hook fires on every Pre/PostToolUse).
sys.path.insert(0, str(Path(__file__).parent))
import master_logger  # noqa: E402

master_logger.main()