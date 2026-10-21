#!/usr/bin/env bash
# install-paths.sh — apply this repo in a clean Ubuntu 24.04 container, several
# ways, and fail on anything a second apply would still change.
#
# WHY
#
# Every install defect this repo has shipped so far passed a single apply on a
# single machine and failed on the second: a run_once_ script that skipped
# offline and so never ran again, an install-state key that left `chezmoi
# verify` at rc=1 until another apply, a first apply that replaced an existing
# machine's own setup. Each was found by hand, once. This runs the paths
# that found them, every time, and asserts the same three things after every
# apply: apply rc=0, verify rc=0, and `chezmoi status` empty.
#
# SCENARIOS (run all by default, or name them)
#
#   online          one networked apply on a fresh box with tmux.
#   offline-online  DOTFILES_NO_NETWORK=1 apply first, then a networked one.
#                   TPM must be absent after the first and present after the
#                   second.
#   tmux-later      apply with tmux absent, install tmux, apply again. TPM must
#                   arrive on the second apply.
#   upgrade         HOME seeded like an existing machine (git identity and
#                   CA in ~/.gitconfig, mise activated from the rc files, a
#                   mise-installed tool, a hand-written ~/.tmux.conf), then the
#                   setup guide's steps 1 and 3 as written. Nothing seeded may
#                   end up neither effective nor in the step-3 backup.
#   undo            the upgrade, then the guide's restore steps in reverse
#                   order; HOME is diffed against a snapshot taken before
#                   step 1. The diff is printed; paths it does not expect fail.
#
# The log check (session logs land outside the repo) runs in `online`.
#
# USAGE
#     .github/scripts/install-paths.sh [--tree DIR] [scenario ...]
#         Host mode. Builds the test image, then runs each scenario in its own
#         container against DIR (default: this repo), which must be a git
#         checkout. Needs docker.
#     install-paths.sh --inside <scenario>
#         Container mode; the host mode calls this. Not for direct use.
#
# Exit: 0 every scenario passed; 1 any assertion failed; 2 bad usage.
#
# Placeholders only: every seeded name, address and path below is invented.

set -uo pipefail

IMAGE=portable-core-install-test:ubuntu-24.04
ALL=(online offline-online tmux-later upgrade undo)

# =============================================================================
# HOST MODE
# =============================================================================
host_main() {
  local tree scenarios=() failed=() s
  tree=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)
  while [ $# -gt 0 ]; do
    case "$1" in
      --tree)   shift; tree=${1:?--tree needs a directory} ;;
      --tree=*) tree=${1#--tree=} ;;
      -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
      -*) echo "install-paths: unknown option $1" >&2; exit 2 ;;
      *) scenarios+=("$1") ;;
    esac
    shift
  done
  [ ${#scenarios[@]} -gt 0 ] || scenarios=("${ALL[@]}")
  for s in "${scenarios[@]}"; do
    case " ${ALL[*]} " in *" $s "*) ;; *) echo "install-paths: no scenario '$s' (have: ${ALL[*]})" >&2; exit 2 ;; esac
  done
  tree=$(cd "$tree" && pwd) || exit 2
  git -C "$tree" rev-parse HEAD >/dev/null 2>&1 || { echo "install-paths: $tree is not a git checkout" >&2; exit 2; }
  # chezmoi init clones HEAD, so an uncommitted edit would silently not be tested.
  if [ -n "$(git -C "$tree" status --porcelain --untracked-files=no)" ]; then
    echo "install-paths: $tree has uncommitted changes; the test clones HEAD ($(git -C "$tree" rev-parse --short HEAD)) and would not see them" >&2
  fi

  command -v docker >/dev/null || { echo "install-paths: docker not found" >&2; exit 2; }
  echo "── building $IMAGE"
  # The image is the machine the setup guide's prerequisites describe: Ubuntu
  # 24.04 with the guide's apt line (jq, git, tmux, python3, zsh) plus what a
  # real WSL box already has (a non-root sudo user, curl, CA certs), and chezmoi.
  # Keep the package list equal to the guide's: an extra package here hides a
  # missing one there (zsh was, until 2026-09-29).
  # and mise binaries parked OUTSIDE $HOME. Nothing is installed into the user's
  # home here: each scenario decides what HOME looks like.
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { echo "install-paths: image build failed" >&2; exit 1; }
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends jq git tmux python3 zsh sudo curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/opt/mise/mise sh
RUN useradd -m -s /bin/bash dev && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
USER dev
WORKDIR /home/dev
DOCKERFILE

  for s in "${scenarios[@]}"; do
    echo
    echo "══ scenario: $s"
    if docker run --rm --hostname new-machine -v "$tree":/src:ro "$IMAGE" \
         bash /src/.github/scripts/install-paths.sh --inside "$s"; then
      echo "══ $s: PASS"
    else
      echo "══ $s: FAIL"; failed+=("$s")
    fi
  done

  echo
  if [ ${#failed[@]} -eq 0 ]; then
    echo "✓ install-paths: ${#scenarios[@]} scenario(s) passed"
  else
    echo "✗ install-paths: failed: ${failed[*]}"; exit 1
  fi
}

# =============================================================================
# CONTAINER MODE
# =============================================================================
FINDINGS=0
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; FINDINGS=$((FINDINGS + 1)); }
step() { echo "── $*"; }

