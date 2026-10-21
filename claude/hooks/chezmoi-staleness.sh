#!/usr/bin/env bash
# SessionStart hook — assert the DEPLOYED agent-instruction files are not stale
# against their chezmoi source. (claude-dotfiles-8v4)
#
# WHY: ~/.codex/AGENTS.md and ~/.gemini/GEMINI.md sat stale for ten days while
# `chezmoi status` listed them pending the entire time. Worse than stale — they
# carried the INVERSE of the corrected guidance (both said `--effort` sets
# reasoning independently; the corrected source says never pass it, because it
# hard-errors). Two peer seats held an instruction that would fail if followed.
# Nothing was broken: the templates rendered correctly, `chezmoi apply` had
# simply not run. A correct mechanism nobody runs is indistinguishable from a
# broken one.
#
# It asserts on STALENESS, not on content correctness. Detecting wrong guidance
# is unbounded; detecting SKEW is cheap and total. ~18ms on an M-series laptop.
#
# --- Two traps this repo keeps producing, both encoded below -----------------
#
# 1. `chezmoi verify` signals ONLY through its exit code, with EMPTY stdout in
#    both directions. Piping it and reading the output reads as success whether
#    it passed or failed. So: verify is used for the boolean ($?), and `chezmoi
#    status` — which actually prints — is used for the human-readable detail.
#
# 2. `chezmoi verify`/`status` on an UNMANAGED path exits 1 with "not managed"
#    on stderr, which is indistinguishable from skew at the exit-code level.
#    So the watch list is intersected with `chezmoi managed` first: a host that
#    has no gemini seat must go quiet, not cry wolf.
#
# --- Why a scoped watch list and not the whole tree --------------------------
#
# `chezmoi verify` over the full tree exits 1 on this host right now, and
# legitimately so: there is a deliberate pending set (a modified .gitconfig,
# seven not-yet-run run scripts). A guard that fires on every session for
# reasons the reader has already decided to accept trains the reader to ignore
# it — which is the same fail-open, one level of indirection out. So this
# watches exactly the surface the bead is about: the rendered files an agent
# READS AS INSTRUCTIONS at session start.
#
# Skills, commands and hooks are deliberately absent: they are delivered as
# symlinks into the source dir, so they cannot go stale by construction. Only
# rendered (copied) targets can skew. Adding a new rendered instruction file?
# Add it here.

set -uo pipefail

WATCH=(
  "$HOME/.claude/CLAUDE.md"   # @-import shim; the imports resolve into the source dir
  "$HOME/.codex/AGENTS.md"    # flat-concatenated — the whole payload is deployed content
  "$HOME/.gemini/GEMINI.md"   # ditto
)

command -v chezmoi >/dev/null 2>&1 || exit 0

managed="$(chezmoi managed --path-style=absolute 2>/dev/null)" || exit 0
[ -n "$managed" ] || exit 0

watched=()
for t in "${WATCH[@]}"; do
  printf '%s\n' "$managed" | grep -qxF "$t" && watched+=("$t")
done
# bash 3.2 (/bin/bash on macOS) treats "${arr[@]}" on an empty array as a fatal
# error under set -u, so bail before expanding rather than after.
[ "${#watched[@]}" -gt 0 ] || exit 0

# The boolean. Exit code only — never read its stdout.
if chezmoi verify "${watched[@]}" >/dev/null 2>&1; then
  exit 0
fi

# Skewed. `status` is the one that prints; per-path so a "not managed" straggler
# cannot swallow the rest of the report.
detail=""
skewed=()
for t in "${watched[@]}"; do
  line="$(chezmoi status "$t" 2>/dev/null)"
  if [ -n "$line" ]; then
    detail="${detail}    ${line}"$'\n'
    # Show WHAT would change, not just that something would. On 2026-09-19 the
    # status line alone hid a host-doc swap (a real host doc -> _generic) caused by a
    # stray /etc/hosts entry; the suggested apply would have deployed the wrong
    # host doc and reported success. Added/removed lines only, capped.
    hunk="$(chezmoi diff "$t" 2>/dev/null | grep -E '^[-+][^-+]' | head -12)"
    [ -n "$hunk" ] && detail="${detail}$(printf '%s\n' "$hunk" | sed 's/^/        /')"$'\n'
    skewed+=("$t")
  fi
done
# verify said something is off; if status named nothing, report the whole watch
# list rather than emitting an empty warning.
[ "${#skewed[@]}" -gt 0 ] || skewed=("${watched[@]}")

cat <<EOF
## ⚠ chezmoi staleness — deployed agent instructions differ from source

The file(s) below are DEPLOYED copies that no longer match their chezmoi
source. Treat their contents as untrusted for this session: the last time this
happened, two peer seats carried guidance that was the exact inverse of the
corrected source for ten days.

${detail}
Re-render with a TARGETED apply — never a broad one, this repo carries a
deliberate pending set:

    chezmoi apply ${skewed[*]}

If the target was hand-edited (status column 1 is also M), chezmoi asks
"has changed since chezmoi last wrote it?" on a TTY — and in a non-TTY shell
that is not a prompt, it is the hard error "could not open a new TTY", exit 1.
Add --force there, after checking the hand edit is not something you want:

    chezmoi apply --force ${skewed[*]}

Then re-run this to confirm it goes quiet:

    ~/.claude/hooks/chezmoi-staleness.sh
EOF
exit 0
