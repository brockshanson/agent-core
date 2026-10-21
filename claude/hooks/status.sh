#!/usr/bin/env bash
# Claude Code StatusLine v2
# Line 1: user@host:~/path version | branch | beads
# Line 2: context bar | rate limits (with countdown) | session duration
#
# Reads JSON session data from stdin (Claude Code pipes this automatically).
# Caches git/beads operations to /tmp (5s TTL) for performance.

# --- ANSI colors ---
#
# Plain ANSI (30-37), deliberately NOT bold-bright (01;3x), and deliberately
# no SGR 2. Both of those were wrong here, for different reasons:
#
#   01;3x  With bold_brightens_ansi_colors (WezTerm's default) bold promotes
#          these to the BRIGHT slots — and in both Flexoki schemes brights
#          1-6 are the same 400-series values (#d14d41, #879a39, #d0a215,
#          #4385be, #ce5d97, #3aa99f). So bold pinned the dark-mode colours
#          into light mode too: yellow-400 on paper is ~2.2:1. The plain
#          slots are the ones that actually switch (400-series on dark,
#          600-series on light), so dropping bold is what makes the status
#          line follow the system appearance. On dark it costs nothing —
#          there, ansi[n] and bright[n] are identical.
#
#   SGR 2  The terminal renders faint by halving the foreground, which on a
#          dark background drops these segments to ~2.7:1. Same defect that
#          made Claude Code's AskUserQuestion descriptions unreadable (see
#          the Theming section in CLAUDE.md). MUTED replaces it with an
#          explicit tone instead.
#
# MUTED is the one truecolour value here: Flexoki base-500, the neutral that
# sits legibly on both ends of the base ramp (4.67:1 on #1c1b1a, 3.59:1 on
# #fffcf0) where no ANSI slot does — ansi[7] and bright[0] each collapse on
# one background or the other. Terminals without truecolour degrade to their
# nearest colour, not to invisible, which is what SGR 2 effectively was.
#
# It reads as the same tone as `subtle` in the Claude Code theme without being
# the same hex: that one is base-400 because the TUI dims it and this one is
# not dimmed. Matching rendered output, not matching values, is the point —
# keep them one ramp step apart if either side moves.
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MUTED='\033[38;2;135;133;128m'
RESET='\033[00m'

# --- Read JSON from stdin ---
INPUT=$(cat)