# The repo under test, as the guide's `chezmoi init <REPO-URL>` would see it.
# Copied first so the clone is owned by this user (git refuses a repo owned by
# another uid, and the mount is owned by whoever ran docker).
init_repo() {
  cp -a /src /tmp/src
  step "chezmoi init"
  chezmoi init --no-tty "file:///tmp/src" </dev/null >/tmp/init.log 2>&1 \
    || { cat /tmp/init.log; fail "chezmoi init rc=$?"; return 1; }
}

# apply, verify, status. $1 is a label; remaining args are env assignments for
# all three (DOTFILES_NO_NETWORK=1 for an offline apply: the guide says to
# verify with the same prefix).
apply_and_check() {
  local label=$1; shift
  local rc out
  step "apply ($label)"
  env "$@" chezmoi apply -v --no-tty </dev/null >"/tmp/apply-$label.log" 2>&1
  rc=$?
  grep -E '^install-tpm:|^link-resurrect|^preflight' "/tmp/apply-$label.log" | sed 's/^/    | /'
  [ "$rc" -eq 0 ] && pass "apply rc=0" || { fail "apply rc=$rc"; tail -25 "/tmp/apply-$label.log" | sed 's/^/    /'; }
  out=$(env "$@" chezmoi verify --no-tty </dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] && pass "verify rc=0" || { fail "verify rc=$rc"; printf '%s\n' "$out" | head -10 | sed 's/^/    /'; }
  out=$(env "$@" chezmoi status --no-tty </dev/null 2>&1)
  [ -z "$out" ] && pass "status empty" || { fail "status not empty:"; printf '%s\n' "$out" | head -20 | sed 's/^/    /'; }
  # verify and status are both clean when chezmoi manages NOTHING (source
  # dir gone), so they cannot prove the setup is intact on their own. The
  # floor is well under the real count (86 on 2026-09-29) and far above zero.
  local n; n=$(chezmoi managed --no-tty </dev/null 2>/dev/null | wc -l)
  [ "$n" -ge 60 ] && pass "chezmoi manages $n targets (floor 60)" || fail "chezmoi manages only $n targets (floor 60)"
}

tpm_present() { [ -f "$HOME/.tmux/plugins/tpm/tpm" ]; }

