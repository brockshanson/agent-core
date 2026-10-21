#!/usr/bin/env python3
"""
summary.json as a read-side rollup of full.jsonl (claude-dotfiles-abx Phase 3c).

WHY THIS REPLACED THE IN-PROCESS SUMMARY

master_logger used to accumulate the summary in memory and flush it every 20
events. But every hook invocation is a fresh process, so the "accumulated" state
only ever held the one event that process handled: across 100 sessions on
the primary host (2026-09-28) every summary.json recorded a single event, and 98 of 100
said IN_PROGRESS. It also read `tool_result`, a key Claude Code never sends (the
payload key is `tool_response`), so no failure was ever counted. The pre-compact
handoff (since retired), log_reasoning and /logs' pre-filter were all reading that.

The fix is to stop pretending the hot path has memory: summarise by folding the
session's full.jsonl, which is the durable record anyway. It runs at Stop
and on demand, never per tool call.

FAILURE SIGNAL: Claude Code fires PostToolUse only for tools that succeeded and
PostToolUseFailure for ones that failed. That hook event is the failure count.
Substring-matching "error" in successful output (the old heuristic) marked every
Read of a file mentioning errors as a failure.

Usage:  rollup.py <session_id|--current> [cwd]   -> writes and prints summary.json

`--current` picks the session whose full.jsonl was written most recently. Run
from inside a session's Bash tool, that is the calling session: its own
PreToolUse record for that very command was just appended.
"""

import json
import os
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import log_paths  # noqa: E402

SUMMARY_SCHEMA = 2

_STOP_WORDS = {
    'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'her', 'was', 'one', 'our',
    'had', 'has', 'what', 'were', 'said', 'each', 'which', 'she', 'use', 'how', 'they', 'his',
    'will', 'would', 'could', 'should', 'may', 'might', 'must', 'this', 'that', 'these', 'those',
    'with', 'from', 'into', 'during', 'including', 'until', 'against', 'among', 'throughout',
    'despite', 'towards', 'upon', 'concerning', 'off', 'out', 'over', 'after', 'about',
}
_MODIFYING_TOOLS = ('Edit', 'Write', 'NotebookEdit')
_COMMIT_OK = re.compile(r'\[[^\]]+ [0-9a-f]{7,}\]')


def _keywords(text: str) -> Iterable[str]:
    return (w for w in re.findall(r'\b[a-zA-Z]{3,}\b', text.lower()) if w not in _STOP_WORDS)


def _as_dict(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except ValueError:
            return {}
    return {}


def _error_summary(text: str, max_len: int = 150) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:max_len]
    return ''


def _records(dirs: List[Path]) -> Iterable[Dict[str, Any]]:
    for d in dirs:
        try:
            with open(d / 'full.jsonl', 'rb') as f:
                for raw in f:
                    try:
                        yield json.loads(raw)
                    except ValueError:
                        continue  # a torn line must not sink the whole summary
        except OSError:
            continue


def outcome(signals: Dict[str, int]) -> str:
    """SUCCEEDED / PARTIAL_PLUS / PARTIAL_MINUS / FAILED / IN_PROGRESS.

    A coarse heuristic, and labelled as one wherever it is shown: it knows what
    tools did, not whether the user's goal was met.
    """
    ok, bad = signals['tool_successes'], signals['tool_failures']
    total = ok + bad
    if total == 0:
        return 'IN_PROGRESS'
    rate = ok / total
    progress = signals['files_modified'] > 0 or signals['commits_made'] > 0
    if rate >= 0.8 and progress:
        return 'SUCCEEDED'
    if rate >= 0.6 or progress:
        return 'PARTIAL_PLUS'
    if rate >= 0.3:
        return 'PARTIAL_MINUS'
    return 'FAILED'


