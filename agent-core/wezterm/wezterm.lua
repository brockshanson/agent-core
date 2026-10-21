-- Enhanced WezTerm configuration for Semantic Typography
-- Using Monaspace font families with Mix & Match via font_rules
-- 
-- This configuration maps different SGR attributes to different Monaspace families:
-- - Default code → Neon (grid-accurate monospace)
-- - AI thinking/drafts → Radon (italic)
-- - Comments/docs → Argon (faint/half intensity)
-- - Errors/diagnostics → Krypton (curly underlines)
-- - Prompts/input → Xenon (reverse video)

local wezterm = require 'wezterm'
local config = {}

-- ---------------------------------------------------------------------------
-- Platform detection (claude-dotfiles-yme.10)
--
-- This file is delivered as a plain SYMLINK into the repo, not as a chezmoi
-- template, and that was a deliberate choice: WezTerm evaluates its config as
-- Lua on every reload, so the file can branch at RUNTIME while staying a live
-- symlink. Templating it would move the branch to `chezmoi apply` time and
-- break the edit-the-repo-and-it's-live flow the rest of this repo rests on
-- (see docs/chezmoi-migration.md). Branch here, in Lua — not in chezmoi.
--
-- target_triple values this config is written against:
--   aarch64-apple-darwin      Apple Silicon macOS
--   x86_64-pc-windows-msvc    Windows (WezTerm native, not the WSL side)
--   *-unknown-linux-gnu       Linux; headless hosts run no GUI terminal
local target    = wezterm.target_triple
local is_darwin  = target:find('darwin')  ~= nil
local is_windows = target:find('windows') ~= nil

-- Interactive shell, pinned explicitly (claude-dotfiles-yme.9).
--
-- The login shell ($SHELL / dscl UserShell) moved to bash so that Claude
-- Code's Bash tool runs bash rather than zsh: it snapshots the LOGIN shell, so
-- setting CLAUDE_CODE_SHELL alone would source a zsh snapshot into bash and
-- break every command. Humans still want zsh, so the terminal launches it
-- explicitly instead of inheriting it. `-l` so the zsh login files still run.
--
-- Resolve the path rather than hardcoding it: zsh is /bin/zsh on macOS but
-- /usr/bin/zsh on most Linux distros. wezterm.glob is the only filesystem
-- probe available at config-parse time.
local function first_existing(paths)
  for _, candidate in ipairs(paths) do
    local hits = wezterm.glob(candidate)
    if hits and #hits > 0 then return hits[1] end
  end
  return nil
end

if is_windows then
  -- On Windows the equivalent lever is the WSL DOMAIN, not default_prog:
  -- the shell lives inside the distro, and /etc/wsl.conf `[user] default=`
  -- decides who it runs as. Enumerate rather than hardcoding a distro name;
  -- if no WSL distro is registered this falls through to the native shell.
  -- UNVERIFIED — no Windows box exists yet. Confirm which lever WezTerm
  -- actually honours on the machine before trusting this (yme.10).
  local wsl = wezterm.default_wsl_domains()
  if wsl and #wsl > 0 then
    -- Open zsh, the human shell, inside WSL. Without this the domain starts
    -- the distro user's login shell, which is bash (the agent shell), and zsh
    -- never runs (portable-core red team, 2026-09-29). Falls back to bash if
    -- zsh is not installed, rather than failing to open a tab.
    for _, dom in ipairs(wsl) do
      dom.default_prog = { 'bash', '-c', 'command -v zsh >/dev/null && exec zsh -l || exec bash -l' }
    end
    config.wsl_domains = wsl
    -- Which distro opens by default. default_wsl_domains() lists distros in
    -- registry order, not with the Windows default first: on the first real
    -- run that put docker-desktop first and opened the wrong distro
    -- (acceptance run, 2026-09-29). In order of preference:
    --   1. WEZTERM_WSL_DISTRO, a Windows user environment variable, if set;
    --   2. the WSL default distro, as WSL itself reports it;
    --   3. the first domain that is not a Docker Desktop utility distro.
    local function probe_default()
      local ok, out = wezterm.run_child_process {
        'wsl.exe', '--exec', 'sh', '-c', 'printf %s "$WSL_DISTRO_NAME"',
      }
      if ok and out and out ~= '' then return out end
      return nil
    end
    local function find(name)
      for _, dom in ipairs(wsl) do
        if name and dom.distribution == name then return dom.name end
      end
      return nil
    end
    local override = os.getenv('WEZTERM_WSL_DISTRO')
    local pick = find(override)
    if override and not pick then
      -- A typo here used to fall through silently.
      wezterm.log_warn('WEZTERM_WSL_DISTRO=' .. override
        .. ' matches no WSL distro; opening the WSL default instead')
    end
    -- The probe runs whenever the override did not decide, so a typo lands on
    -- the WSL default, as the warning says, not on registry order.
    if not pick then pick = find(probe_default()) end
    if not pick then
      for _, dom in ipairs(wsl) do
        if not (dom.distribution or ''):match('^docker%-desktop') then pick = dom.name break end
      end
    end
    config.default_domain = pick or wsl[1].name
  end
