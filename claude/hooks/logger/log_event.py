#!/usr/bin/env python3
# Event Logging Hook for Claude Code Logger
# Handles Stop, SubagentStop, Notification, and PreCompact events

import subprocess
import sys
from pathlib import Path

# Get master_logger.py from same directory as this script
master_logger = Path(__file__).parent / 'master_logger.py'

try:
    subprocess.run([sys.executable, str(master_logger)], stdin=sys.stdin, check=True)
except subprocess.CalledProcessError as e:
    sys.exit(e.returncode)