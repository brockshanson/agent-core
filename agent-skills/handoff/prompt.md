# Handoff Generation

Generate a session handoff document based on the current session's work.

## Instructions

1. **Read Session Context**: Fold this session's log into a fresh summary:
   `python3 ~/.claude/hooks/logger/rollup.py --current` (prints the JSON and
   writes `summary.json`; `--current` is the session that wrote last, which is
   this one). If the logger is not installed (no `~/.claude/hooks/logger/rollup.py`),
   skip this step and work from git and the conversation alone. Fields (full
   contract in `~/.claude/hooks/logger/SCHEMA.md`):
   - `semantic.file_modifications` - files touched
   - `semantic.tool_outcomes` - what succeeded/failed
   - `semantic.error_details` - errors encountered
   - `semantic.decisions` - decisions made (from commits)
   - `outcome` - a heuristic over tool results, not a verdict on the goal
   - `outcome_signals` - success/failure counts

2. **Review Recent Activity**: Look at git status and recent commits to understand what was accomplished.

3. **Gather Peer State** (skip silently unless the host's agent docs describe
   an inter-agent channel; use the commands they give):
   - Mentions and posts aimed at you that you never engaged, read without
     consuming them, so the next session still sees them.
   - Recent traffic for this repo; note anything still in motion that a peer
     flagged (claimed worktrees, fixture daemons, "please don't touch X" notes).
   - Any done notes you already posted this session, so the handoff and the
     channel don't diverge.

4. **Generate Handoff Document**: Create a markdown file with these sections:

```markdown
---
date: YYYY-MM-DD HH:MM
session_id: <from summary>
outcome: <SUCCEEDED|PARTIAL_PLUS|PARTIAL_MINUS|FAILED>
beads_closed: [list of closed bead IDs if any]
---

# Session Handoff: <title>

## What Was Done
- Bullet points of completed work
- Reference specific files: `path/to/file.py:line`

## What Worked
- Successful approaches
- Patterns that helped

## What Failed
- Issues encountered
- Why they failed (if known)

## Key Decisions
- Important choices made
- Rationale when relevant

## Open Peer Asks
- Unanswered mentions or help requests aimed at this session
- Peer claims still standing (worktrees, fixtures, "don't touch" notes)
- Omit this section entirely if there is no channel or nothing open

## Files Modified
- List of files changed with brief description

## Next Steps
- Recommended follow-up actions
- Open questions to address
```

5. **Save the Handoff**:
   - Directory: `H=$(python3 ~/.claude/hooks/logger/log_paths.py handoffs)`; `mkdir -p "$H"`
   - Save as: `$H/YYYY-MM-DD_HHMMSS_<sanitized-title>.md`, local time. The
     SessionStart hook ages handoffs by this stamp, so it must be the real
     time of writing.

6. **Post a done note to the channel** (skip silently if there is none, or if
   you already posted an equivalent note this session):
   - One or two sentences for this repo: what shipped, what's left, pointer to
     the handoff file. Ambient signal, not a changelog.
   - Never let a channel failure block or fail the handoff itself.

7. **Report**: Tell the user where the handoff was saved.

## Arguments

$ARGUMENTS - Optional title for the handoff (default: "Session Handoff")

## Example Output Location

`~/.local/state/claude-logs/-Users-me-Projects-cc-v2/handoffs/2025-12-30_113500_implemented-cc-v2-features.md`
