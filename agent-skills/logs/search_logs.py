#!/usr/bin/env python3
"""
Claude-friendly log search utility.
Returns structured JSON output for programmatic consumption.
"""

import json
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

# Paths come from the logger's own resolver, so this reader and the writers
# cannot disagree about where a project's logs live. Repo layout first (this
# file is symlinked from the chezmoi source), installed hooks second.
for _candidate in (Path(__file__).resolve().parents[2] / 'claude' / 'hooks' / 'logger',
                   Path.home() / '.claude' / 'hooks' / 'logger'):
    if (_candidate / 'log_paths.py').exists():
        sys.path.insert(0, str(_candidate))
        break
try:
    import log_paths
except ImportError:  # pragma: no cover - reported as a JSON error by main()
    log_paths = None


def find_log_directory(start_path: Path = None) -> Optional[Path]:
    """This project's log dir under the log root, if it has any logs."""
    if log_paths is None:
        return None
    log_dir = log_paths.project_log_dir(str(start_path) if start_path else None)
    return log_dir if log_dir.is_dir() else None


def read_jsonl(file_path: Path) -> List[Dict[str, Any]]:
    """Read a JSONL file and return list of entries."""
    entries = []
    if file_path.exists():
        with open(file_path) as f:
            for line in f:
                try:
                    entries.append(json.loads(line.strip()))
                except json.JSONDecodeError:
                    continue
    return entries


def _list_sessions_light(log_dir: Path, days: int = 7) -> List[Dict[str, Any]]:
    """Lightweight session listing for search — skips metadata/summary/line counting.
    Uses os.scandir instead of pathlib for speed."""
    sessions = []
    sessions_dir = os.path.join(str(log_dir), 'sessions')
    if not os.path.isdir(sessions_dir):
        return sessions

    # String comparison works for YYYY-MM-DD format (lexicographic = chronological)
    start_date_str = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

    try:
        date_entries = sorted(os.scandir(sessions_dir), key=lambda e: e.name, reverse=True)
    except OSError:
        return sessions

    for date_entry in date_entries:
        if not date_entry.is_dir():
            continue
        name = date_entry.name
        # Validate YYYY-MM-DD format and filter by date
        if len(name) != 10 or name[4] != '-' or name[7] != '-':
            continue
        if name < start_date_str:
            continue

        try:
            session_entries = sorted(os.scandir(date_entry.path), key=lambda e: e.name, reverse=True)
        except OSError:
            continue

        for session_entry in session_entries:
            if not session_entry.is_dir():
                continue
            sessions.append({
                'date': date_entry.name,
                'session_id': session_entry.name,
                'path': session_entry.path,
            })

    return sessions


def list_sessions(log_dir: Path, days: int = 7) -> List[Dict[str, Any]]:
    """List available sessions from the last N days."""
    sessions = []
    sessions_dir = log_dir / 'sessions'

    if not sessions_dir.exists():
        return sessions

    end_date = datetime.now()
    start_date = end_date - timedelta(days=days)

    for date_dir in sorted(sessions_dir.iterdir(), reverse=True):
        if not date_dir.is_dir():
            continue
        try:
            dir_date = datetime.strptime(date_dir.name, '%Y-%m-%d')
            if dir_date < start_date:
                continue
        except ValueError:
            continue

        for session_dir in sorted(date_dir.iterdir(), reverse=True):
            if not session_dir.is_dir():
                continue

            session_info = {
                'date': date_dir.name,
                'session_id': session_dir.name,
                'path': str(session_dir),
            }

            # Read metadata
            metadata_file = session_dir / 'metadata.json'
            if metadata_file.exists():
                try:
                    with open(metadata_file) as f:
                        metadata = json.load(f)
                    session_info['start_time'] = metadata.get('start_time')
                    session_info['project_dir'] = metadata.get('project_dir')
                except:
                    pass

            # Read summary
            summary_file = session_dir / 'summary.json'
            if summary_file.exists():
                try:
                    with open(summary_file) as f:
                        session_info['summary'] = json.load(f)
                except:
                    pass

            # Count entries
            full_log = session_dir / 'full.jsonl'
            if full_log.exists():
                session_info['entry_count'] = sum(1 for _ in open(full_log))

            sessions.append(session_info)

    return sessions


