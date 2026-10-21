#!/usr/bin/env python3
"""
SessionStart Handoff Hook
Loads the latest handoff into context at session start.
"""

from __future__ import annotations

import json
import re
import sys
import os
from pathlib import Path
from datetime import datetime, timedelta

sys.path.insert(0, str(Path(__file__).resolve().parent / 'logger'))
import log_paths  # noqa: E402

_STAMP = re.compile(r'^(\d{4}-\d{2}-\d{2}_\d{6})_')


def written_at(path: Path) -> datetime | None:
    """When a handoff was written, from its filename stamp.

    Not mtime: a git checkout, clone, or copy resets mtime to "now", so a
    months-old handoff in a fresh worktree read as written today and was
    injected into a new session as current (seen 2026-09-28: a 2026-06-13
    handoff loaded into an unrelated session).
    """
    m = _STAMP.match(path.name)
    if m:
        try:
            return datetime.strptime(m.group(1), '%Y-%m-%d_%H%M%S')
        except ValueError:
            pass
    try:
        return datetime.fromtimestamp(path.stat().st_mtime)
    except OSError:
        return None


def find_latest_handoff(handoffs_dir: Path) -> Path | None:
    """Find the most recent handoff file."""

    if not handoffs_dir.exists():
        return None

    # Check for latest symlink first
    latest_link = handoffs_dir / 'latest.md'
    if latest_link.is_symlink():
        try:
            target = latest_link.resolve()
            if target.exists():
                return target
        except:
            pass

    # Fall back to finding most recent by filename
    # Filter out symlinks — broken symlinks crash stat()
    handoffs = [p for p in handoffs_dir.glob('*.md') if not p.is_symlink()]
    if not handoffs:
        return None

    handoffs.sort(key=lambda p: written_at(p) or datetime.min, reverse=True)
    return handoffs[0]


def is_recent(handoff_path: Path, max_hours: int = 24) -> bool:
    """Check if handoff is recent enough to be relevant."""
    stamp = written_at(handoff_path)
    return stamp is not None and datetime.now() - stamp < timedelta(hours=max_hours)


def main():
    try:
        # Read hook input
        input_data = json.load(sys.stdin)
    except:
        input_data = {}

    # After a compaction the session already holds Claude Code's own summary,
    # and the newest handoff is usually that same summary (post-compact-handoff.py).
    # Injecting it again only spends context.
    if input_data.get('source') == 'compact':
        sys.exit(0)

    cwd = input_data.get('cwd', os.getcwd())
    handoff_path = find_latest_handoff(log_paths.handoffs_dir(cwd))

    if not handoff_path:
        sys.exit(0)

    # Only load if recent (within 24 hours)
    if not is_recent(handoff_path, max_hours=24):
        sys.exit(0)

    try:
        with open(handoff_path) as f:
            content = f.read()

        # Output handoff content to STDOUT — SessionStart injects stdout into the
        # agent's context (stderr is terminal-only). This is the whole point of the
        # hook; emitting to stderr silently dropped every handoff (claude-dotfiles-gox).
        print("")
        print("📋 Previous Session Handoff:")
        print("-" * 40)

        # Limit output to avoid overwhelming context
        lines = content.split('\n')
        if len(lines) > 50:
            # Show first 40 lines + note
            for line in lines[:40]:
                print(line)
            print("")
            print(f"... ({len(lines) - 40} more lines)")
            print(f"Full handoff: {handoff_path}")
        else:
            print(content)

        print("-" * 40)
        print("")

    except Exception as e:
        # Don't block session start, but surface WHY context is missing instead of
        # swallowing it silently (claude-dotfiles-74a).
        print(f"[session-start-handoff] could not load handoff: {e}", file=sys.stderr)

    sys.exit(0)


if __name__ == '__main__':
    main()