else
  local zsh = first_existing { '/bin/zsh', '/usr/bin/zsh', '/opt/homebrew/bin/zsh' }
  if zsh then
    config.default_prog = { zsh, '-l' }
  end
end

-- Base font configuration with fallbacks for glyphs
config.font = wezterm.font_with_fallback({
  { family = 'Monaspace Neon' },
  { family = 'Symbols Nerd Font Mono' }, -- Powerline/NerdFont glyphs
  { family = 'Noto Color Emoji' },       -- Emoji support (macOS/Linux)
  { family = 'Segoe UI Emoji' },         -- Emoji support (Windows)
})

-- Font size optimized for readability
config.font_size = 12.0

-- Keep the OS window fixed when font size changes; reflow columns instead.
-- Pairs with PinchBar (trackpad pinch → ⌘+/⌘-) so pinch-to-zoom mirrors
-- Terminus's pane-reflow behavior on iOS rather than growing the window.
config.adjust_window_size_when_changing_font_size = false

-- Enable texture healing and ligatures for Monaspace
-- CRITICAL: Must include stylistic sets (ss01-ss09) and correct syntax
config.harfbuzz_features = { 'calt', 'liga', 'ss01', 'ss02', 'ss03', 'ss04', 'ss05', 'ss06', 'ss07', 'ss08', 'ss09' }

-- Semantic Typography: Map SGR attributes to specific Monaspace families
config.font_rules = {
  -- AI drafts/thinking mode → italic → Monaspace Radon
  {
    italic = true,
    intensity = 'Normal',
    font = wezterm.font {
      family = 'Monaspace Radon',
      weight = 'Medium',
      style = 'Italic',
      harfbuzz_features = { 'calt', 'liga', 'ss01', 'ss02', 'ss03', 'ss04', 'ss05', 'ss06', 'ss07', 'ss08', 'ss09' }
    }
  },

  -- Comments/documentation → faint (half intensity) → Monaspace Argon
  -- Prose-like: no ligatures, texture healing only.
  --
  -- Weight is Regular, NOT Light, and that is deliberate. SGR 2 is not just
  -- "comments" — Ink (and therefore Claude Code) uses it as the generic
  -- de-emphasis for UI chrome, including the option descriptions in
  -- AskUserQuestion. WezTerm already halves the foreground colour for half
  -- intensity; stacking a Light weight on top of that dropped stem weight as
  -- well, and the two together made dimmed text genuinely unreadable on a
  -- dark background. Colour is handled on the Claude Code side by the
  -- contrast-tuned agent-core/claude-themes/flexoki-*.json; this rule's job
  -- is just to stop making it worse. Keep Regular or heavier.
  {
    intensity = 'Half',
    italic = false,
    font = wezterm.font {
      family = 'Monaspace Argon',
      weight = 'Regular',
      harfbuzz_features = { 'ss01' }
    }
  },

  -- Diagnostics/errors → curly underline → Monaspace Xenon (slab-serif)
  -- Slabs anchor errors visually; cv11 is Monaspace's slashed-zero variant
  {
    underline = 'Curly',
    font = wezterm.font {
      family = 'Monaspace Xenon',
      weight = 'DemiBold',
      harfbuzz_features = { 'ss01', 'cv11' }
    }
  },

  -- Secondary error patterns (dotted underline)
  {
    underline = 'Dotted',
    font = wezterm.font {
      family = 'Monaspace Xenon',
      weight = 'DemiBold',
      harfbuzz_features = { 'ss01', 'cv11' }
    }
  },

  -- Prompts/input/selection → reverse video → Monaspace Krypton (mechanical)
  -- Geometric letterforms read "terminal-precise" for user input; ExtraBold
  -- lands the prompt on top of reverse-video's already-max contrast
  {
    reverse = true,
    font = wezterm.font {
      family = 'Monaspace Krypton',
      weight = 'ExtraBold',
      harfbuzz_features = { 'ss01' }
    }
  },

  -- Bold text → stay with current family but enable bold
  -- This prevents bold from overriding our semantic mapping
  {
    intensity = 'Bold',
    font = wezterm.font { 
      family = 'Monaspace Neon', 
      weight = 'Bold',
      harfbuzz_features = { 'calt', 'liga', 'ss01', 'ss02', 'ss03', 'ss04', 'ss05', 'ss06', 'ss07', 'ss08', 'ss09' }
    }
  },

  -- Combined states: bold + italic → Radon bold
  {
    italic = true,
    intensity = 'Bold',
    font = wezterm.font { 
      family = 'Monaspace Radon', 
      weight = 'Bold',
      style = 'Italic',
      harfbuzz_features = { 'calt', 'liga', 'ss01', 'ss02', 'ss03', 'ss04', 'ss05', 'ss06', 'ss07', 'ss08', 'ss09' }
    }
  },
}

