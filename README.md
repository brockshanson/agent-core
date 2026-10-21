# agent-core

My Claude Code and Codex CLI setup, with the shell, tmux and terminal layer
they run in, for a new machine. Managed by [chezmoi](https://chezmoi.io).
Public so a clean machine can clone it without a credential.

## What comes along

| Path | What |
|---|---|
| `agent-core/charter/` | How I work with agents. Loaded first by every agent doc. |
| `agent-core/AGENTS.core.md` | Shared agent conventions. Claude reads it by `@`-import, Codex by concatenation. |
| `hosts/_generic/host.md` | What this machine lacks, so agents stop reaching for it. |
| `agent-core/{tmux,starship,lazygit,glow,direnv,wezterm}/` | The terminal layer. WezTerm installs on macOS only; on Windows, copy it across by hand. |
| `agent-core/claude-themes/` | Flexoki light and dark for Claude Code, with a contrast check. |
| `claude/` | Hooks (status line, session logging, handoff at compaction), `/interview` and `/logs`, read-only subagents, the deep-research workflow, and the settings template. |
| `agent-skills/` | The interview skills (`interviewing`, `create-spec`, `grill-me`), `handoff` and `logs`. |
| `codex/` | Codex execpolicy rules. |
| `dot_*/`, `run_*` | chezmoi templates and bootstrap scripts. |

## Defaults

The settings template pins no model, pre-approves only WebSearch and
`command -v`, starts no MCP server, and turns the account's claude.ai
connectors off (`ENABLE_CLAUDEAI_MCP_SERVERS`; set it to `"true"` in
`~/.claude/settings.json` to turn them back on, and later applies keep it).

Some pieces name a model and fail without access to it: the `researcher`
subagent (Fable), `lean-worker` (Sonnet), `/interview` (Opus), and
`deep-research` (Opus, Sonnet, Haiku).

## What it writes where

Everything stays on this machine.

| Store | Where | Kept for |
|---|---|---|
| Session logs | `~/.local/state/claude-logs/`, owner-only | 30 days (`CLAUDE_LOG_RETENTION_DAYS`; 0 keeps all) |
| Claude Code transcripts | `~/.claude/projects/` | 365 days, unless you set `cleanupPeriodDays` |
| tmux sessions | `~/.local/share/tmux/resurrect/` | Layout and commands, not pane contents |

git ignores `.claude-logs/` everywhere as a backstop. Machine settings such as
your git identity or a corporate CA go in `~/.config/git/local`, which this repo
never touches.

## Install

The full Windows 11 + WSL2 walkthrough, with a check and an undo for each step,
is in [docs/setup-guide](docs/setup-guide/). The short version:

```bash
curl -fsLS https://get.chezmoi.io -o /tmp/chezmoi-install.sh && sh /tmp/chezmoi-install.sh -b ~/.local/bin   # or: brew install chezmoi
chezmoi init https://github.com/brockshanson/agent-core.git
chezmoi diff        # read it before anything is written
chezmoi apply -v
```

Needs `jq` and `git` (checked before anything is written), plus `bash` 4+ and
`python3` 3.9+ (not checked). Every step that reaches the network names its
host first; `DOTFILES_NO_NETWORK=1` skips them all and prints what to run later.
The first zsh launch also clones zinit from github.com, and honours the same
switch.

Most of the tree is one-line `symlink_*.tmpl` files: each declares one link in
`~`.

## License

MIT; see [`LICENSE`](LICENSE). The theme colors are
[Flexoki](https://stephango.com/flexoki) by Steph Ango, MIT licensed.