def search_sessions(log_dir: Path, query: str, days: int = 30,
                   max_results: int = 50, search_type: str = 'all') -> Dict[str, Any]:
    """
    Search sessions for a query.

    search_type options:
    - 'all': Search all content
    - 'keywords': Search summary keywords only (fastest)
    - 'tools': Search tool usage
    - 'files': Search file paths
    - 'prompts': Search user prompts only (empty unless UserPromptSubmit logging is wired)
    - 'errors': Search for error indicators
    """
    sessions = _list_sessions_light(log_dir, days)
    query_lower = query.lower()
    query_bytes = query_lower.encode('utf-8')

    # Pre-compute search_type checks
    check_keywords = search_type in ('all', 'keywords')
    check_tools = search_type in ('all', 'tools')
    check_files = search_type in ('all', 'files')
    check_errors = search_type in ('all', 'errors')

    results = {
        'query': query,
        'search_type': search_type,
        'days_searched': days,
        'sessions_scanned': len(sessions),
        'matches': []
    }

    for session in sessions:
        session_path = session['path']  # already a string from _list_sessions_light
        match_info = {
            'session_id': session['session_id'],
            'date': session['date'],
            'project_dir': None,
            'match_reasons': [],
            'excerpts': []
        }

        # Phase 1: Check summary for quick filtering
        summary_match = False
        summary = {}
        try:
            with open(os.path.join(session_path, 'summary.json')) as f:
                summary = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass

        if check_keywords:
            keywords = summary.get('keywords', {})
            matching_keywords = [k for k in keywords if query_lower in k.lower()]
            if matching_keywords:
                summary_match = True
                match_info['match_reasons'].append(f"keywords: {matching_keywords[:5]}")

        if check_tools:
            tools = summary.get('tools_used', [])
            matching_tools = [t for t in tools if query_lower in t.lower()]
            if matching_tools:
                summary_match = True
                match_info['match_reasons'].append(f"tools: {matching_tools}")

        if check_files:
            files = summary.get('file_paths', [])
            matching_files = [f for f in files if query_lower in f.lower()]
            if matching_files:
                summary_match = True
                match_info['match_reasons'].append(f"files: {matching_files[:5]}")

        if check_errors:
            errors = summary.get('error_keywords', [])
            matching_errors = [e for e in errors if query_lower in e.lower()]
            if matching_errors:
                summary_match = True
                match_info['match_reasons'].append(f"errors: {matching_errors}")

        # Phase 2: Deep search
        should_deep_search = summary_match or not summary or search_type == 'prompts'

        if not should_deep_search and summary:
            event_counts = summary.get('event_counts', {})
            total_events = sum(event_counts.values())
            if total_events < 10:
                should_deep_search = True

        if should_deep_search:
            # Choose appropriate log file
            if search_type == 'tools':
                log_file = os.path.join(session_path, 'tools.jsonl')
            else:
                log_file = os.path.join(session_path, 'full.jsonl')

            try:
                # Binary search: avoids UTF-8 decode for non-matching lines
                with open(log_file, 'rb') as f:
                    for raw_line in f:
                        if query_bytes in raw_line.lower():
                            try:
                                entry = json.loads(raw_line)
                            except (json.JSONDecodeError, UnicodeDecodeError):
                                continue
                            excerpt = extract_excerpt(entry, query, query_lower)
                            if excerpt:
                                match_info['excerpts'].append(excerpt)
                                if len(match_info['excerpts']) >= 3:
                                    break
            except FileNotFoundError:
                pass

        if match_info['match_reasons'] or match_info['excerpts']:
            # Deferred metadata read — only for confirmed matches
            try:
                with open(os.path.join(session_path, 'metadata.json')) as f:
                    metadata = json.load(f)
                match_info['project_dir'] = metadata.get('project_dir')
            except (FileNotFoundError, json.JSONDecodeError, OSError):
                pass
            results['matches'].append(match_info)
            if len(results['matches']) >= max_results:
                break

    results['total_matches'] = len(results['matches'])
    return results


def extract_excerpt(entry: Dict[str, Any], query: str, query_lower: str = None) -> Optional[Dict[str, Any]]:
    """Extract a relevant excerpt from a log entry."""
    if query_lower is None:
        query_lower = query.lower()

    excerpt = {
        'timestamp': entry.get('timestamp'),
        'event_type': entry.get('event_type'),
        'sequence': entry.get('sequence_number'),
    }

    data = entry.get('data', {})
    input_data = data.get('input', {})

    # Extract relevant content based on event type
    event_type = entry.get('event_type', '')

    if event_type == 'user_prompt':
        prompt = input_data.get('prompt', '')
        if query_lower in prompt.lower():
            excerpt['content_type'] = 'prompt'
            excerpt['content'] = truncate_around_match(prompt, query, 200)
            return excerpt

    elif event_type in ('pre_tool_use', 'post_tool_use', 'post_tool_use_failure'):
        tool_name = input_data.get('tool_name', '')
        tool_input = input_data.get('tool_input', {})

        excerpt['tool_name'] = tool_name

        if query_lower in tool_name.lower():
            excerpt['content_type'] = 'tool_name'
            return excerpt

        # Check tool input fields
        for field in ('command', 'file_path', 'pattern', 'content'):
            if field in tool_input:
                value = str(tool_input[field])
                if query_lower in value.lower():
                    excerpt['content_type'] = f'tool_{field}'
                    excerpt['content'] = truncate_around_match(value, query, 150)
                    return excerpt

        error = str(input_data.get('error') or '')
        if error and query_lower in error.lower():
            excerpt['content_type'] = 'tool_error'
            excerpt['content'] = truncate_around_match(error, query, 150)
            return excerpt

    elif event_type == 'notification':
        message = input_data.get('message', '')
        if query_lower in message.lower():
            excerpt['content_type'] = 'notification'
            excerpt['content'] = truncate_around_match(message, query, 150)
            return excerpt

    return None