-- Terminal appearance - adaptive Flexoki theme based on system appearance
local function get_appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return 'Light'
end

local function scheme_for_appearance(appearance)
  if appearance:find 'Dark' then
    return 'flexoki-dark'
  else
    return 'flexoki-light'
  end
end

config.color_scheme = scheme_for_appearance(get_appearance())

-- Re-apply scheme on every window config reload and on system light↔dark
-- toggle. window:get_appearance() is always available, unlike wezterm.gui
-- at config-parse time.
wezterm.on('window-config-reloaded', function(window, _pane)
  local scheme = scheme_for_appearance(window:get_appearance())
  local overrides = window:get_config_overrides() or {}
  if overrides.color_scheme ~= scheme then
    overrides.color_scheme = scheme
    window:set_config_overrides(overrides)
  end
end)
config.window_background_opacity = 0.95
config.text_background_opacity = 1.0

-- Status bar configuration (for ccstatusline integration)
config.status_update_interval = 300 -- ms, matches Claude Code frequency

-- Window configuration
config.window_decorations = "RESIZE"
config.window_padding = {
  left = 8,
  right = 8,
  top = 8,
  bottom = 0,
}

-- Cell-quantization sliver fix: WezTerm sizes the tab content area in whole
-- cells, so when (window_size − chrome) isn't an exact multiple of cell_size
-- a small (1-3px) gap appears below the last row and right of the last col.
-- Absorb the vertical gap into window_padding.top (with bottom=0 so the
-- tmux status line touches the edge) and the horizontal gap into
-- window_padding.right (with left=0 so the status line starts flush left).
--
-- Compute slivers from cell_height/cell_width (font-derived, padding-
-- invariant), NOT from tab_pixel_height/width. Earlier attempts used
-- `window − tab`, which is degenerate: growing padding by Δ reduces
-- available cell space by Δ, so tab stays identical and the formula keeps
-- demanding another Δ on every resize → padding grew without bound.
local BASE_TOP = 8
local function snap_padding_to_cells(window, pane)
  local tab = pane:tab()
  if not tab then return end
  local tab_size = tab:get_size()
  if not tab_size or tab_size.pixel_height == 0 or tab_size.rows == 0
    or tab_size.pixel_width == 0 or tab_size.cols == 0 then return end
  local dims = window:get_dimensions()
  if dims.pixel_height == 0 or dims.pixel_width == 0 then return end

  local cell_h = tab_size.pixel_height / tab_size.rows
  local cell_w = tab_size.pixel_width / tab_size.cols
  -- Single-tab is the configured common case (hide_tab_bar_if_only_one_tab).
  -- For multi-tab, the wezterm tab bar consumes ~1 cell at the bottom.
  local mux = window:mux_window()
  local n_tabs = mux and #mux:tabs() or 1
  local v_chrome = (n_tabs > 1) and cell_h or 0

  local v_available = dims.pixel_height - BASE_TOP - v_chrome
  local v_sliver = v_available - math.floor(v_available / cell_h) * cell_h
  local new_top = math.floor(BASE_TOP + v_sliver)

  local h_sliver = dims.pixel_width - math.floor(dims.pixel_width / cell_w) * cell_w
  local new_right = math.floor(h_sliver)

  local overrides = window:get_config_overrides() or {}
  local current = overrides.window_padding or {}
  if current.top == new_top and current.bottom == 0
     and current.left == 0 and current.right == new_right then return end
  overrides.window_padding = { left = 0, right = new_right, top = new_top, bottom = 0 }
  window:set_config_overrides(overrides)