# --- log check ---------------------------------------------------------------
# The guide's step 4: session logs go to ~/.local/state/claude-logs and never
# into the repo the session ran in. Drive the logging hooks directly with a
# hook payload, from inside a scratch repo, the way Claude Code invokes them.
check_logs() {
  step "session logs stay out of the repo"
  local repo=/tmp/scratch-repo
  git init -q "$repo"
  local payload
  payload=$(jq -nc --arg cwd "$repo" '{session_id:"install-test",transcript_path:"/dev/null",cwd:$cwd,
    hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"true"},tool_response:{}}')
  ( cd "$repo" && printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$repo" python3 "$HOME/.claude/hooks/logger/log_tool.py" ) >/tmp/log-hook.out 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] && pass "logging hook rc=0" || { fail "logging hook rc=$rc"; head -5 /tmp/log-hook.out | sed 's/^/    /'; }
  # Positive control first: a null "no .claude-logs in the repo" means nothing
  # unless the hook wrote somewhere.
  if [ -n "$(find "$HOME/.local/state/claude-logs" -type f 2>/dev/null | head -1)" ]; then
    pass "hook wrote under ~/.local/state/claude-logs"
  else
    fail "nothing under ~/.local/state/claude-logs (positive control: the hook logged nowhere expected)"
  fi
  if [ -e "$repo/.claude-logs" ]; then
    fail "hook wrote $repo/.claude-logs (a transcript one \`git add -A\` from a commit)"
    git -C "$repo" status --porcelain | grep -q claude-logs \
      && fail "…and git would stage it" || pass "…but the global ignore hides it from git"
  else
    pass "no .claude-logs in the repo"
  fi
}

# --- seeded existing-machine HOME -------------------------------------------------
# Placeholder values throughout. The shape is what matters: identity and a CA
# path set by hand in ~/.gitconfig, mise activated from all three rc files as
# `mise activate` tells you to, a tool installed through mise, and a
# ~/.tmux.conf someone wrote.
seed_home() {
  step "seed HOME like an existing machine"
  mkdir -p "$HOME/.local/bin"
  cp /opt/mise/mise "$HOME/.local/bin/mise"          # where mise.run puts it
  # The CA path is deliberately NOT the system bundle, so a guide that writes a
  # fixed path instead of carrying the existing one is caught. It is a real
  # copy of the bundle so the apply's own HTTPS clones still verify.
  mkdir -p "$HOME/.certs"
  cp /etc/ssl/certs/ca-certificates.crt "$HOME/.certs/example-bundle.pem"
  cat > "$HOME/.gitconfig" <<EOF
[user]
	name = Pat Example
	email = pat.example@example.invalid
[http]
	sslCAInfo = $HOME/.certs/example-bundle.pem
[core]
	editor = vi
[alias]
	st = status --short
EOF
  # Ubuntu's stock .bashrc/.profile with the mise line appended, as mise's
  # install docs have you do.
  cp /etc/skel/.bashrc "$HOME/.bashrc"
  cp /etc/skel/.profile "$HOME/.profile"
  printf '\n# seeded\nexport SEED_BASHRC=1\neval "$(~/.local/bin/mise activate bash)"\n' >> "$HOME/.bashrc"
  printf '\n# seeded\nexport SEED_PROFILE=1\nexport PATH="$HOME/.local/bin:$PATH"\neval "$(~/.local/bin/mise activate bash --shims)"\n' >> "$HOME/.profile"
  printf '# seeded\nexport SEED_ZSHRC=1\neval "$(~/.local/bin/mise activate zsh)"\n' > "$HOME/.zshrc"
  printf '# seeded\nset -g prefix C-b\nset -g history-limit 12345\n' > "$HOME/.tmux.conf"
  # git's global excludes, which the apply edits in place rather than replaces.
  # No trailing newline, which is how an editor-less `echo -n >>` leaves it.
  mkdir -p "$HOME/.config/git"
  printf '# seeded\n*.swp\n.envrc.private' > "$HOME/.config/git/ignore"
  # An existing Claude Code settings file: a hook another tool installed, and
  # two choices made on the machine. The apply merges into it; none of the
  # three may be lost (portable-core red team, 2026-09-29).
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/seeded-guard"}]}]},
 "cleanupPeriodDays":14,"showThinkingSummaries":false,"permissions":{"allow":["Bash(ls:*)"]}}
