#!/usr/bin/env bash
# status-extra.sh — portable extension point for the tmux status-right bar.
#
# Runs every executable in ~/.tmux/status-extra.d/ in lexical order and
# concatenates their stdout, so a machine can add a status segment without the
# themes naming it. With the directory empty it prints nothing and the bar has
# no extra segment. Segments are delivered by construction (a file is there or
# it isn't), never by a runtime host test.
#
# CONTRACT for a drop-in:
#   - executable, any interpreter
#   - stdout is inserted verbatim at the LEFT of status-right, so it may contain
#     tmux #[...] style escapes; end with #[default] to avoid bleeding style
#   - print NOTHING when it has nothing to say (a quiet bar is the default)
#   - must be fast: tmux blocks the status redraw on it (status-interval is 5s)
#   - must not fail the bar: errors are swallowed, output is dropped on failure
#
# tmux invokes #(...) with a minimal environment — no ~/.bashrc, no ~/.zshrc —
# so a drop-in must not assume any exported variable from the user's shell.

set -u

dir="${TMUX_STATUS_EXTRA_DIR:-$HOME/.tmux/status-extra.d}"
[ -d "$dir" ] || exit 0

for f in "$dir"/*; do
  # Unmatched glob leaves the literal pattern; -x rejects it along with
  # non-executables (READMEs, .disabled files) in one test.
  [ -x "$f" ] || continue
  # Never let one drop-in take down the bar: drop stderr, and drop stdout too
  # if it exits non-zero (a half-written segment is worse than none).
  if out=$("$f" 2>/dev/null); then
    printf '%s' "$out"
  fi
done
