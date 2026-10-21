#!/usr/bin/env bash
# run_onchange: raise Codex's project_doc_max_bytes so ~/.codex/AGENTS.md is not
# silently truncated.
#
# THE BUG THIS FIXES (found 2026-08-24 while splitting AGENTS.core.md, 6uo):
# codex defaults project_doc_max_bytes to 32 KiB and truncates past it WITHOUT
# WARNING. dot_codex/AGENTS.md.tmpl flat-concatenates the portable core, any
# infrastructure doc, and hosts/<hostname>/host.md into one file; on one host that was
# 41393 bytes, so codex silently dropped the last ~4 KB. The dropped tail was
# the ENTIRE host doc — including two hard "never do this" rules about local
# daemons and SSH key selection. Codex had never seen either.
#
# The 6uo split cut the total to ~36.6 KB, which is still over. Rather than
# trimming to fit an arbitrary ceiling, raise the ceiling: the cost of a larger
# instruction file is tokens, and the cost of a truncated one is an agent acting
# on rules it cannot see.
#
# Same mechanism as the other Codex config scripts: codex rewrites
# ~/.codex/config.toml itself (appending [projects.*] trust entries), so chezmoi
# cannot own the file as a template. Inject a marker-delimited managed block.
# Idempotent and TOML-validated.
#
# This is run_onchange: chezmoi runs it again only when THIS SCRIPT changes, not
# on every apply. So it must not depend on Codex having run first. On a fresh
# machine there is no config.toml yet, and an earlier version
# skipped and never came back, leaving the 32 KiB default in place. It now
# creates the file, and Codex appends its own entries to it later.
#
# Verify after apply:
#   wc -c ~/.codex/AGENTS.md          # must be <= the cap below
#   grep -A2 'codex-doc-budget' ~/.codex/config.toml
set -euo pipefail

cfg="$HOME/.codex/config.toml"
if [[ ! -f "$cfg" ]]; then
  echo "ensure-codex-doc-budget: no $cfg yet — creating it so the cap is in place before Codex first runs"
  mkdir -p "$(dirname "$cfg")"
  : > "$cfg"
fi

# 64 KiB: double the default, ~27 KB of headroom over the current concatenation.
# If AGENTS.md ever approaches this, prefer moving content to an on-demand
# reference over raising it again.
cap=65536

begin="# >>> codex-doc-budget (managed by chezmoi) >>>"
end="# <<< codex-doc-budget (managed by chezmoi) <<<"

block="$begin
# project_doc_max_bytes defaults to 32768 and codex truncates AGENTS.md past it
# silently. Our concatenated AGENTS.md (portable core + infra doc + host doc)
# exceeds that, and the truncated tail is the host doc. See claude-dotfiles-6uo.
# Managed by chezmoi — hand edits inside these markers are reverted on apply.
project_doc_max_bytes = $cap
$end"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Base = config minus any existing managed block, trailing blanks trimmed so
# repeated runs converge.
if grep -qF "$begin" "$cfg"; then
  # Also swallow ONE blank line immediately after the end marker. The insert
  # step below writes `block` followed by a blank, so a strip that removed only
  # the marked lines left that blank behind and the next insert added another —
  # the file grew one blank line per run, forever, and `cmp` never converged so
  # every run reported "raised" and rewrote. Measured 2026-08-25. Only the
  # first following blank is eaten, so deliberate spacing further down survives.
  awk -v b="$begin" -v e="$end" '
    index($0, b) { skip = 1; next }
    skip && index($0, e) { skip = 0; eat = 1; next }
    eat { eat = 0; if ($0 == "") next }
    !skip { print }
  ' "$cfg"
else
  cat "$cfg"
fi | awk 'NF { last = NR } { line[NR] = $0 } END { for (i = 1; i <= last; i++) print line[i] }' > "$tmp"

# project_doc_max_bytes is a TOP-LEVEL key. A bare key appended after codex's
# existing [projects.*] tables would be parsed as belonging to the LAST table,
# not the root — so it must be inserted BEFORE the first table header, not
# appended. This is the one place this script differs from its siblings.
# $block is MULTI-LINE, so it must reach awk through the environment, not
# through -v. BSD awk (the macOS default) rejects a literal newline inside a
# -v assignment with "awk: newline in string" and exits non-zero; only GNU awk
# accepts it. Measured 2026-08-25 on macOS: this script failed on every run on
# the very host it was written for. It failed CLOSED (set -e aborted before
# the write, leaving config.toml untouched), so the symptom was a silent no-op
# rather than a corrupt config — which is why nobody noticed. ENVIRON is POSIX
# and behaves identically on both awks.
{
  BLK="$block" awk '
    !done && /^[[:space:]]*\[/ { print ENVIRON["BLK"]; print ""; done = 1 }
    { print }
    END { if (!done) { print ""; print ENVIRON["BLK"] } }
  ' "$tmp"
} > "$tmp.new"
mv "$tmp.new" "$tmp"

# Never hand codex a broken config: validate it parses and the key landed at the
# ROOT (not nested inside a table) before touching the live file.
# tomllib is Python 3.11+; stock Ubuntu 22.04 (WSL) ships 3.10. Fall back to
# tomli, and if neither is present skip the raise rather than write a config we
# cannot validate (exit 3). Skipping leaves Codex on its 32 KiB default, which
# is safe while ~/.codex/AGENTS.md stays under it.
rc=0
python3 - "$tmp" "$cap" <<'PY' || rc=$?
import sys
try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        sys.exit(3)
d = tomllib.load(open(sys.argv[1], "rb"))
want = int(sys.argv[2])
got = d.get("project_doc_max_bytes")
assert got == want, f"project_doc_max_bytes is {got!r} at root, want {want}"
PY
if [ "$rc" -eq 3 ]; then
  echo "ensure-codex-doc-budget: SKIPPED — no TOML parser (need python3 >= 3.11 or the tomli package); Codex keeps its default cap" >&2
  exit 0
elif [ "$rc" -ne 0 ]; then
  echo "ensure-codex-doc-budget: refusing to write — result invalid or key missing" >&2
  exit 1
fi

if cmp -s "$tmp" "$cfg"; then
  echo "ensure-codex-doc-budget: $cfg already current"
  exit 0
fi

[[ -f "$cfg.pre-doc-budget.bak" ]] || cp "$cfg" "$cfg.pre-doc-budget.bak"
mv "$tmp" "$cfg"
echo "ensure-codex-doc-budget: raised project_doc_max_bytes to $cap in $cfg"