def truncate_around_match(text: str, query: str, max_length: int = 150) -> str:
    """Truncate text to show context around the match."""
    query_lower = query.lower()
    text_lower = text.lower()

    match_pos = text_lower.find(query_lower)
    if match_pos == -1:
        return text[:max_length] + ('...' if len(text) > max_length else '')

    start = max(0, match_pos - max_length // 2)
    end = min(len(text), match_pos + len(query) + max_length // 2)

    snippet = text[start:end]
    if start > 0:
        snippet = '...' + snippet
    if end < len(text):
        snippet = snippet + '...'

    return snippet


def global_search(query: str, max_results: int = 30, days: int = 60) -> Dict[str, Any]:
    """Search every project under the log root.

    A directory walk, not the old ~/.claude/log-registry.json: the registry sat
    behind a host-wide lock that could wedge every session (abx Phase 1) and had
    been frozen since 2026-05-16. One root makes the walk cheap.
    """
    results = {
        'query': query,
        'scope': 'global',
        'projects_searched': 0,
        'matches': []
    }
    if log_paths is None:
        results['error'] = 'logger log_paths.py not found'
        return results
    root = log_paths.log_root()
    if not root.is_dir():
        results['error'] = f'No log root at {root}'
        return results

    for project_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        results['projects_searched'] += 1
        project_results = search_sessions(project_dir, query, days=days, max_results=10)
        if project_results['matches']:
            results['matches'].append({
                'project_slug': project_dir.name,
                'project_path': project_results['matches'][0].get('project_dir'),
                'session_matches': project_results['matches'][:5]
            })
        if len(results['matches']) >= max_results:
            break

    results['total_project_matches'] = len(results['matches'])
    return results


def get_session_detail(log_dir: Path, date: str, session_id: str) -> Dict[str, Any]:
    """Get detailed information about a specific session."""
    session_path = log_dir / 'sessions' / date / session_id

    if not session_path.exists():
        return {'error': f'Session not found: {date}/{session_id}'}

    result = {
        'session_id': session_id,
        'date': date,
        'path': str(session_path),
    }

    # Read metadata
    metadata_file = session_path / 'metadata.json'
    if metadata_file.exists():
        with open(metadata_file) as f:
            result['metadata'] = json.load(f)

    # Read summary
    summary_file = session_path / 'summary.json'
    if summary_file.exists():
        with open(summary_file) as f:
            result['summary'] = json.load(f)

    # Read recent entries
    full_log = session_path / 'full.jsonl'
    if full_log.exists():
        entries = read_jsonl(full_log)
        result['entry_count'] = len(entries)
        result['recent_entries'] = entries[-20:]  # Last 20 entries

    return result


def main():
    parser = argparse.ArgumentParser(description='Claude-friendly log search')
    subparsers = parser.add_subparsers(dest='command', help='Command')

    # List command
    list_parser = subparsers.add_parser('list', help='List recent sessions')
    list_parser.add_argument('--days', type=int, default=7, help='Days to look back')

    # Search command
    search_parser = subparsers.add_parser('search', help='Search logs')
    search_parser.add_argument('query', help='Search query')
    search_parser.add_argument('--days', type=int, default=30, help='Days to search')
    search_parser.add_argument('--max', type=int, default=50, help='Max results')
    search_parser.add_argument('--type', choices=['all', 'keywords', 'tools', 'files', 'prompts', 'errors'],
                              default='all', help='Search type')

    # Global search command
    global_parser = subparsers.add_parser('global', help='Search all projects')
    global_parser.add_argument('query', help='Search query')
    global_parser.add_argument('--max', type=int, default=30, help='Max results')
    global_parser.add_argument('--days', type=int, default=60, help='Days to search')

    # Session detail command
    detail_parser = subparsers.add_parser('detail', help='Get session details')
    detail_parser.add_argument('--date', required=True, help='Session date (YYYY-MM-DD)')
    detail_parser.add_argument('--session', required=True, help='Session ID')

    args = parser.parse_args()

    # Find log directory
    log_dir = find_log_directory()

    if args.command == 'list':
        if not log_dir:
            print(json.dumps({'error': 'No logs for this project', 'looked_in': str(log_paths.project_log_dir()) if log_paths else None}))
            return
        sessions = list_sessions(log_dir, args.days)
        print(json.dumps({'sessions': sessions}, indent=2))

    elif args.command == 'search':
        if not log_dir:
            print(json.dumps({'error': 'No logs for this project', 'looked_in': str(log_paths.project_log_dir()) if log_paths else None}))
            return
        results = search_sessions(log_dir, args.query, args.days, args.max, args.type)
        print(json.dumps(results, indent=2))

    elif args.command == 'global':
        results = global_search(args.query, args.max, args.days)
        print(json.dumps(results, indent=2))

    elif args.command == 'detail':
        if not log_dir:
            print(json.dumps({'error': 'No logs for this project', 'looked_in': str(log_paths.project_log_dir()) if log_paths else None}))
            return
        result = get_session_detail(log_dir, args.date, args.session)
        print(json.dumps(result, indent=2))

    else:
        parser.print_help()


if __name__ == '__main__':
    main()