JSON
  "$HOME/.local/bin/mise" use -g -y ripgrep >/tmp/mise.log 2>&1 \
    || { tail -5 /tmp/mise.log; fail "seed: mise could not install ripgrep"; return 1; }
  bash -lc 'command -v rg' | grep -q mise && pass "seed: rg from mise on PATH in a login shell" \
    || fail "seed: rg not from mise before the apply"
}

# The guide's step 1 (docs/setup-guide/README.md), verbatim. The guide is the
# thing under test: change it there first, then mirror it here.
guide_step1() {
  step "guide step 1: move machine settings to the local files"
  mkdir -p ~/.config/git
  f=~/.config/git/local
  [ -e "$f" ] || { [ -e ~/.gitconfig ] && cp -a ~/.gitconfig "$f" || { : > "$f"; touch ~/.config/git/.from-scratch; }; }
  git config --file "$f" user.useConfigOnly true
  guide_step1_profile
  git config --file "$f" --get user.email >/dev/null || {
    git config --file "$f" user.name  "Your Name"
    git config --file "$f" user.email "you@example.com"
  }
  # "Copy the lines worth keeping, minus mise activation, into ~/.shellrc.local"
  # -- the hand-picked part, done the way a reader would.
  [ -e ~/.bashrc ] && diff /etc/skel/.bashrc ~/.bashrc | sed -n 's/^> //p' | grep -v 'mise' | grep -v '^#' > ~/.shellrc.local
  mkdir -p ~/.config/tmux
  [ -e ~/.tmux.conf ] && [ ! -e ~/.config/tmux/local.conf ] && cp ~/.tmux.conf ~/.config/tmux/local.conf
}

# Step 1's mise removal from ~/.profile, verbatim.
guide_step1_profile() {
  if [ -e ~/.profile ]; then
    [ -e ~/.profile.pre-portable-core ] || cp -a ~/.profile ~/.profile.pre-portable-core
    sed -i -E '/^[[:space:]]*eval[[:space:]].*mise[[:space:]]+activate/d' ~/.profile
    bash -n ~/.profile || { cp -a ~/.profile.pre-portable-core ~/.profile; echo "STOP: edit ~/.profile by hand"; }
  fi
}

