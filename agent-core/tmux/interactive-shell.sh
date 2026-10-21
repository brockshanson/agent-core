#!/usr/bin/env bash
# The interactive shell for a tmux pane: zsh for humans, bash for agents.
# Wired as tmux's default-command; tmux.conf says why not default-shell.
#
# KEEP IT A SCRIPT, one command. tmux-resurrect restores a pane by running
# "exec <default-command>", so an inline compound `if` became `exec if ...`, a
# syntax error that killed every restored pane and then the tmux server.
#
# zsh is found on PATH, not at /bin/zsh; without it, $SHELL, then /bin/sh.

if command -v zsh >/dev/null 2>&1; then
	exec zsh -l
else
	exec "${SHELL:-/bin/sh}" -l
fi