# --- Extract all fields in ONE jq pass (fast path) ---
# One jq invocation emits all fields, one per line, read into an array.
# Replaces 9 separate `echo | jq` calls (18 forks) with a single process.
# Empty string (// "") preserves the "absent" semantics the rate-limit
# branches below rely on; floor replicates the old `cut -d. -f1` truncation.
# NB: a `while read` loop, not `mapfile` — macOS /bin/bash is 3.2 (no mapfile),
# and Claude Code execs this via the #!/bin/bash shebang, not $PATH bash.
_F=()
while IFS= read -r _line; do _F+=("$_line"); done < <(printf '%s' "$INPUT" | jq -r '
  (.model.display_name // "?"),
  (.workspace.current_dir // ""),
  (.cost.total_cost_usd // 0),
  (.cost.total_duration_ms // 0),
  (.context_window.used_percentage // 0 | floor),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  (.context_window.total_input_tokens // 0),
  (.context_window.context_window_size // 0),
  (.effort.level // ""),
  (.exceeds_200k_tokens // false)')
MODEL=${_F[0]}
CWD_RAW=${_F[1]}
COST=${_F[2]}
DURATION_MS=${_F[3]}
CTX_PCT=${_F[4]}
RL_5H_PCT=${_F[5]}
RL_5H_RESETS=${_F[6]}
RL_7D_PCT=${_F[7]}
RL_7D_RESETS=${_F[8]}
CTX_USED_TOK=${_F[9]}
CTX_SIZE_TOK=${_F[10]}
EFFORT=${_F[11]}
EXCEEDS_200K=${_F[12]}

# --- Helpers ---

# Threshold color: green <60%, yellow 60-79%, red ≥80%
threshold_color() {
    local val=$1
    if [ "$val" -ge 80 ]; then echo "$RED"
    elif [ "$val" -ge 60 ]; then echo "$YELLOW"
    else echo "$GREEN"
    fi
}

# Humanize a token count: 60960 -> 61k, 1000000 -> 1M, 200000 -> 200k
humanize_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        local m=$((n / 1000000))
        local frac=$(((n % 1000000) / 100000))
        if [ "$frac" -eq 0 ]; then echo "${m}M"; else echo "${m}.${frac}M"; fi
    elif [ "$n" -ge 1000 ]; then
        echo "$(((n + 500) / 1000))k"
    else
        echo "$n"
    fi
}

# Format milliseconds to Xm Ys
format_duration_ms() {
    local ms=$1
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    local rem_secs=$((secs % 60))
    if [ "$mins" -gt 0 ]; then
        echo "${mins}m ${rem_secs}s"
    else
        echo "${rem_secs}s"
    fi
}

# Format seconds remaining to Xh Ym or Xm
format_countdown() {
    local remaining=$1
    if [ "$remaining" -le 0 ]; then echo "now"; return; fi
    local days=$((remaining / 86400))
    local hours=$(((remaining % 86400) / 3600))
    local mins=$(((remaining % 3600) / 60))
    if [ "$days" -gt 0 ]; then
        echo "${days}d${hours}h"
    elif [ "$hours" -gt 0 ]; then
        if [ "$mins" -gt 0 ]; then
            echo "${hours}h${mins}m"
        else
            echo "${hours}h"
        fi
    else
        echo "${mins}m"
    fi
}

# --- Tilde-contracted CWD ---
# Resolve symlinks: ~/Projects -> /mnt/docker-data/projects
# Try $HOME first, then resolve any symlinked dirs under $HOME
if [ -n "$CWD_RAW" ]; then
    CWD_DISPLAY="$CWD_RAW"
else
    CWD_DISPLAY="$(pwd)"
fi
# Direct $HOME match (e.g., /home/you/foo -> ~/foo)
#
# The replacement MUST come from a variable. Neither literal form is portable,
# and each fails on exactly the half of the machines the other one works on:
#
#   ${v/#$HOME/~}    bash 5.2+ DOES tilde-expand the replacement, so `~`
#                    becomes $HOME and the substitution is a silent no-op —
#                    the status line shows the full absolute path. Fine where
#                    /bin/bash is 3.2 (macOS), broken where it is 5.2 (Linux).
#   ${v/#$HOME/\~}   bash 3.2 keeps the backslash literally, printing `\~/…`.
#
# $TILDE dodges both: tilde expansion runs before parameter expansion and only
# on an unquoted literal ~, so the value is substituted verbatim everywhere.
# Verified against 3.2.57 and 5.3.9. Don't "simplify" this back to a literal.
TILDE='~'
CWD_DISPLAY="${CWD_DISPLAY/#$HOME/$TILDE}"
# Symlink target match (e.g., /mnt/docker-data/projects -> ~/Projects)
if [[ "$CWD_DISPLAY" != "~"* ]]; then
    for link in "$HOME"/*/; do
        [ -L "${link%/}" ] || continue
        target=$(readlink -f "${link%/}")
        if [[ "$CWD_DISPLAY" == "$target"* ]]; then
            rel="${link%/}"
            CWD_DISPLAY="~${rel#$HOME}${CWD_DISPLAY#$target}"
            break
        fi
    done
fi

# --- Git info (cached, 5s TTL, keyed per-repo) ---
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr '/' '_')
# Namespace cache paths per-user — /tmp is world-writable and shared on multi-user
# hosts; an un-namespaced predictable path lets another user poison/pre-create it
# (claude-dotfiles-h83).
CACHE_FILE="/tmp/statusline-git-cache-${USER:-nouser}${REPO_ROOT}"
CACHE_MAX_AGE=5

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

GIT_BRANCH=""
GIT_DIRTY=""
GIT_TAG=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
    if cache_is_stale; then
        _branch=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
        _dirty=""
        [[ -n $(git status --porcelain 2>/dev/null) ]] && _dirty="*"
        _tag=$(git describe --tags 2>/dev/null || echo "")
        # Unit-separator delimiter (0x1f) — git refs cannot contain control chars,
        # so a branch/tag with a literal '|' can't corrupt the parse (claude-dotfiles-1yq).
        printf '%s\x1f%s\x1f%s\n' "$_branch" "$_dirty" "$_tag" > "$CACHE_FILE"
    fi
    IFS=$'\x1f' read -r GIT_BRANCH GIT_DIRTY GIT_TAG < "$CACHE_FILE"
fi

# --- Beads info (cached alongside git, same TTL, keyed per-repo) ---
BEADS_CACHE="/tmp/statusline-beads-cache-${USER:-nouser}${REPO_ROOT}"
BEADS_COUNT=0
if [[ -d ".beads" ]] && command -v bd &>/dev/null; then
    if [ ! -f "$BEADS_CACHE" ] || [ $(($(date +%s) - $(stat -c %Y "$BEADS_CACHE" 2>/dev/null || stat -f %m "$BEADS_CACHE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]; then
        # grep -c always prints a count (0 on no match); the old '|| echo 0' double-printed
        # to "0\n0" → "00" after whitespace strip (claude-dotfiles-bzb).
        _count=$(bd list --status=in_progress 2>/dev/null | grep -c "^◐")
        echo "$_count" > "$BEADS_CACHE"
    fi
    BEADS_COUNT=$(tr -d '[:space:]' < "$BEADS_CACHE")
fi

# =============================================
# LINE 1: identity, project, version, branch, beads
# =============================================

# Identity from shell builtins (no whoami/hostname forks); fall back if unset.
_HN=${HOSTNAME%%.*}; [ -n "$_HN" ] || _HN=$(hostname -s)
L1="${GREEN}${USER:-$(whoami)}@${_HN}${RESET}"
L1="${L1}:${BLUE}${CWD_DISPLAY}${RESET}"

# Version tag with distance (dim — reference info)
# git describe outputs: v1.0.0-47-gabcdef → show "v1.0.0+47", exact tag → show "v1.0.0"
if [ -n "$GIT_TAG" ]; then
    if [[ "$GIT_TAG" =~ ^(.*)-([0-9]+)-g[0-9a-f]+$ ]]; then
        TAG_NAME="${BASH_REMATCH[1]}"
        TAG_DIST="${BASH_REMATCH[2]}"
        L1="${L1} ${MUTED}${TAG_NAME}+${TAG_DIST}${RESET}"
    else
        L1="${L1} ${MUTED}${GIT_TAG}${RESET}"
    fi
fi

# Branch (cyan clean, yellow dirty)
if [ -n "$GIT_BRANCH" ]; then
    if [ -n "$GIT_DIRTY" ]; then
        L1="${L1} ${YELLOW}${GIT_BRANCH}${GIT_DIRTY}${RESET}"
    else
        L1="${L1} ${CYAN}${GIT_BRANCH}${RESET}"
    fi
fi

# Beads active count
if [ "$BEADS_COUNT" -gt 0 ]; then
    L1="${L1} ${CYAN}${BEADS_COUNT} active${RESET}"
fi

# Reasoning effort badge (absent when the model doesn't expose effort.level)
if [ -n "$EFFORT" ]; then
    L1="${L1} ${CYAN}⚡${EFFORT}${RESET}"
fi

# =============================================
# LINE 2: context bar | rate limits | duration
# =============================================

# Context bar (10 chars)
CTX_COLOR=$(threshold_color "$CTX_PCT")
# Past the fixed 200k threshold the 1M-window percentage stays low (and green),
# so escalate the bar to at least amber as an absolute "past the old limit" warning.
if [ "$EXCEEDS_200K" = "true" ] && [ "$CTX_COLOR" = "$GREEN" ]; then
    CTX_COLOR=$YELLOW
fi
BAR_WIDTH=10
# Clamp the bar fill to 100% so a >100 CTX_PCT can't overflow BAR_WIDTH and break
# statusline alignment; the displayed percentage below stays the true value (claude-dotfiles-9t1).
BAR_PCT=$CTX_PCT
[ "$BAR_PCT" -gt 100 ] && BAR_PCT=100
FILLED=$((BAR_PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /█}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /░}"

CTX_USED_H=$(humanize_tokens "$CTX_USED_TOK")
CTX_SIZE_H=$(humanize_tokens "$CTX_SIZE_TOK")
L2="${CTX_COLOR}${BAR}${RESET} ${CTX_PCT}% ${MUTED}· ${CTX_USED_H}/${CTX_SIZE_H}${RESET} ctx"

# Mini bar builder: mini_bar <pct> <width>
# Returns filled/empty bar string (no color — caller wraps)
mini_bar() {
    local pct=$1 width=${2:-5}
    [ "$pct" -gt 100 ] && pct=100   # same overflow guard as the context bar (claude-dotfiles-9t1)
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""
    [ "$filled" -gt 0 ] && printf -v _f "%${filled}s" && bar="${_f// /█}"
    [ "$empty" -gt 0 ] && printf -v _e "%${empty}s" && bar="${bar}${_e// /░}"
    echo "$bar"
}

# Rate limits (only shown if data available)
NOW=$(date +%s)

if [ -n "$RL_5H_PCT" ]; then
    RL_5H_INT=$(printf '%.0f' "$RL_5H_PCT")
    RL_5H_COLOR=$(threshold_color "$RL_5H_INT")
    RL_5H_BAR=$(mini_bar "$RL_5H_INT" 5)
    L2="${L2} | 5h ${RL_5H_COLOR}${RL_5H_BAR}${RESET} ${RL_5H_INT}%"
    # Only compute the countdown if resets_at is a Unix epoch integer; an ISO-8601
    # string would break $(()) and (without set -e) fall through to a false "now"
    # (claude-dotfiles-gcn). Non-numeric → omit the countdown entirely.
    if [ -n "$RL_5H_RESETS" ] && [[ "$RL_5H_RESETS" =~ ^[0-9]+$ ]] && [ "$RL_5H_INT" -ge 70 ]; then
        REMAINING=$((RL_5H_RESETS - NOW))
        L2="${L2} ${YELLOW}($(format_countdown $REMAINING))${RESET}"
    fi
fi

if [ -n "$RL_7D_PCT" ]; then
    RL_7D_INT=$(printf '%.0f' "$RL_7D_PCT")
    RL_7D_COLOR=$(threshold_color "$RL_7D_INT")
    RL_7D_BAR=$(mini_bar "$RL_7D_INT" 5)
    L2="${L2} | 7d ${RL_7D_COLOR}${RL_7D_BAR}${RESET} ${RL_7D_INT}%"
    if [ -n "$RL_7D_RESETS" ] && [[ "$RL_7D_RESETS" =~ ^[0-9]+$ ]] && [ "$RL_7D_INT" -ge 70 ]; then
        REMAINING=$((RL_7D_RESETS - NOW))
        L2="${L2} ${YELLOW}($(format_countdown $REMAINING))${RESET}"
    fi
fi

# Session duration (dim — passive reference)
DURATION_FMT=$(format_duration_ms "$DURATION_MS")
L2="${L2} | ${MUTED}${DURATION_FMT}${RESET}"

# --- Output ---
printf '%b\n' "$L1"
printf '%b' "$L2"