end

wezterm.on('window-resized', function(window, pane)
  snap_padding_to_cells(window, pane)
end)

-- Font-size change doesn't fire window-resized (window stays fixed when
-- adjust_window_size_when_changing_font_size=false), so the pinch keybindings
-- emit this custom event after IncreaseFontSize/DecreaseFontSize to re-snap.
wezterm.on('readjust-padding', function(window, pane)
  snap_padding_to_cells(window, pane)
end)

-- Tab configuration
config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = true
-- Retro (non-fancy) tab bar fully collapses when hidden; the fancy bar
-- leaves a small fringe at the bottom on macOS even with hide_tab_bar set.
config.use_fancy_tab_bar = false

-- Option-as-Alt (macOS ONLY -- claude-dotfiles-yme.10).
--
-- On macOS, Option is a compose modifier, so it must be explicitly demoted to
-- Meta for the prefix-less tmux Alt-bindings in AGENTS.core.md to work. macOS
-- composed keys (Opt+e for e-acute etc.) become unavailable -- fine for a dev
-- terminal, and keeps one set of bash/tmux muscle memory across platforms.
-- Ref: claude-dotfiles-dg8.
--
-- DO NOT carry this to Windows or Linux. There is no compose layer on those
-- platforms: Alt is already a true modifier and the whole Option+... table
-- ports as Alt+... unchanged. The real Windows risk is the OPPOSITE one --
-- the OS or terminal swallowing Alt for menu activation -- which is a
-- `showkey -a` test (expect ^[n), not something this setting fixes.
if is_darwin then
  config.send_composed_key_when_left_alt_is_pressed = false
  config.send_composed_key_when_right_alt_is_pressed = false
end

config.keys = {
  -- Portable: Shift+Enter -> ESC CR, for multi-line input in TUIs.
  {key="Enter", mods="SHIFT", action=wezterm.action{SendString="\x1b\r"}},
}

-- PinchBar bindings are macOS-only (claude-dotfiles-yme.10): PinchBar is a
-- macOS trackpad utility, and CMD maps to the Windows/Super key elsewhere,
-- where Win+] and Win+/ are claimed by the OS shell -- so binding them on
-- Windows would be both useless and hostile.
--
-- PinchBar's "Font Size" preset emits Cmd+keycode-44 / Cmd+keycode-30
-- (= / - on a German layout; / and ] on US). Bind both so trackpad pinch-out
-- grows the font and pinch-in shrinks it. Swap the two actions if the
-- direction feels inverted. Each chains to readjust-padding so the
-- cell-quantization snap re-runs after the font change (font changes don't
-- fire window-resized when adjust_window_size_when_changing_font_size=false).
if is_darwin then
  table.insert(config.keys, {key="]", mods="CMD", action=wezterm.action.Multiple{
    wezterm.action.IncreaseFontSize,
    wezterm.action.EmitEvent 'readjust-padding',
  }})
  table.insert(config.keys, {key="/", mods="CMD", action=wezterm.action.Multiple{
    wezterm.action.DecreaseFontSize,
    wezterm.action.EmitEvent 'readjust-padding',
  }})
end

return config