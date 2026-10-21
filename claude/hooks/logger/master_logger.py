#!/usr/bin/env python3
"""
Claude Code session logger: one hook event in, one JSONL record out.

Every hook invocation is its own process, so this module holds no cross-event
state. Where things go is decided in log_paths.py; the record format is
documented in SCHEMA.md; summary.json is folded from full.jsonl by rollup.py at
Stop and PreCompact, never accumulated here (claude-dotfiles-abx Phase 3).
"""

import datetime
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import log_paths  # noqa: E402
import rollup  # noqa: E402

if os.name != 'nt':
    import fcntl
else:  # pragma: no cover - Windows has no fcntl; appends go unlocked there
    fcntl = None

HOOK_VERSION = '2.0.0'
_METADATA_JSON = json.dumps({'hook_version': HOOK_VERSION, 'python_version': sys.version.split()[0]})

# hook_event_name -> (event_type in the record, file the record is routed to
# besides full.jsonl). SCHEMA.md documents these; readers switch on event_type.
EVENT_TYPES = {
    'SessionStart': ('session_start', 'events.jsonl'),
    'PreToolUse': ('pre_tool_use', 'tools.jsonl'),
    'PostToolUse': ('post_tool_use', 'tools.jsonl'),
    'PostToolUseFailure': ('post_tool_use_failure', 'tools.jsonl'),
    'UserPromptSubmit': ('user_prompt', 'messages.jsonl'),
    'Notification': ('notification', 'events.jsonl'),
    'Stop': ('stop', 'events.jsonl'),
    'SubagentStop': ('subagent_stop', 'events.jsonl'),
    'PreCompact': ('compact', 'events.jsonl'),
}


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def _iso(ts: datetime.datetime) -> str:
    return ts.isoformat().replace('+00:00', 'Z')


def _session_id(input_data: Dict[str, Any]) -> str:
    sid = input_data.get('session_id')
    if not sid:
        transcript = input_data.get('transcript_path', '')
        sid = os.path.basename(transcript).replace('.jsonl', '') if transcript else ''
    return sid or _now().strftime('%Y%m%d_%H%M%S')


class _Locked:
    """Exclusive flock for the duration of a with-block (no-op where unsupported)."""

    def __init__(self, fh):
        self.fh = fh

    def __enter__(self):
        if fcntl:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX)
        return self.fh

    def __exit__(self, *exc):
        if fcntl:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)


class ClaudeLogger:
    def __init__(self, input_data: Dict[str, Any]):
        self.input = input_data
        self.session_id = _session_id(input_data)
        # Resolved ONCE per event, from CLAUDE_PROJECT_DIR before the per-event
        # cwd: cwd drifts into subdirectories mid-session, which is what
        # scattered .claude-logs/ dirs through project subtrees (§9.5).
        self.project_root = log_paths.project_root(input_data.get('cwd'))
        self.project_log_dir = log_paths.log_root() / log_paths.project_slug(self.project_root)
        self.now = _now()
        self.date_str = self.now.strftime('%Y-%m-%d')
        self.session_dir = log_paths.session_dir(self.project_log_dir, self.session_id, self.date_str)
        self.session_dir.mkdir(parents=True, exist_ok=True)

    def _next_sequence(self) -> int:
        """Monotonic per-session counter, persisted every event under a lock.

        Pre- and PostToolUse hooks are async and can run concurrently, so the
        read-increment-write must be one critical section or two events share a
        number. Persisting every event (not every 10th) is claude-dotfiles-90w.
        """
        seq_file = self.session_dir / '.sequence'
        with open(seq_file, 'a+') as fh, _Locked(fh):
            fh.seek(0)
            try:
                current = int(fh.read().strip() or 0)
            except ValueError:
                current = 0
            fh.seek(0)
            fh.truncate()
            fh.write(str(current + 1))
            fh.flush()
        return current + 1

    def _update_latest(self):
        """<project>/latest -> this session. For humans; code keys on session_id."""
        link = self.project_log_dir / 'latest'
        tmp = self.project_log_dir / f'latest.tmp.{os.getpid()}'
        try:
            os.symlink(os.path.relpath(self.session_dir, self.project_log_dir), tmp)
            os.replace(tmp, link)
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass

    def write(self, event_type: str, route: str, extra: Optional[Dict[str, Any]] = None) -> str:
        """Append one envelope record to full.jsonl and its routed file."""
        data = {'input': self.input}
        if extra:
            data.update(extra)
        record = (
            f'{{"timestamp": "{_iso(self.now)}", '
            f'"session_id": {json.dumps(self.session_id)}, '
            f'"event_type": "{event_type}", '
            f'"sequence_number": {self._next_sequence()}, '
            f'"project_dir": {json.dumps(str(self.project_root))}, '
            f'"data": {json.dumps(data, ensure_ascii=False)}, '
            f'"metadata": {_METADATA_JSON}}}\n'
        )
        # One write() per record per file, under flock: offset atomicity alone
        # does not stop two large appends interleaving (§9.3).
        for name in ('full.jsonl', route):
            with open(self.session_dir / name, 'a') as fh, _Locked(fh):
                fh.write(record)
        return record

    def session_start(self):
        meta = {
            'session_id': self.session_id,
            'start_time': _iso(self.now),
            'project_dir': str(self.project_root),
            'cwd': self.input.get('cwd', os.getcwd()),
            'source': self.input.get('source', 'unknown'),
            'transcript_path': self.input.get('transcript_path', ''),
        }
        with open(self.session_dir / 'metadata.json', 'w') as f:
            json.dump(meta, f, indent=2)
        self._update_latest()
        return {'metadata': meta}


def main():
    try:
        input_data = json.load(sys.stdin)
        hook_event = input_data.get('hook_event_name', '')
        event_type, route = EVENT_TYPES.get(hook_event, (f'unknown_{hook_event}', 'events.jsonl'))
        logger = ClaudeLogger(input_data)

        extra = None
        if hook_event == 'SessionStart':
            extra = logger.session_start()
        logger.write(event_type, route, extra)

        # Summaries are folded from the durable log at natural boundaries only.
        # SubagentStop shares the parent's session_id; the parent's Stop covers it.
        if hook_event in ('Stop', 'PreCompact'):
            rollup.write_summary(logger.session_id, logger.project_log_dir)
    except Exception as e:
        # Exit code 2 from a PreToolUse hook blocks the tool call; any other
        # non-zero exit is reported as a hook error. Either is wrong for a
        # logging failure, so always exit 0 and say so on stderr
        # (claude-dotfiles-45x).
        print(f'Logging error: {e}', file=sys.stderr)
    sys.exit(0)


if __name__ == '__main__':
    main()
