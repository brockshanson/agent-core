#!/usr/bin/env python3
"""
PostCompact Handoff Hook
Saves the summary Claude Code wrote at compaction as a handoff for the next session.

WHY THIS REPLACED pre-compact-handoff.py (2026-09-28): the old hook built its
handoff before compaction from the logger's tool counts. 210 of 241 of those
handoffs (87%) had no files section and read like "1 succeeded, 0 failed".
Since PostCompact exists, Claude Code hands the hook the model-written
`compact_summary` itself (code.claude.com/docs/en/hooks#postcompact), which is
the thing the old hook was trying to approximate.

It prints nothing: the compacted session already carries this summary, so the
file exists only for the NEXT session, which session-start-handoff.py injects.
PostCompact has no decision control; this hook cannot affect compaction.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / 'logger'))
import log_paths  # noqa: E402


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    summary = (data.get('compact_summary') or '').strip()
    if not summary:
        return
    now = datetime.now()
    handoffs = log_paths.handoffs_dir(data.get('cwd') or os.getcwd())
    handoffs.mkdir(parents=True, exist_ok=True)
    path = handoffs / f"{now.strftime('%Y-%m-%d_%H%M%S')}_postcompact.md"
    path.write_text('\n'.join([
        '---',
        f"date: {now.strftime('%Y-%m-%d %H:%M')}",
        f"session_id: {data.get('session_id', 'unknown')}",
        f"trigger: PostCompact ({data.get('trigger', '?')})",
        '---',
        '',
        '# Compaction Summary',
        '',
        summary,
        '',
    ]))
    latest = handoffs / 'latest.md'
    try:
        if latest.is_symlink() or latest.exists():
            latest.unlink()
        latest.symlink_to(path.name)
    except OSError:
        pass


if __name__ == '__main__':
    try:
        main()
    except Exception as e:  # never block the session over a handoff
        print(f'[post-compact-handoff] {e}', file=sys.stderr)
    sys.exit(0)
