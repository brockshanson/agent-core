#!/usr/bin/env bash
# claude-dotfiles installer — thin chezmoi bootstrap wrapper.
#
# Makes sure chezmoi is installed and pointed at this checkout, then hands
# off to `chezmoi apply`. An alternative to `chezmoi init <url>` for when the
# repo is already cloned.
#
# For first-time setup on a new host:
#   git clone <this repo's remote> ~/Projects/claude-dotfiles
#   ~/Projects/claude-dotfiles/install.sh
#
# For subsequent updates (after `git pull`):
#   chezmoi apply        # if source dir is symlinked to this repo
#   chezmoi update       # if chezmoi has its own clone (default on macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$HOME/.local/share/chezmoi"

# 1. Install chezmoi if missing.
if ! command -v chezmoi >/dev/null 2>&1; then
    if [ -n "${DOTFILES_NO_NETWORK:-}" ]; then
        echo "install.sh: chezmoi is not installed and DOTFILES_NO_NETWORK is set; install it by hand:" >&2
        echo '    curl -fsLS https://get.chezmoi.io -o /tmp/chezmoi-install.sh && sh /tmp/chezmoi-install.sh -b ~/.local/bin' >&2
        exit 1
    fi
    echo "==> NETWORK: installing chezmoi from get.chezmoi.io into ~/.local/bin (set DOTFILES_NO_NETWORK=1 to skip)"
    # Download first: `sh -c "$(curl ...)"` runs an empty script and exits 0
    # when the download fails, and set -e does not see a failed substitution.
    installer="$(mktemp)"
    curl -fsLS https://get.chezmoi.io -o "$installer"
    BIN_DIR="$HOME/.local/bin" sh "$installer"
    rm -f "$installer"
    # The installer historically dropped the binary into ./bin/ when
    # BIN_DIR wasn't honored. Move it if so.
    if [ -x "$SCRIPT_DIR/bin/chezmoi" ] && [ ! -x "$HOME/.local/bin/chezmoi" ]; then
        mv "$SCRIPT_DIR/bin/chezmoi" "$HOME/.local/bin/chezmoi"
    fi
    export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Point chezmoi at this repo. Two flows:
#    a) source dir doesn't exist yet → symlink it to this checkout
#       (one source of truth; edits to repo are live without re-cloning)
#    b) source dir exists → assume already configured (chezmoi init or
#       a prior install.sh run)
# b) must point at THIS checkout: a source dir left by another clone or an
#    earlier `chezmoi init` would otherwise be applied instead, silently.
if [ -e "$SOURCE_DIR" ]; then
    here=$(cd "$SCRIPT_DIR" && pwd -P)
    there=$(cd "$SOURCE_DIR" 2>/dev/null && pwd -P)
    if [ "$here" != "$there" ]; then
        echo "install.sh: $SOURCE_DIR already exists and points at $there, not $here." >&2
        echo "  Move it aside or run 'chezmoi apply' against it directly; nothing was changed." >&2
        exit 1
    fi
fi
if [ ! -e "$SOURCE_DIR" ]; then
    echo "==> Linking chezmoi source dir to this repo..."
    mkdir -p "$(dirname "$SOURCE_DIR")"
    ln -s "$SCRIPT_DIR" "$SOURCE_DIR"
fi

# 3. Apply.
echo "==> Running chezmoi apply..."
chezmoi apply -v

# 4. Dependency floor for the agents' shared tooling (informational, not fatal).
#    The HARD dependencies — jq and git, without which chezmoi cannot render a
#    target — are enforced BEFORE anything is written, by
#    run_onchange_before_preflight-tools.sh. What follows is the floor for the
#    hooks: bash >= 4 and python3 >= 3.9. On macOS that is brew; on
#    Debian/Ubuntu/WSL, apt. On a locked-down box where you cannot install
#    packages, the templates still apply; the tools that need these simply
#    report themselves absent.
missing=()
bash_major=$(bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)
[ "${bash_major:-0}" -ge 4 ] || missing+=("bash>=4 (found $(bash --version | head -1))")
if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
        || missing+=("python3>=3.9 (found $(python3 --version 2>&1))")
else
    missing+=("python3>=3.9")
fi
if [ ${#missing[@]} -gt 0 ]; then
    echo
    echo "NOTE: below the tooling floor: ${missing[*]}"
    echo "      The dotfiles applied; tools that need these will say so when run."
fi

echo
echo "Done. Restart Claude Code to pick up settings/hooks changes."
