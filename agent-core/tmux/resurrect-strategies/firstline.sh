#!/usr/bin/env bash
#
# Vendored tmux-resurrect save-command strategy — single-line, exact-parent.
#
# Selected via `set -g @resurrect-save-command-strategy 'firstline'` in
# tmux.conf; symlinked into the TPM-managed plugin dir by chezmoi
# (dot_tmux/plugins/tmux-resurrect/save_command_strategies/).
#
# WHY THIS EXISTS (2026-08-25, claude-dotfiles):
# Upstream's default `ps` strategy corrupts the save file. save.sh:199 splices
# this script's stdout UNQUOTED into the last tab-delimited field:
#
#     echo "...${d}${pane_command}${d}:${full_command}"
#
# while upstream ps.sh prints ONE LINE PER CHILD PROCESS:
#
#     ps -ao "ppid,args" | sed "s/^ *//" | grep "^${PANE_PID}" | cut -d' ' -f2-
#
# So any pane whose shell has 2+ children (every Claude Code pane — it spawns
# several MCP server children) writes a multi-line record and
# splits one `pane` row into many. A corrupt save makes restore create few or
# no sessions; tmux-resurrect's handle_session_0 (restore.sh:283) then runs
# `tmux kill-session -t "0"` unconditionally, so a bare `tmux` — which creates
# a session literally named "0" — is left with ZERO sessions and the server
# exits. Symptom: tmux draws, then dies a beat after attach.
#
# Upstream's grep is also a PREFIX match (`^63320` matches ppid 633201);
# harmless on macOS (PID_MAX 99999) but not on Linux, where PIDs go higher.
#
# THREE GUARANTEES this makes that upstream does not:
#   1. Exactly one line   — head -n 1
#   2. Exact parent match — pgrep -P (not a prefix grep)
#   3. No stray delimiter — tab/newline stripped; TAB is the field separator
#
# Portability: `pgrep -lf` is NOT portable — macOS prints the full command
# line, Linux/procps-ng prints only the process name. So resolve the pid with
# `pgrep -P` (same on both) and read the args with `ps -o args= -p`.
#
# Picking the first child is a deliberate narrowing: with @resurrect-processes
# unset only the default whitelist (vim/less/top/...) is ever re-run, so the
# field is near-decorative — correctness of the FILE matters far more than
# which sibling wins.

PANE_PID="$1"
[ -z "$PANE_PID" ] && exit 0

child="$(pgrep -P "$PANE_PID" 2>/dev/null | head -n 1)"
[ -z "$child" ] && exit 0

ps -o args= -p "$child" 2>/dev/null | head -n 1 | tr -d '\t\n'
