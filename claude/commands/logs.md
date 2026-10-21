---
description: Search Claude session logs (this project, or every project)
---

Search the Claude session logs with `claude-log-search`, the `logs` skill's
search tool, and summarise what it returns.

Arguments: `$ARGUMENTS`

- `search <query>` or a bare `<query>`: this project → `claude-log-search search "<query>"`
- `global <query>`: every project → `claude-log-search global "<query>"`
- `recent`: this project's sessions from the last 7 days → `claude-log-search list`
- `detail <date> <session>`: one session → `claude-log-search detail --date <date> --session <session>`

The output is JSON. Report how many sessions or projects were searched and the
excerpts that matter, with dates and session ids. If a search comes back empty,
run a positive control (search for something you know this session did) before
saying the logs have nothing. Layout and fields: `~/.claude/hooks/logger/SCHEMA.md`.
