---
name: handoff
description: >
  Generate an end-of-session handoff document capturing what was done, what
  worked, what failed, and next steps. Use at session close or when the user
  says "handoff", "/handoff", "wrap up the session", or work must transfer to
  another agent or session.
---
# /handoff - Generate Session Handoff

Generate an end-of-session handoff document capturing what was done, what worked, what failed, and next steps.

## Usage

```
/handoff [title]
```

## What It Does

Creates a structured handoff document in the project's handoff directory,
`~/.local/state/claude-logs/<project-slug>/handoffs/` (print it with
`python3 ~/.claude/hooks/logger/log_paths.py handoffs`), with:

- **What Was Done**: Summary of completed work with file references
- **What Worked**: Successful approaches and patterns
- **What Failed**: Issues encountered and why
- **Key Decisions**: Important choices made during the session
- **Open Peer Asks**: unanswered peer mentions and standing peer claims
- **Next Steps**: Recommended follow-up actions

Where the host's agent docs describe an inter-agent channel, it also gathers
unanswered mentions from it and posts a one-line done note (with a pointer to
the handoff file) after saving. No channel, or a failing one, never blocks the
handoff.

## When to Use

- Before ending a long session
- Before context compaction, when you want more than Claude Code's own
  compaction summary (a PostCompact hook saves that summary automatically)
- When switching to a different task
- To document progress on a Beads issue

## Output

Saves to: `<handoffs dir>/YYYY-MM-DD_HHMMSS_<title>.md`. The next session in
this project (or any of its worktrees) gets it injected at start if it is under
24 hours old, judged by that filename stamp. The same directory holds the
automatic `_postcompact.md` handoffs (Claude Code's compaction summary, saved
verbatim), so both kinds share one read path. Neither is injected into a
session resuming from compaction, which already holds that summary.

Handoffs live outside the repo, so they do not travel between hosts. If a
handoff must reach another machine, commit a copy deliberately; do not point
the handoff directory back into the repo.

## Example

```
/handoff "Implemented CC-v2 features"
```

Generates a handoff document summarizing the session's work on CC-v2 feature implementation.
