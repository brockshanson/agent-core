---
name: logs
description: |
  Search Claude conversation logs for past context and patterns.
  Use when you need to recall: prior discussions, implementation approaches,
  tool usage patterns, or debugging context from previous sessions.
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
---

# Conversation Log Search

Search the session logs the logger hooks write, to recall what was done before:
how something was implemented, which files a feature touched, what failed and
why, what was committed with what context.

## Where the logs are

One root per host, one directory per project:

```
~/.local/state/claude-logs/<project-slug>/          ($CLAUDE_LOG_ROOT overrides the root)
  sessions/<YYYY-MM-DD>/<session_id>/{metadata.json, summary.json, full.jsonl, tools.jsonl, events.jsonl}
  handoffs/*.md       reasoning/<sha>.json       latest -> newest session
```

The slug is the repo root path with non-alphanumerics turned into `-`, the same
name Claude Code gives the project under `~/.claude/projects/`. Worktrees share
their main repo's directory. The field-by-field contract is
`~/.claude/hooks/logger/SCHEMA.md`; read it before parsing anything by hand.

To print this project's log directory:

```bash
python3 ~/.claude/hooks/logger/log_paths.py project
```

## Search (JSON out)

`claude-log-search` is this skill's `search_logs.py` on PATH. Every command
prints JSON.

```bash
claude-log-search search "QUERY" [--days 30] [--type all|keywords|tools|files|errors] [--max 50]
claude-log-search global "QUERY" [--days 60] [--max 30]   # every project under the root
claude-log-search list [--days 7]                          # this project's sessions
claude-log-search detail --date YYYY-MM-DD --session ID    # metadata, summary, last 20 events
```

`search` resolves the project from the current directory (any subdirectory of a
repo works). If `claude-log-search` is not on PATH, run
`python3 <this skill dir>/search_logs.py` with the same arguments.

How it searches: `summary.json` (tools, files, keywords, error words) narrows the
candidate sessions, then the raw `full.jsonl` lines are scanned for the query and
up to three excerpts per session come back with their event type and sequence.

## Direct reads

For anything the search does not cover, the JSONL is greppable. Pass `rg` an
explicit path:

```bash
L=$(python3 ~/.claude/hooks/logger/log_paths.py project)
rg -l 'pattern' "$L"/sessions/                 # which sessions mention it
rg '"event_type": "post_tool_use_failure"' "$L"/sessions/*/*/tools.jsonl   # every tool failure
jq -c 'select(.data.input.tool_name=="Bash") | .data.input.tool_input.command' "$L"/sessions/<date>/<id>/tools.jsonl
```

## Reading results honestly

- `summary.json` `outcome` is a heuristic over tool successes and failures. It
  does not know whether the user's goal was met; say so if you quote it.
- Summaries with no `schema` field predate 2026-09-28 and are unreliable (each
  recorded one event and never counted a failure). Use the JSONL for those.
- User prompts are not logged by default; `--type prompts` returns nothing unless
  UserPromptSubmit logging has been wired. The full conversation is in the
  session's `transcript_path` (see `metadata.json`) while Claude Code keeps it.
- A null result is only meaningful if the search can find a known positive. If
  nothing turns up, search for something you know is there (a file you edited
  today) before reporting that the log has nothing.

## Reporting

Say how many sessions and projects were searched, show the excerpts that
matter with their dates and session ids, and offer to open a specific session
with `detail`.
