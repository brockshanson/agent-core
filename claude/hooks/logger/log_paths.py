#!/usr/bin/env python3
"""
The one place a Claude log path is decided (claude-dotfiles-abx Phase 3a).

Every writer (master_logger, log_reasoning, the handoff hooks) and every reader
(search_logs.py / claude-log-search, search-reasoning.sh via `log_paths.py dir`)
resolves paths through this module. Before it existed the log root was
recomputed in nine places from the per-event `cwd`, which drifts into
subdirectories mid-session, so logs scattered into <repo>/<subdir>/.claude-logs/
(33 such dirs under ~/Projects on the primary host, 2026-09-28, one inside a .venv).

Layout:

    $CLAUDE_LOG_ROOT (default ${XDG_STATE_HOME:-~/.local/state}/claude-logs)/
      <project-slug>/
        sessions/<YYYY-MM-DD>/<session_id>/{metadata.json,full.jsonl,
                                            tools.jsonl,events.jsonl,summary.json}
        handoffs/<YYYY-MM-DD_HHMMSS>_<title>.md
        reasoning/<commit-hash>.json
        latest -> sessions/<date>/<session_id>

WHY OUTSIDE THE REPO: full.jsonl holds complete tool inputs and outputs. Inside a
project it is one `git add -A` from a commit, and on a client repo that is a leak.
~/.local/state is local APFS, never iCloud, which O_APPEND atomicity needs
(docs/hook-logging-redesign.md §9.3-9.4).

WHY NOT ~/.claude/logs (the first choice, 2026-09-28): Claude Code's retention
sweep lists `logs/` under ~/.claude as a legacy directory and deletes its
contents after cleanupPeriodDays (default 30; code.claude.com/docs/en/
claude-directory, "Cleaned up automatically"). Keeping sessions past that
window is most of what this logger is still for, so the root must sit where
the sweep never looks.

WHY THE SLUG MATCHES CLAUDE CODE'S: ~/.claude/projects/<slug>/ holds Claude
Code's own transcripts under the same name, so a session's log dir and its
transcript can be joined by eye.

WHY WORKTREES FOLD INTO THEIR MAIN REPO: a worktree session is work on the same
project. Keying on the worktree path would give each short-lived worktree its own
log dir and strand its handoff where the next session never looks.

Pure stdlib, no subprocess: this runs on every tool call.
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Optional

LOG_ROOT_ENV = 'CLAUDE_LOG_ROOT'


def log_root() -> Path:
    """Root of all Claude logs on this host, created owner-only (0700).

    The logs hold full tool input and output. Files inside are written with the
    default umask (usually 0644), so the directory mode is what keeps other
    local users out (portable-core red team, 2026-09-29).
    """
    override = os.environ.get(LOG_ROOT_ENV)
    if override:
        root = Path(override).expanduser()
    else:
        state = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local' / 'state')
        root = Path(state).expanduser() / 'claude-logs'
    try:
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if root.stat().st_mode & 0o077:
            os.chmod(root, 0o700)
    except OSError:
        pass  # a reader on a read-only or foreign root must still resolve the path
    return root


RETENTION_ENV = 'CLAUDE_LOG_RETENTION_DAYS'


def prune(days: Optional[int] = None) -> int:
    """Delete session dirs older than `days` (by their date directory).

    `days` defaults to $CLAUDE_LOG_RETENTION_DAYS; unset or 0 keeps everything,
    which was the behaviour before this existed. The settings template
    sets 30. Handoffs and reasoning are small and kept.
    Returns the number of session date directories removed.
    """
    import shutil
    from datetime import date, timedelta
    if days is None:
        try:
            days = int(os.environ.get(RETENTION_ENV, '0') or 0)
        except ValueError:
            return 0
    if days <= 0:
        return 0
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    removed = 0
    for sessions in log_root().glob('*/sessions'):
        for d in sessions.iterdir():
            if re.fullmatch(r'\d{4}-\d{2}-\d{2}', d.name) and d.name < cutoff and d.is_dir():
                shutil.rmtree(d, ignore_errors=True)
                removed += 1
    return removed


def _main_worktree_from_gitfile(gitfile: Path) -> Optional[Path]:
    """A linked worktree's `.git` is a file: `gitdir: <main>/.git/worktrees/<name>`."""
    try:
        line = gitfile.read_text(errors='replace').strip()
    except OSError:
        return None
    if not line.startswith('gitdir:'):
        return None
    gitdir = Path(line[len('gitdir:'):].strip())
    if not gitdir.is_absolute():
        gitdir = (gitfile.parent / gitdir).resolve()
    # <main>/.git/worktrees/<name> -> <main>. Submodules point at
    # <super>/.git/modules/<name>; those are their own project, keep the checkout.
    if gitdir.parent.name == 'worktrees' and gitdir.parent.parent.name == '.git':
        return gitdir.parent.parent.parent
    return gitfile.parent


def project_root(cwd: Optional[str] = None) -> Path:
    """The project a session belongs to.

    CLAUDE_PROJECT_DIR first (stable for the whole session), then the event cwd,
    then the process cwd; from there, walk up to the git root, folding a linked
    worktree into its main checkout. Not in git: the start directory itself.
    """
    start = os.environ.get('CLAUDE_PROJECT_DIR') or cwd or os.getcwd()
    try:
        here = Path(start).expanduser().resolve()
    except OSError:
        here = Path(start)
    for candidate in (here, *here.parents):
        dotgit = candidate / '.git'
        if dotgit.is_dir():
            return candidate
        if dotgit.is_file():
            return _main_worktree_from_gitfile(dotgit) or candidate
    return here


def project_slug(root: Path) -> str:
    """Claude Code's own naming for ~/.claude/projects/<slug>/."""
    return re.sub(r'[^A-Za-z0-9]', '-', str(root))


def project_log_dir(cwd: Optional[str] = None) -> Path:
    return log_root() / project_slug(project_root(cwd))


def session_dir(project_dir: Path, session_id: str, date_str: str) -> Path:
    return project_dir / 'sessions' / date_str / session_id


def find_session_dirs(project_dir: Path, session_id: str) -> List[Path]:
    """Every date dir a session wrote to, oldest first (sessions cross midnight UTC)."""
    return sorted(p for p in (project_dir / 'sessions').glob(f'*/{session_id}') if p.is_dir())


def handoffs_dir(cwd: Optional[str] = None) -> Path:
    return project_log_dir(cwd) / 'handoffs'


def reasoning_dir(cwd: Optional[str] = None) -> Path:
    return project_log_dir(cwd) / 'reasoning'


if __name__ == '__main__':
    # Shell entry point, so shell readers resolve paths the same way:
    #   log_paths.py [root|project|handoffs|reasoning] [cwd]
    #   log_paths.py prune     (uses $CLAUDE_LOG_RETENTION_DAYS; unset or 0 = keep all)
    what = sys.argv[1] if len(sys.argv) > 1 else 'project'
    where = sys.argv[2] if len(sys.argv) > 2 else None
    resolvers = {
        'root': lambda: log_root(),
        'project': lambda: project_log_dir(where),
        'handoffs': lambda: handoffs_dir(where),
        'reasoning': lambda: reasoning_dir(where),
    }
    if what == 'prune':
        print(prune())
        sys.exit(0)
    if what not in resolvers:
        print(f'usage: log_paths.py [{"|".join(resolvers)}] [cwd]', file=sys.stderr)
        sys.exit(2)
    print(resolvers[what]())
