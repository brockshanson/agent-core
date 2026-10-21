# Agent-core conventions

Portable conventions that hold on **any** machine. Nothing here assumes a
server, a daemon, an internal endpoint, or a private repo.

Host-specific facts live in `hosts/<hostname>/host.md`. Conventions tied to
particular infrastructure live in a separate doc, imported alongside this one
only where that infrastructure exists. If none was imported, assume none of it
exists here.

**Adding a convention?** If it names a hostname, an internal URL, a private
repo, or a daemon, it belongs in the infrastructure doc. If it holds on a stock
laptop with no network, it belongs here.

## Your shell is bash

The agent shell is **bash**, and the recipes you are handed are bash. These
agree, which is the point: the login shell was moved to bash precisely so that
agents stop inheriting a shell whose parsing semantics differ from every recipe
and every LLM-generated command they run. Humans get zsh, launched by the
terminal emulator.

**Verify rather than assume**, because a half-applied cutover is the dangerous
state:

```bash
echo "$BASH_VERSION"   # non-empty on a correctly configured host
type cd                # must be "cd is a shell builtin"
```

If `BASH_VERSION` is empty you are in zsh and the cutover has regressed on this
host. Two consequences fire immediately, both of which **fail open and print
success**:

- **zsh does not word-split unquoted expansions.** `set -- $kv` yields one
  argument, not two; `git add $paths` passes ONE pathspec containing spaces.
- **`cd` may be a zoxide function**, so `cd somedir` can silently land you in a
  different repository entirely and still exit 0.

Report the regression rather than working around it silently. Meanwhile, the
habits below are good practice in any shell and cost nothing:

1. **Quote every expansion.** `"$var"`, `"${arr[@]}"`, `"$@"`. Passing a list?
   Use an array, never a packed string.
2. **Verify effects, not exit codes.** After a `git add`/`commit`, read
   `git show --stat HEAD`. After a config write, parse the file back.
3. **Scripts declare their own shell.** `#!/usr/bin/env bash`, not `#!/bin/bash`
   — the latter is 3.2.57 on macOS, where `"${arr[@]}"` on an empty array is a
   fatal error under `set -u`.

## Preferred CLI tools

When running shell commands, prefer modern replacements for the classics — they're faster, produce cleaner output (which reduces token pressure on agent context), and have saner defaults. This applies to both agent invocations and human typing. The classic tools are still installed; reach for them only for a specific missing feature.

**On a machine you have not provisioned, check before you reach.** These are not POSIX and are not present by default anywhere; `command -v rg fd eza bat sd delta` tells you what you actually have. On a managed device you may not be able to install them at all — fall back to the classics rather than treating their absence as a fault to fix.

| Prefer | Instead of | Why |
|--------|-----------|-----|
| `rg "pat" .` | `grep -r "pat"` | Parallel search; respects `.gitignore`; cleaner output |
| `fd pat` | `find . -name 'pat'` | Intuitive syntax; git-aware; no `-name`/`-exec` dance |
| `eza -l --git .` | `ls -la` | Git status column; icons; tree mode via `-T` |
| `bat file` | `cat file` | Syntax highlighting + line numbers (non-interactive falls back to plain) |
| `sd 'a' 'b' f` | `sed -i 's/a/b/' f` | Sane regex syntax; no `-i`/`-i ''` OS split |
| `delta` | piping `git diff` to `less` | Already wired as git pager; don't override |

**Always pass `rg` and `eza` an explicit path (`.` for the cwd) in agent/non-interactive shells.** With no path and a non-TTY stdin, both read paths from stdin instead of the filesystem, so in the agent Bash tool they hang until the timeout and return *blank*. `rg "pat" .` / `eza -l --git .` are instant; `fd`/`bat`/`sd`/`delta` are unaffected.

Keep the classic when:
- `grep` — POSIX BRE/ERE, `-z` null-delimited, niche flags `rg` doesn't replicate.
- `find` — complex `-exec` or `-prune` patterns.
- `cat` — heredocs (`cat <<EOF`) and single-file pipelines (`... | cat` for unbuffered stdout).
- `sed` — multi-line/multi-command programs (`sd` is single-substitution focused).

When the task is ad-hoc search/list/view, default to modern. When reaching for the classic, briefly note why.

**To bound a command's runtime, use the Bash tool's `timeout` parameter — not a `timeout`/`gtimeout` shell command.** GNU `timeout` is *absent on macOS hosts by default* (no coreutils), so `timeout 30 …` fails with "command not found"; the harness parameter is portable across every host. If you genuinely need an in-shell timeout (e.g. inside a pipeline), `gtimeout` exists only where `brew install coreutils` has run, and `perl -e 'alarm shift; exec @ARGV' <secs> <cmd…>` is the dependency-free fallback.

## Per-repo environment (direnv)

Repos that need environment setup on entry should ship an `.envrc` file. Where the direnv shell hook is already wired, agents and humans just drop the right template and grant allow; on a fresh machine, install `direnv` and add its hook to the shell rc first (`direnv --version` tells you which case you are in).

Canonical templates live at `agent-core/direnv/` in this repo:

| File | Use |
|---|---|
| `python-venv.envrc` | Python repo with `.venv/` — auto-creates via `uv` (fallback `python3 -m venv`), activates via `layout python`, loads `.env`. |
| `node.envrc` | Node repo — adds `node_modules/.bin` to PATH, loads `.env`. Node version itself stays under volta/fnm/asdf. |
| `generic.envrc` | Just load `.env`, optional repo-local `bin/`. |

Install on a new repo:

```bash
cp ~/.local/share/chezmoi/agent-core/direnv/python-venv.envrc .envrc
direnv allow
```

Hard rules:
- `.env` (plaintext values) is gitignored. `.envrc` (the recipe) is committed.
- Never put secrets directly in `.envrc` — load them via `dotenv_if_exists` or a secret backend. `.envrc` is allow-gated but still world-readable on disk.
- When a user reaches for `export FOO=$(grep ... .env ...)` or invokes `.venv/bin/python` explicitly, that's the signal to offer `.envrc` scaffolding instead.

## Commit Conventions

All commits must use a type prefix. Some repos enforce this at push time and reject the whole push on a bad subject, so treat the list as binding rather than advisory.

`feat:` `fix:` `docs:` `chore:` `refactor:` `perf:` `test:` `revert:`
`style:` `build:` `ci:`

An optional scope and a breaking-change marker are both accepted:
`feat(gemini): …`, `refactor!: …`, `fix(bridge)!: …`. A repo that documents its own extra types adds to this list.

## Markdown review — CriticMarkup

Review marks in Markdown use CriticMarkup: `{>>comment<<}` `{++insert++}` `{--delete--}` `{~~old~>new~~}` `{==highlight==}`; marks inside fenced code blocks are literal. Where `review-gate` is installed it reports whether a doc's marks are settled; where it is not, read the marks yourself and never treat its absence as a clean review.

## Delegated work can exit 0 having done nothing

A subagent or peer CLI can return a success-shaped report after a denied tool call, an exhausted quota, or a refused command, having acted on nothing. Never treat exit 0 or a confident report as evidence: check the structured status where there is one, and verify the artifact itself (the file, the commit, the output).