# The guide's step 3 backup and restore, verbatim.
BACKUP=$HOME/pre-portable-core
guide_step3_backup() {
  step "guide step 3: back up everything the apply writes over"
  b=$BACKUP
  ls -d ~/pre-portable-core* >/dev/null 2>&1 && { echo "STOP: a backup already exists ($(ls -d ~/pre-portable-core* | head -1)); keep it, and do not re-run this backup"; return 0; }
  mkdir -p "$b"
  cd ~
  { chezmoi managed --include=files,symlinks
    printf '%s\n' .codex/config.toml .codex/config.toml.pre-doc-budget.bak \
      .tmux/plugins .local/share/zinit .config/zsh-abbr .zcompdump
  } > "$b.paths"
  while IFS= read -r p; do
    if [ -e "$p" ] || [ -L "$p" ]; then cp -a --parents -- "$p" "$b/"; fi
  done < "$b.paths"
  chezmoi managed --include=dirs \
    | while IFS= read -r d; do [ -d "$d" ] || printf '%s\n' "$d"; done > "$b.newdirs"
  cd - >/dev/null
}
# The guide's Updating step, from after the reset to before the apply, verbatim.
guide_update_backup() {
  step "guide Updating: extend the backup to what the release adds"
  b=$BACKUP
  ( set -e
    [ -s "$b.paths" ] && [ -d "$b" ] \
      || { echo "no backup at $b: the undo will not cover this update"; exit 0; }
    cd ~
    chezmoi managed --include=files,symlinks | grep -vxF -f "$b.paths" \
      | while IFS= read -r p; do
          printf '%s\n' "$p" >> "$b.paths"
          if [ -e "$p" ] || [ -L "$p" ]; then cp -a --parents -- "$p" "$b/"; fi
        done
    chezmoi managed --include=dirs \
      | while IFS= read -r d; do [ -d "$d" ] || printf '%s\n' "$d"; done >> "$b.newdirs"
  ) || fail "guide Updating backup rc=$?"
}
guide_step3_restore() {
  step "guide step 3 restore"
  # The guide's guard, first against a wrong backup path: it must stop before
  # chezmoi purge (an unedited <date> placeholder would otherwise purge anyway).
  local rc=0
  ( b=~/pre-portable-core-DOES-NOT-EXIST; set -e
    [ -s "$b.paths" ] && [ -d "$b" ] || exit 1
    chezmoi purge --force --no-tty </dev/null ) || rc=$?
  [ "$rc" -ne 0 ] && [ -d "$(chezmoi source-path)" ] \
    && pass "restore guard stops on a missing backup; chezmoi source intact" \
    || fail "restore guard let a missing backup through"
  b=$BACKUP
  ( set -e
    [ -s "$b.paths" ] && [ -d "$b" ] || { echo "no backup at $b"; exit 1; }
    cd ~
    xargs -d '\n' rm -rf -- < "$b.paths"
    cp -a "$b"/. ~/
    rm -f ~/.local/state/agent-core-apply.log
    sort -r "$b.newdirs" | xargs -r -d '\n' rmdir --ignore-fail-on-non-empty --
    chezmoi purge --force --no-tty </dev/null
    rm -f ~/.local/bin/chezmoi
  ) || fail "guide step 3 restore rc=$?"
}
# The guide's step 1 restore guard: true when ~/.config/git/local is not the
# only live copy of the git settings.
step1_restore_safe() {
  [ -e ~/.config/git/.from-scratch ] || { [ -f ~/.gitconfig ] && ! git config --file ~/.gitconfig --get-all include.path | grep -qxF '~/.config/git/local'; }
}
guide_step1_restore() {
  step "guide step 1 restore"
  if step1_restore_safe; then
    rm -f ~/.config/git/local ~/.config/git/.from-scratch ~/.config/tmux/local.conf
    rmdir ~/.config/git ~/.config/tmux 2>/dev/null || true
  else
    fail "~/.gitconfig is still the managed one; restore step 3's backup first"
  fi
  [ -e ~/.profile.pre-portable-core ] && mv ~/.profile.pre-portable-core ~/.profile
  rm -f ~/.shellrc.local          # "Remove by hand any lines you added"
}