def rollup(session_id: str, project_dir: Path) -> Optional[Dict[str, Any]]:
    """Fold every full.jsonl the session wrote into one summary. None if no log."""
    dirs = log_paths.find_session_dirs(project_dir, session_id)
    if not dirs:
        return None

    keywords: Counter = Counter()
    event_counts: Counter = Counter()
    tools, files, error_kw = set(), set(), set()
    signals = {'tool_successes': 0, 'tool_failures': 0, 'errors_encountered': 0,
               'files_modified': 0, 'commits_made': 0}
    file_mods: List[Dict[str, Any]] = []
    tool_outcomes: List[Dict[str, Any]] = []
    error_details: List[Dict[str, Any]] = []
    decisions: List[Dict[str, Any]] = []
    first_ts = last_ts = None
    project_roots = set()

    for rec in _records(dirs):
        etype = rec.get('event_type', '')
        ts = rec.get('timestamp')
        first_ts = first_ts or ts
        last_ts = ts or last_ts
        event_counts[etype] += 1
        if rec.get('project_dir'):
            project_roots.add(rec['project_dir'])
        data = _as_dict(rec.get('data', {})).get('input', {})
        if not isinstance(data, dict):
            continue
        tool = data.get('tool_name')
        if tool:
            tools.add(tool)
        tin = _as_dict(data.get('tool_input'))
        if tin.get('file_path'):
            files.add(tin['file_path'])
        for field in ('prompt', 'message', 'command', 'description'):
            val = data.get(field) or tin.get(field)
            if isinstance(val, str) and val:
                keywords.update(_keywords(val))

        if etype == 'post_tool_use':
            signals['tool_successes'] += 1
            entry = {'tool': tool, 'success': True, 'timestamp': ts}
            if tool == 'Bash':
                cmd = tin.get('command', '')
                entry['command_preview'] = cmd[:80] + ('...' if len(cmd) > 80 else '')
                if 'git commit' in cmd:
                    stdout = str(_as_dict(data.get('tool_response')).get('stdout', ''))
                    if _COMMIT_OK.search(stdout):
                        signals['commits_made'] += 1
                        first = stdout.splitlines()[0] if stdout else ''
                        decisions.append({'description': f'Committed: {first[:100]}', 'timestamp': ts})
            if tool in _MODIFYING_TOOLS:
                signals['files_modified'] += 1
            if tool in _MODIFYING_TOOLS + ('Read',) and tin.get('file_path'):
                mod = {'path': tin['file_path'], 'tool': tool,
                       'action': 'read' if tool == 'Read' else 'modify', 'timestamp': ts}
                if tool == 'Edit' and tin.get('old_string'):
                    old = tin['old_string']
                    mod['context'] = old[:100] + ('...' if len(old) > 100 else '')
                file_mods.append(mod)
            tool_outcomes.append(entry)

        elif etype == 'post_tool_use_failure':
            signals['tool_failures'] += 1
            signals['errors_encountered'] += 1
            err = str(data.get('error') or data.get('tool_response') or '')
            summary = _error_summary(err)
            low = err.lower()
            for kw in ('traceback', 'exception', 'error', 'fail', 'timeout', 'denied'):
                if kw in low:
                    error_kw.add(kw)
            entry = {'tool': tool, 'success': False, 'error_summary': summary, 'timestamp': ts}
            if tool == 'Bash':
                entry['command_preview'] = tin.get('command', '')[:80]
            tool_outcomes.append(entry)
            detail = {'type': 'tool_failure', 'message': summary, 'tool': tool, 'timestamp': ts}
            if tin.get('file_path'):
                detail['file_context'] = tin['file_path']
            error_details.append(detail)

    return {
        'schema': SUMMARY_SCHEMA,
        'session_id': session_id,
        'date': dirs[0].parent.name,
        'dates': [d.parent.name for d in dirs],
        'project_dirs': sorted(project_roots),
        'first_event': first_ts,
        'last_updated': last_ts,
        'keywords': dict(keywords.most_common(50)),
        'tools_used': sorted(tools),
        'file_paths': sorted(files),
        'error_keywords': sorted(error_kw),
        'event_counts': dict(event_counts),
        'outcome': outcome(signals),
        'outcome_signals': signals,
        'semantic': {
            'file_modifications': file_mods[-50:],
            'tool_outcomes': tool_outcomes[-100:],
            'error_details': error_details[-20:],
            'decisions': decisions[-20:],
        },
    }


def write_summary(session_id: str, project_dir: Path) -> Optional[Dict[str, Any]]:
    """Roll up and write summary.json into the session's newest date dir, atomically."""
    summary = rollup(session_id, project_dir)
    if summary is None:
        return None
    target = log_paths.find_session_dirs(project_dir, session_id)[-1] / 'summary.json'
    tmp = target.with_name(f'.summary.json.{os.getpid()}')
    with open(tmp, 'w') as f:
        json.dump(summary, f, separators=(',', ':'))
    os.replace(tmp, target)  # readers never see a half-written summary
    return summary


def current_session_id(project_dir: Path) -> Optional[str]:
    logs = list(project_dir.glob('sessions/*/*/full.jsonl'))
    if not logs:
        return None
    return max(logs, key=lambda p: p.stat().st_mtime).parent.name


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('usage: rollup.py <session_id|--current> [cwd]', file=sys.stderr)
        sys.exit(2)
    project = log_paths.project_log_dir(sys.argv[2] if len(sys.argv) > 2 else None)
    sid = current_session_id(project) if sys.argv[1] == '--current' else sys.argv[1]
    result = write_summary(sid, project) if sid else None
    print(json.dumps(result, indent=2) if result else '{}')
