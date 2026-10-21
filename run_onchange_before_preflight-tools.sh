#!/usr/bin/env bash
# Preflight the HARD tool dependencies before chezmoi writes a single target.
#
# claude-dotfiles-qcy (WSL rehearsal finding F4). `chezmoi apply` stops at the
# FIRST target that errors and silently leaves every later target unapplied.
# On stock Ubuntu 22.04 -- which ships no jq -- the first jq-built settings file exits 127
# partway through, and .local, .tmux, .tmux.conf, .zshrc and .gitconfig are
# never written. The only signal is rc=1. Worse, ~/.claude was already
# populated by then, so the box LOOKS applied.
#
# A _before_ script executes before the rest of the target state, so failing
# here means nothing is half-written: the tree is untouched, and the operator
# gets the install command instead of a 127 from inside a modify_ script.
#
# run_ONCHANGE_before_ rather than plain run_before_, deliberately. A plain
# run_before_ script is pending on EVERY apply, and `chezmoi verify` counts a
# pending script as a difference -- so it would exit 1, with no output, forever.
# That is the exact silent-verify symptom claude-dotfiles-7iv just removed. The
# onchange form still fires on a fresh box (empty state) and whenever this
# script changes; the cost is that removing jq from an already-applied box is
# not re-detected, which is the far cheaper failure.
#
# HARD = a target cannot be produced without it. Everything else (rg, fd, eza,
# bat, delta, direnv) is a convenience and is not checked here -- an apply that
# refuses to run over a missing `bat` would be its own defect.

set -euo pipefail

missing=()
command -v jq  >/dev/null 2>&1 || missing+=(jq)
command -v git >/dev/null 2>&1 || missing+=(git)

[ ${#missing[@]} -eq 0 ] && exit 0

install_hint() {
    if   command -v brew    >/dev/null 2>&1; then echo "brew install $*"
    elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get update && sudo apt-get install -y $*"
    elif command -v dnf     >/dev/null 2>&1; then echo "sudo dnf install -y $*"
    elif command -v pacman  >/dev/null 2>&1; then echo "sudo pacman -S --needed $*"
    elif command -v apk     >/dev/null 2>&1; then echo "sudo apk add $*"
    else echo "install with your platform's package manager: $*"
    fi
}

cat >&2 <<MSG

  chezmoi apply STOPPED — required tool(s) missing: ${missing[*]}

  Nothing has been written. These are hard dependencies of the templates
  (jq builds ~/.claude/settings.json; git is
  used by the source state itself), not optional conveniences.

  Install, then re-run:

      $(install_hint "${missing[@]}")
      chezmoi apply -v

  Why this fails here rather than mid-apply: chezmoi stops at the first
  failing target and leaves an UNKNOWN suffix of the tree unapplied, with
  a bare rc=1 as the only signal. See claude-dotfiles-qcy.

MSG
exit 1
