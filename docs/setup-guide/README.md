# Setup

How to put agent-core on a fresh Windows 11 + WSL2 (Ubuntu 24.04) machine.
Each step has a command, what "done" prints, and, for most, how to undo it.
[Validation](#validation) reruns the checks that read the machine, at once.

It is not a macOS guide: steps 1 and 3 use GNU `sed -i`, `cp --parents` and
`xargs -d`. On a Mac, use the README's short version, and still move your git
settings as step 1 does first.

> [!NOTE]
> Run end to end on a fresh WSL2 Ubuntu 24.04 distro on 2026-09-29. Every
> change since then is tested in Ubuntu containers only, and the Windows-side
> steps (WezTerm, fonts, Windows Terminal) not at all.

## Prerequisites

- [ ] **WSL2 with systemd, a working trust store, and [mise](https://mise.jdx.dev)
	with the CLI tools.** If the network inspects TLS, its root CA must be in
	`/usr/local/share/ca-certificates/` as a `.crt`, and `update-ca-certificates`
	must have run. Check both before anything downloads:
	```bash
	# Expected: "systemd", then "SSL certificate verify ok". A certificate error
	# here means the CA is not in place yet; the mise install below would fail too.
	ps -p 1 -o comm=
	curl -vI https://github.com 2>&1 | grep -i 'SSL certificate verify'
	```
	Keep Windows interop working across systemd restarts (step 4 has the recovery
	if it drops anyway):
	```bash
	echo ':WSLInterop:M::MZ::/init:PF' | sudo tee /etc/binfmt.d/WSLInterop.conf
	sudo systemctl restart systemd-binfmt
	# Expected: "interop ok". stderr is hidden (a harmless UNC-path warning when
	# run from ~), so the grep is what reports a failure.
	cmd.exe /c ver </dev/null 2>/dev/null | grep -q Windows && echo "interop ok" \
	  || echo "STOP: interop down; sudo systemctl restart systemd-binfmt"
	```
	Put `~/.local/bin` on PATH now; stock Ubuntu adds it only at the next login.
	```bash
	mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
	```
	Install [mise](https://mise.jdx.dev) and the CLI tools. Skip mise's
	"activate" step: the managed shell files put the tools on PATH themselves.
	Use the plain URL; `mise.run/bash` and `mise.run/zsh` write activation into
	your rc file.
	```bash
	# Download, then run: a failed `curl | sh` still returns 0.
	curl -fsSL https://mise.run -o /tmp/mise-install.sh && sh /tmp/mise-install.sh && rm /tmp/mise-install.sh
	mise use -g ripgrep fd eza bat sd delta starship lazygit direnv fzf
	```
	<details><summary>Restore to default</summary>

	```bash
	mise unuse -g ripgrep fd eza bat sd delta starship lazygit direnv fzf
	# mise itself, after step 2's restore (which uses it):
	rm -f ~/.local/bin/mise; rm -rf ~/.config/mise ~/.local/share/mise
	```
	</details>

	```bash
	# Expected: ten paths and no MISSING. `mise which`, because mise's tools are
	# not on PATH in this shell until step 3's rc files load.
	for t in rg fd eza bat sd delta starship lazygit direnv fzf; do printf '%-10s %s\n' "$t" "$(mise which "$t" 2>/dev/null || echo MISSING)"; done
	```
- [ ] **Install jq, git, tmux, python3 and zsh.** The apply stops before writing
	anything without `jq` or `git`; the hooks need `python3`; zsh is the shell
	step 4's terminal opens.
	```bash
	sudo apt update && sudo apt install -y jq git tmux python3 zsh
	```
- [ ] **On Windows, install WezTerm and the Monaspace fonts.** Step 4 gives
	WezTerm a config that opens zsh in WSL and sets text in Monaspace; without
	the fonts WezTerm falls back to its own and warns.
	```powershell
	# In PowerShell, not WSL.
	winget install wez.wezterm
	```
	For the fonts, download `monaspace-static-*.zip` from the
	[Monaspace releases](https://github.com/githubnext/monaspace/releases),
	unzip it, select the `.otf` files, right-click and choose Install.
	<details><summary>Restore to default</summary>

	`winget uninstall wez.wezterm`, then remove the Monaspace fonts in
	Settings > Personalization > Fonts.
	</details>
- [ ] **Verification**
	```bash
	# Expected: two paths, bash major >= 4, "ok"
	command -v jq git
	bash -c 'echo "${BASH_VERSINFO[0]}"'
	python3 -c 'import sys; print("ok" if sys.version_info >= (3, 9) else "TOO OLD")'
	```

---

## 1. Move machine settings out of the files the apply replaces

The apply replaces `~/.gitconfig`, `~/.bashrc`, `~/.bash_profile`, `~/.zshrc`
and `~/.tmux.conf` whole. Each reads a local file last, which chezmoi never touches:

| Replaced | Local file it reads last |
|---|---|
| `~/.gitconfig` | `~/.config/git/local` |
| `~/.bashrc`, `~/.zshrc` | `~/.shellrc.local` (both shells) |
| `~/.bash_profile` | `~/.profile`, then `~/.bashrc` |
| `~/.tmux.conf` | `~/.config/tmux/local.conf` |

- [ ] Move the git settings before the first apply. The whole file comes along,
	and it wins wherever it sets the same key as the managed file.
	```bash
	mkdir -p ~/.config/git
	f=~/.config/git/local
	# A fresh machine has no ~/.gitconfig: note that, so the restore knows there
	# is nothing to put back.
	[ -e "$f" ] || { [ -e ~/.gitconfig ] && cp -a ~/.gitconfig "$f" || { : > "$f"; touch ~/.config/git/.from-scratch; }; }
	git config --file "$f" user.useConfigOnly true
	```
- [ ] **Give git an identity** if it has none. With `useConfigOnly` set, git
	refuses to commit without one.
	```bash
	f=~/.config/git/local
	git config --file "$f" --get user.email >/dev/null || {
	  git config --file "$f" user.name  "Your Name"          # edit before pasting
	  git config --file "$f" user.email "you@example.com"    # the address for this machine
	}
	git config --file "$f" --get user.email   # Expected: the address you set
	```
- [ ] **Remove any older mise activation** from `~/.profile`, which is not
	replaced. Only a machine that had mise set up before this guide has one.
	```bash
	if [ -e ~/.profile ]; then
	  [ -e ~/.profile.pre-portable-core ] || cp -a ~/.profile ~/.profile.pre-portable-core   # first run only
	  sed -i -E '/^[[:space:]]*eval[[:space:]].*mise[[:space:]]+activate/d' ~/.profile
	  # A line inside an if/fi leaves an empty branch; put the file back if so.
	  bash -n ~/.profile || { cp -a ~/.profile.pre-portable-core ~/.profile; echo "STOP: edit ~/.profile by hand"; }
	fi
	# Expected: nothing. Any line left is yours to remove by hand; zsh still reads
	# the last two, and the new ~/.bash_profile hides ~/.bash_login.
	grep -n 'mise activate' ~/.profile ~/.bash_login ~/.zprofile ~/.zshenv 2>/dev/null
	```
- [ ] Carry over your own shell and tmux lines, if you want them. Ubuntu ships
	no `~/.zshrc`, so all of that one is yours.
	```bash
	[ -e ~/.bashrc ] && diff /etc/skel/.bashrc ~/.bashrc
	[ -e ~/.zshrc ] && cat ~/.zshrc
	[ -e ~/.bash_profile ] && cat ~/.bash_profile
	# Copy the lines worth keeping, minus mise activation, into ~/.shellrc.local.
	# Both shells read it, agent bash included: wrap zsh-only lines (setopt,
	# bindkey, zstyle) in  if [ -n "$ZSH_VERSION" ]; then ... fi
	# tmux: the whole file carries over as is.
	mkdir -p ~/.config/tmux
	[ -e ~/.tmux.conf ] && [ ! -e ~/.config/tmux/local.conf ] && cp ~/.tmux.conf ~/.config/tmux/local.conf
	```
	<details><summary>Restore to default</summary>

	```bash
	# Before step 3's apply, or after step 3's restore has put ~/.gitconfig back.
	# In between, ~/.config/git/local is the only live copy of your git settings;
	# the managed ~/.gitconfig is recognised by its include of that file.
	if [ -e ~/.config/git/.from-scratch ] || { [ -f ~/.gitconfig ] && ! git config --file ~/.gitconfig --get-all include.path | grep -qxF '~/.config/git/local'; }; then
	  rm -f ~/.config/git/local ~/.config/git/.from-scratch ~/.config/tmux/local.conf
	  rmdir ~/.config/git ~/.config/tmux 2>/dev/null || true   # only if now empty
	else
	  echo "~/.gitconfig is still the managed one; restore step 3's backup first"
	fi
	# Put back the mise lines removed from ~/.profile.
	[ -e ~/.profile.pre-portable-core ] && mv ~/.profile.pre-portable-core ~/.profile
	# Remove by hand any lines you added to ~/.shellrc.local.
	```
	</details>
- [ ] **Verification**, now and again after step 3.
	```bash
	# Expected now: your old ~/.gitconfig's keys plus user.useconfigonly=true
	# (git does not read this file until the apply adds the include)
	git config --file ~/.config/git/local --list
	# Expected after the apply: your user.* keys, plus http.* if you set a CA,
	# each from file:~/.config/git/local
	git config --show-origin --get-regexp '^(user|http)\.'
	```

---

## 2. Agent CLIs

- [ ] Install Claude Code.
	```bash
	curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && bash /tmp/claude-install.sh && rm /tmp/claude-install.sh
	```
- [ ] Install Codex CLI; mise provides Node without root.
	```bash
	mise use -g node@lts
	# Through mise, not npm -g: an npm -g install lives inside one Node version
	# and drops off PATH when mise upgrades Node.
	mise use -g npm:@openai/codex
	```
	<details><summary>Restore to default</summary>

	```bash
	mise unuse -g npm:@openai/codex node
	```
	</details>
- [ ] **Verification**
	```bash
	# Expected: two version strings. A TLS error means the trust store prerequisite is not met.
	# codex through mise exec: not on PATH in this shell until step 3.
	claude --version; mise exec -- codex --version
	```

---

## 3. Apply

- [ ] Install chezmoi to `~/.local/bin`.
	```bash
	curl -fsLS https://get.chezmoi.io -o /tmp/chezmoi-install.sh && sh /tmp/chezmoi-install.sh -b ~/.local/bin && rm /tmp/chezmoi-install.sh
	```
- [ ] Initialise from this repo and note the commit, so what you review is
	what runs.
	```bash
	chezmoi init https://github.com/brockshanson/agent-core.git   # the PUBLIC repo, never the private one
	cd "$(chezmoi source-path)"
	git log --oneline -1          # note this commit; it is what you review below
	# Expected: "portable tree". The private repo carries a fleet/ directory, and
	# applying it would bring home MCP servers, model pins and plugins along.
	[ ! -e fleet ] && echo "portable tree" || echo "STOP: this is the private repo; chezmoi purge and init the public one"
	cd - >/dev/null
	```
- [ ] **Read the code that will run.** Hooks, skills and helpers are symlinks
	into the clone, so `chezmoi diff` shows only their link paths.
	```bash
	cd "$(chezmoi source-path)"
	# What executes: hooks, bootstrap scripts, the modify_ scripts the apply
	# runs, the log-search helper on PATH, the deep-research workflow, and the
	# settings that wire the hooks. Skill bodies are in agent-skills/*/SKILL.md.
	ls claude/hooks claude/hooks/logger run_* dot_local/bin
	less claude/settings.json.template claude/hooks/*.sh claude/hooks/*.py claude/hooks/logger/*.py run_* \
	  dot_claude/modify_settings.json.tmpl dot_config/git/modify_ignore agent-skills/logs/search_logs.py \
	  claude/workflows/deep-research.js
	cd - >/dev/null
	```
- [ ] **Read the diff.** It should add configuration and nothing that connects
	anywhere.
	```bash
	chezmoi diff | less
	# Expected: no output. Any line means an MCP server came along.
	chezmoi diff | grep -n 'mcpServers'
	```
- [ ] **Back up everything the apply writes over:** every managed file, plus
	what the scripts and the first zsh launch create. Files that exist are
	copied; the rest are recorded for the undo to remove.
	```bash
	b=~/pre-portable-core
	# Never overwrite an existing backup, on any day: run after the apply, this
	# would copy the applied files over the originals and lose the only undo.
	# The glob also catches a dated backup from an earlier copy of this guide.
	ls -d ~/pre-portable-core* >/dev/null 2>&1 && { echo "STOP: a backup already exists ($(ls -d ~/pre-portable-core* | head -1)); keep it, and do not re-run this backup"; } || {
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
	# Expected: each file below that existed before the apply, with its path
	find "$b" \( -type f -o -type l \) -not -path '*/.tmux/plugins/*' | sed "s|^$b/||"
	}
	```
	> [!WARNING]
	> **No undo without this backup.** chezmoi keeps no copy of what it
	> overwrites, and `chezmoi purge` leaves every file it wrote behind as a
	> broken link. The backup and restore need GNU tools (Ubuntu, WSL), not macOS.
- [ ] Apply. On a filtered network, prefix `DOTFILES_NO_NETWORK=1`; skipped
	steps print the command to run later. The log is kept for step 4.
	```bash
	mkdir -p ~/.local/state && chezmoi apply -v 2>&1 | tee ~/.local/state/agent-core-apply.log
	```
	<details><summary>Restore to default</summary>

	Run before step 1's restore. It removes what the apply wrote, puts the
	originals back, and removes chezmoi. Session logs stay.
	```bash
	b=~/pre-portable-core   # a backup from an earlier copy of this guide is ~/pre-portable-core-<date>
	( set -e
	  [ -s "$b.paths" ] && [ -d "$b" ] \
	    || { echo "no backup at $b — set b to the real backup first; nothing changed"; exit 1; }
	  cd ~
	  xargs -d '\n' rm -rf -- < "$b.paths"       # what the apply wrote or created
	  cp -a "$b"/. ~/                            # the originals, where they were
	  rm -f ~/.local/state/agent-core-apply.log
	  sort -r "$b.newdirs" | xargs -r -d '\n' rmdir --ignore-fail-on-non-empty --
	  chezmoi purge --force                      # chezmoi's source, config and state
	  rm -f ~/.local/bin/chezmoi
	)
	```
	</details>

	> [!CAUTION]
	> **A failed apply stops partway**, and through `tee` it does not even
	> return `rc=1`. Run `chezmoi status`, and don't start an agent until it is empty.
- [ ] **Verification**
	```bash
	# Expected: no output and rc=0, then 1 (the generic host profile is imported),
	# then "managed: N" with N of 60 or more. verify alone is not enough: with
	# the chezmoi source gone it manages nothing and still returns 0.
	chezmoi verify; echo "rc=$?"
	grep -c '_generic/host.md' ~/.claude/CLAUDE.md
	echo "managed: $(chezmoi managed | wc -l)"
	```
	> [!NOTE]
	> After an apply with `DOTFILES_NO_NETWORK=1`, verify with the same prefix.
	> A plain `verify` reports the two tmux scripts pending until one networked
	> apply runs.

---

## 4. Shells and terminal

- [ ] **Verification: agent shell.** In a fresh WSL login shell:
	```bash
	# Expected: a bash version, "builtin", a path under ~/.local/share/mise/installs
	bash -lc 'echo "$BASH_VERSION"; type -t cd; command -v rg'
	```
	Neither shell activates mise, so `cd` stays the builtin. Open a new shell
	after `mise upgrade`.
- [ ] **Give Windows WezTerm its config.** WezTerm on Windows reads
	`%USERPROFILE%\.wezterm.lua` and won't follow a symlink into WSL, so copy
	it across, and again after any change. It opens your default WSL distro;
	set the Windows variable `WEZTERM_WSL_DISTRO` to pick another.
	```bash
	# Run in WSL. Replaces any existing Windows-side .wezterm.lua; back it up first if you have one.
	# </dev/null: cmd.exe reads stdin and would swallow the rest of a pasted script.
	win_home=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' </dev/null 2>/dev/null | tr -d '\r')")
	# If WSL interop is down (after a VM restart cmd.exe fails with "Exec format
	# error"), win_home comes back as "." and the copy would land inside WSL.
	case "$win_home" in
	  /mnt/?/*) cp "$(chezmoi source-path)/agent-core/wezterm/wezterm.lua" "$win_home/.wezterm.lua" \
	              && ls -l "$win_home/.wezterm.lua" ;;   # Expected: the file, just written
	  *) echo "STOP: could not find your Windows home (got '$win_home'): WSL interop is down; see the note below" ;;
	esac
	```
	> [!NOTE]
	> **If it says interop is down** (`cmd.exe` fails with "Exec format error"),
	> restart binfmt and re-run the snippet:
	> ```bash
	> sudo systemctl restart systemd-binfmt
	> cmd.exe /c ver </dev/null 2>/dev/null | grep -q Windows && echo "interop ok"
	> ```
	> If that still fails, re-register the handler by hand:
	> `echo ':WSLInterop:M::MZ::/init:PF' | sudo tee /proc/sys/fs/binfmt_misc/register`.

	Windows Terminal also works, with two things to do by hand: port the Flexoki
	colours, and set the WSL profile's command line to
	`wsl.exe ~ -d <distro> -- zsh -l`, or its tabs open bash and the next check
	fails.
- [ ] **Verification: human shell.** Open a new WezTerm tab. The first zsh launch
	clones zinit, announced, and skips it under `DOTFILES_NO_NETWORK=1`.
	```bash
	# Expected: zsh, then a path for rg
	ps -p $$ -o comm=; command -v rg
	```
- [ ] **Verification: git survived the apply.** Rerun step 1's second check.
- [ ] **Verification: tmux plugins.**
	```bash
	# Expected: tpm, tmux-continuum, tmux-resurrect, tmux-sensible
	ls ~/.tmux/plugins
	```
	If one is missing, find the failure in step 3's log and run the command it
	names: `grep -n -A3 WARNING ~/.local/state/agent-core-apply.log`.

---

## 5. First sessions

- [ ] **Start sessions from WSL's home.** `wsl -d <distro>` opens in the
	Windows folder you launched from, and Claude Code reads that folder's
	`.claude/`. Use `wsl ~ -d <distro>`, or `cd` first.
- [ ] **Sign in** at the first `claude` launch, only with the account meant for
	this machine.
- [ ] Pick the theme in Claude Code: `/theme`, then `custom:flexoki-dark`.
- [ ] Check the theme contrast. It was tuned on macOS; judge Windows rendering
	by eye.
	```bash
	python3 "$(chezmoi source-path)/agent-core/claude-themes/check-contrast.py"
	```
- [ ] **Verification: Claude Code.** Start `claude` in a scratch repo and ask:
	*"Which host profile did you load, and what does it say is absent here?"*
	**Expected:** it names the unregistered-host fallback and lists the absent
	tracker, git server, and review app. No hook errors at session start.
- [ ] **Verification: session logs stay out of repos.** Run after the first
	session in step 5.
	```bash
	# Expected: a non-empty listing, then nothing
	ls ~/.local/state/claude-logs
	ls -d <the-repo-you-used>/.claude-logs 2>/dev/null
	```
	> [!CAUTION]
	> Logs hold full tool calls and reasoning. A `.claude-logs/` inside a repo is
	> staged by the first `git add .`, without warning.
- [ ] **Account connectors are off.** Ask a new session which tools it has.
	**Expected:** none of the account's claude.ai connectors.
	```bash
	jq -r '.env.ENABLE_CLAUDEAI_MCP_SERVERS' ~/.claude/settings.json   # Expected: false
	```
	Set it to `"true"` to turn them all back on; later applies keep your value.
- [ ] **Verification: skills and hooks.**
	```bash
	# Expected: create-spec grill-me handoff interviewing logs workflow-designer
	ls ~/.claude/skills
	# Expected: Notification PostCompact PostToolUse PostToolUseFailure PreToolUse SessionStart Stop
	jq -r '.hooks | keys | join(" ")' ~/.claude/settings.json
	```
- [ ] **Verification: Codex instruction budget.** Codex silently truncates
	`~/.codex/AGENTS.md` past 32 KiB; the apply raises the cap.
	```bash
	# Expected: a byte count under 65536, then a line reading project_doc_max_bytes = 65536
	wc -c ~/.codex/AGENTS.md
	grep -n '^project_doc_max_bytes' ~/.codex/config.toml
	```

---

## Updating

Never run `chezmoi update`: the pull alone changes the hooks and skills that
run, before you have read them.

- [ ] Fetch, read, then move and apply. Each release is a fresh single commit,
	so the clone moves with a reset; nothing in it is yours to keep.
	```bash
	cd "$(chezmoi source-path)"
	git fetch origin
	git log --oneline -1 origin/main       # what is new
	git diff HEAD origin/main | less       # all of it, hook and skill code included
	git reset --hard origin/main
	cd - >/dev/null
	# Extend step 3's backup to what this release adds, before it is written:
	# a newly managed file is recorded, and backed up if it already exists.
	b=~/pre-portable-core
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
	)
	chezmoi diff | less
	chezmoi apply -v
	chezmoi verify; echo "rc=$?"           # Expected: rc=0
	```

## Validation

Run in a new WSL tab: the shell you started in has none of step 3's PATH.

```bash
# P · Prerequisites. Expected: jq and git paths, bash >= 4, "ok", ten tool paths
command -v jq git; bash -c 'echo "${BASH_VERSINFO[0]}"'
python3 -c 'import sys; print("ok" if sys.version_info >= (3, 9) else "TOO OLD")'
command -v rg fd eza bat sd delta starship lazygit direnv fzf

# 1 · Git. Expected: your user.* keys, plus http.* if you set a CA, each from ~/.config/git/local
git config --show-origin --get-regexp '^(user|http)\.'

# 2 · Agents. Expected: two versions
claude --version; codex --version

# 3 · Apply. Expected: rc=0 with no output, then 1, then managed: 60 or more
chezmoi verify; echo "rc=$?"; grep -c '_generic/host.md' ~/.claude/CLAUDE.md
echo "managed: $(chezmoi managed | wc -l)"

# 4 · Shells and logs. Expected: bash version, "builtin", a path under mise/installs; a non-empty log dir
bash -lc 'echo "$BASH_VERSION"; type -t cd; command -v rg'
ls ~/.local/state/claude-logs

# 5 · Sessions. Expected: hook event names; a byte count under 65536; project_doc_max_bytes = 65536
jq -r '.hooks | keys | join(" ")' ~/.claude/settings.json; wc -c ~/.codex/AGENTS.md
grep -n '^project_doc_max_bytes' ~/.codex/config.toml
```

## Sanity check

Checks on this guide rather than the machine:

- **Step 1 was needed.** On a machine that had a `~/.gitconfig`, before
  applying, `chezmoi diff ~/.gitconfig` should show its hand-set `[user]` and
  `[http]` lines being removed and the `[include]` added. If it does not, this
  guide misread the template. On a fresh machine the diff is a new file, and
  the `[include] path = ~/.config/git/local` line is what to look for.
- **The logs check has a positive control.** "No `.claude-logs/` in the repo"
  means nothing unless the session logged somewhere; the non-empty
  `~/.local/state/claude-logs` listing is what makes it mean something.
