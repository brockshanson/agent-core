# 05-mise.sh — put mise-installed tools on PATH, without activating mise.
#
# Sourced by both ~/.zshrc and ~/.bashrc through the ~/.config/shell/rc.d/
# loop, which runs before the prompt and tool inits so mise-managed binaries
# (rg, fd, eza, starship, lazygit, ...) are on PATH when those inits look for
# them. A non-home machine gets its CLI tools from mise (yme.9 decision,
# 2026-08-23); a host without mise skips this silently.
#
# Before this drop-in, applying the dotfiles replaced a ~/.zshrc or ~/.profile
# that had been activating mise by hand, and mise-installed tools vanished
# from new shells (found by the setup guide, 2026-09-28).
command -v mise >/dev/null 2>&1 || return 0

# mise is the INSTALLER only (owner, 2026-09-29). At shell start, ask it once
# for the real bin/ directories of the installed tools and put them first on
# PATH: no shims and no activation hook, so `cd` stays the shell builtin in
# both shells (AGENTS.core.md tells agents to check that; hook activation broke
# it on a clean Ubuntu 24.04 run, 2026-09-28). Trade-off: a shell that is
# already open keeps the old version after `mise upgrade` until a new shell
# starts.
_mise_bins=$(mise bin-paths 2>/dev/null) || { unset _mise_bins; return 0; }
_mise_path=
while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    case ":$PATH:" in *":$_d:"*) continue ;; esac
    _mise_path="${_mise_path:+$_mise_path:}$_d"
done <<MISE_BINS
$_mise_bins
MISE_BINS
[ -n "$_mise_path" ] && PATH="$_mise_path:$PATH" && export PATH
unset _mise_bins _mise_path _d