# What in the seeded HOME must survive the apply, and how.
check_upgrade() {
  step "nothing seeded is lost"
  local k want got origin
  for k in user.name user.email http.sslCAInfo; do
    want=$(git config --file "$BACKUP/.gitconfig" "$k")
    got=$(git config --get "$k"); origin=$(git config --show-origin --get "$k" | cut -f1)
    [ "$got" = "$want" ] && pass "git $k effective (from ${origin#file:})" || fail "git $k is '$got', was '$want'"
  done
  # Keys the guide does not name are the ones at risk.
  got=$(git config --get core.editor)
  [ "$got" = vi ] && pass "git core.editor effective" || fail "git core.editor is '$got', seeded 'vi'"
  got=$(git config --get alias.st)
  [ "$got" = "status --short" ] && pass "git alias.st effective" || fail "git alias.st is '$got'"

  got=$(bash -lc 'command -v rg')
  case "$got" in *mise/installs/*) pass "agent login shell: rg from mise's install dir, not a shim ($got)" ;; *) fail "agent login shell: rg is '$got', not under mise/installs" ;; esac
  got=$(bash -lc 'type -t cd'); [ "$got" = builtin ] && pass "agent login shell: cd is a builtin" || fail "agent login shell: cd is a $got"
  got=$(bash -lc 'echo "${SEED_PROFILE:-}"'); [ "$got" = 1 ] && pass "~/.profile still read by login bash" || fail "~/.profile no longer read by login bash"
  # Step 1 removes only the mise activation lines, and keeps the original.
  grep -v 'mise activate' /tmp/profile.before | cmp -s - "$HOME/.profile" \
    && pass "~/.profile unchanged except its mise activation line" || fail "~/.profile changed beyond the mise line"
  cmp -s /tmp/profile.before "$HOME/.profile.pre-portable-core" && pass "~/.profile original kept as ~/.profile.pre-portable-core" \
    || fail "~/.profile original not kept"
  # zsh: interactive, offline so the first launch does not clone zinit.
  got=$(DOTFILES_NO_NETWORK=1 zsh -ic 'command -v rg' 2>/dev/null | tail -1)
  case "$got" in *mise/installs/*) pass "human zsh: rg from mise's install dir, not a shim ($got)" ;; *) fail "human zsh: rg is '$got', not under mise/installs" ;; esac
  got=$(DOTFILES_NO_NETWORK=1 zsh -ic 'whence -w cd' 2>/dev/null | tail -1)
  [ "$got" = "cd: builtin" ] && pass "human zsh: cd is a builtin" || fail "human zsh: cd is '$got'"

  # Replaced wholesale, so their own lines stop being effective. Acceptable only
  # if the backup holds them byte for byte.
  for f in .bashrc .zshrc .gitconfig .tmux.conf .config/git/ignore; do
    if cmp -s "/tmp/seed/$f" "$BACKUP/$f"; then pass "~/$f original in the backup"
    else fail "~/$f original NOT in the backup — lost"; fi
  done
  # The global ignore is edited in place: every seeded line survives, in order,
  # and the managed patterns are appended.
  if head -c "$(wc -c < /tmp/seed/.config/git/ignore)" "$HOME/.config/git/ignore" | cmp -s - /tmp/seed/.config/git/ignore; then
    pass "~/.config/git/ignore keeps the seeded lines as its first lines"
  else
    fail "~/.config/git/ignore lost or reordered seeded lines:"; sed 's/^/    /' "$HOME/.config/git/ignore"
  fi
  grep -qxF '.envrc.private' "$HOME/.config/git/ignore" && pass "…including the last line, which had no newline" \
    || fail "the seeded last line (no trailing newline) was merged into the next pattern"
  git init -q /tmp/ign-repo && mkdir -p /tmp/ign-repo/.claude-logs
  touch /tmp/ign-repo/a.swp /tmp/ign-repo/.claude-logs/x
  [ -z "$(git -C /tmp/ign-repo status --porcelain)" ] && pass "git ignores both a seeded pattern and .claude-logs/" \
    || fail "git does not ignore: $(git -C /tmp/ign-repo status --porcelain | tr '\n' ' ')"
  got=$(tmux -L seedcheck -f "$HOME/.tmux.conf" new-session -d \; show-options -gv history-limit 2>&1; tmux -L seedcheck kill-server 2>/dev/null)
  [ "$got" = 12345 ] && pass "hand-written tmux setting effective (via ~/.config/tmux/local.conf)" \
    || fail "hand-written tmux setting not effective: history-limit is '$got'"
  got=$(bash -lc 'echo "${SEED_BASHRC:-}"' 2>/dev/null)
  [ "$got" = 1 ] && pass "hand-written ~/.bashrc line effective (via ~/.shellrc.local)" \
    || fail "hand-written ~/.bashrc line not effective"
  local st="$HOME/.claude/settings.json"
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | index("/usr/local/bin/seeded-guard")' "$st" >/dev/null \
    && pass "seeded foreign PreToolUse hook survives the settings merge" \
    || fail "seeded foreign hook was dropped from ~/.claude/settings.json"
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("logger/log_tool.py"))' "$st" >/dev/null \
    && pass "managed PreToolUse hook added alongside it" || fail "managed PreToolUse hook missing"
  [ "$(jq -r .cleanupPeriodDays "$st")" = 14 ] && [ "$(jq -r .showThinkingSummaries "$st")" = false ] \
    && pass "machine's cleanupPeriodDays and showThinkingSummaries kept" \
    || fail "machine settings overwritten: cleanupPeriodDays=$(jq -r .cleanupPeriodDays "$st") showThinkingSummaries=$(jq -r .showThinkingSummaries "$st")"
  jq -e '.permissions.allow | index("Bash(ls:*)") and index("WebSearch")' "$st" >/dev/null \
    && pass "permissions are a union (seeded + managed)" || fail "permissions not merged: $(jq -c .permissions.allow "$st")"
}

# find-based snapshot: type, mode, path, and a content hash for files and link
# targets. Excludes the undo's own by-products, which the diff reports
# separately.
snapshot() {
  ( cd "$HOME" && find . -xdev \( -path ./.cache \) -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
      if   [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then printf 'D %s\n' "$p"
      else printf 'F %s %s %s\n' "$(stat -c %a "$p")" "$(sha256sum < "$p" | cut -c1-16)" "$p"; fi
    done )
}

sc_online() {
  # A fresh machine: no ~/.gitconfig, no ~/.zshrc. Step 1 must not error, and
  # must leave git able to commit (useConfigOnly with an identity).
  guide_step1
  init_repo || return
  step "portable tree, not the private repo"
  [ ! -e "$(chezmoi source-path)/fleet" ] && pass "no fleet/ in the source" || fail "source has fleet/"
  apply_and_check online
  tpm_present && pass "TPM installed" || fail "TPM not installed after a networked apply with tmux"
  git init -q /tmp/commit-check && git -C /tmp/commit-check commit -q --allow-empty -m test \
    && pass "a first commit works on a fresh machine (identity from ~/.config/git/local)" \
    || fail "first commit fails: no git identity"
  check_logs
}

sc_offline_online() {
  init_repo || return
  apply_and_check offline DOTFILES_NO_NETWORK=1
  tpm_present && fail "TPM present after an offline apply" || pass "TPM absent after the offline apply"
  # The guide's note: plain verify after an offline apply returns 1 with the
  # tmux scripts pending. Asserted, because the note tells a reader what is normal.
  chezmoi verify --no-tty </dev/null >/dev/null 2>&1 && fail "plain verify rc=0 after an offline apply; the guide says 1" \
    || pass "plain verify rc=1 after the offline apply, as the guide says"
  apply_and_check online
  tpm_present && pass "TPM installed by the networked apply" || fail "TPM still absent after the networked apply"
}

sc_tmux_later() {
  local tmux; tmux=$(command -v tmux)
  sudo mv "$tmux" "$tmux.hidden"
  command -v tmux >/dev/null && { fail "could not hide tmux"; return; }
  init_repo || return
  apply_and_check no-tmux
  tpm_present && fail "TPM present with no tmux" || pass "TPM absent with no tmux"
  step "install tmux"
  sudo mv "$tmux.hidden" "$tmux"
  apply_and_check tmux-added
  tpm_present && pass "TPM installed once tmux arrived" || fail "TPM still absent after tmux arrived"
}

sc_upgrade() {
  seed_home || return
  mkdir -p /tmp/seed
  (cd "$HOME" && cp -a --parents .bashrc .zshrc .gitconfig .tmux.conf .config/git/ignore .claude/settings.json /tmp/seed/)
  cp -a "$HOME/.profile" /tmp/profile.before
  guide_step1
  init_repo || return
  guide_step3_backup
  apply_and_check upgrade
  check_upgrade
  # Activation inside an if/fi: deleting the line alone leaves an empty branch
  # and a login shell that fails to parse. Step 1 must put the file back whole.
  step "step 1 on a ~/.profile whose mise activation sits inside an if/fi"
  ( export HOME; HOME=$(mktemp -d)
    printf 'export KEEP=1\nif command -v mise >/dev/null; then\n  eval "$(mise activate bash)"\nfi\n' > ~/.profile
    cp ~/.profile /tmp/guarded.before
    guide_step1_profile | grep -q '^STOP: edit ~/.profile by hand' && bash -n ~/.profile && cmp -s /tmp/guarded.before ~/.profile
  ) && pass "guarded activation: ~/.profile restored whole and a STOP printed" \
    || fail "guarded activation: ~/.profile left changed, unparseable, or no STOP"
}

sc_undo() {
  seed_home || return
  # A file a later release starts managing, already present before step 1.
  mkdir -p ~/.config/shell && echo original > ~/.config/shell/update-existing
  snapshot > /tmp/home.before
  guide_step1
  init_repo || return
  guide_step3_backup
  apply_and_check upgrade
  # A second run of the backup after the apply must not overwrite the originals.
  local before_sum; before_sum=$(cd "$BACKUP" && find . -type f -exec sha256sum {} + | sort | sha256sum)
  guide_step3_backup
  [ "$(cd "$BACKUP" && find . -type f -exec sha256sum {} + | sort | sha256sum)" = "$before_sum" ] \
    && pass "re-running the backup after the apply leaves the originals untouched" \
    || fail "re-running the backup changed the backup"
  # A later release: one file that already existed and one in a new directory.
  # Written straight into the source, the state the guide's reset leaves.
  # Under .config/shell because .chezmoiignore ignores anything not allowed.
  local src; src=$(chezmoi source-path)
  mkdir -p "$src/dot_config/shell/update-new"
  echo managed > "$src/dot_config/shell/update-existing"
  echo new > "$src/dot_config/shell/update-new/file"
  guide_update_backup
  apply_and_check update
  [ "$(cat ~/.config/shell/update-existing)" = managed ] && [ -f ~/.config/shell/update-new/file ] \
    && pass "the update wrote over one existing file and added one in a new directory" \
    || fail "the simulated release was not applied"
  # Stand-ins for what real use adds after the apply: a first zsh launch
  # (clones zinit when online).
  zsh -ic true >/dev/null 2>&1
  step1_restore_safe && fail "step 1 restore guard passes while the managed ~/.gitconfig is live" \
    || pass "step 1 restore guard refuses while the managed ~/.gitconfig is live"
  guide_step3_restore
  # An original ~/.gitconfig with no identity (aliases and a proxy only) must
  # still let step 1's restore through once step 3's restore has put it back.
  cp -a ~/.gitconfig /tmp/gitconfig.orig
  git config --file ~/.gitconfig --remove-section user 2>/dev/null
  step1_restore_safe && pass "step 1 restore guard passes on an identity-less original ~/.gitconfig" \
    || fail "step 1 restore guard blocks an identity-less original ~/.gitconfig"
  cp -a /tmp/gitconfig.orig ~/.gitconfig
  guide_step1_restore

  step "diff HOME against the pre-step-1 snapshot"
  snapshot > /tmp/home.after
  diff /tmp/home.before /tmp/home.after > /tmp/home.diff
  # Expected by-products of the guide itself: the backup and the managed list.
  local unexpected
  unexpected=$(grep -E '^[<>]' /tmp/home.diff | grep -vE '^> [FD] (.* )?\./pre-portable-core(\.paths|\.newdirs)?(/|$)')
  local removed added changed
  removed=$(grep -c '^<' /tmp/home.diff)
  added=$(grep -c '^>' /tmp/home.diff)
  echo "  $removed line(s) only before, $added only after"
  if [ -z "$unexpected" ]; then
    pass "HOME matches the snapshot apart from the backup and the managed list"
  else
    fail "HOME differs from the pre-apply snapshot:"
    printf '%s\n' "$unexpected" | sed -E 's/ [0-9a-f]{16} / /' | head -80 | sed 's/^/    /'
    [ "$(printf '%s\n' "$unexpected" | wc -l)" -gt 80 ] && echo "    … $(printf '%s\n' "$unexpected" | wc -l) lines in all"
  fi
  local dang; dang=$(find "$HOME" -xtype l 2>/dev/null)
  [ -z "$dang" ] && pass "no dangling symlink left in HOME" || fail "dangling symlinks left: $(echo "$dang" | head -5 | tr '\n' ' ')"
}

inside_main() {
  local s=${1:?scenario}
  export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
  case "$s" in
    online)         sc_online ;;
    offline-online) sc_offline_online ;;
    tmux-later)     sc_tmux_later ;;
    upgrade)        sc_upgrade ;;
    undo)           sc_undo ;;
    *) echo "no scenario $s" >&2; exit 2 ;;
  esac
  [ "$FINDINGS" -eq 0 ]
}

if [ "${1:-}" = --inside ]; then shift; inside_main "$@"; else host_main "$@"; fi
