# Neovim 0.11/0.12 + Neovide: how respected configs are set up

Researched 2026-10-23. Only what each source states; `[check]` = not confirmed.
Versions at time of writing: Neovim 0.11.0 released 2025-03-26, 0.12.0 released
2026-03-29; Neovide latest 0.16.2 (2026-04-14) (GitHub release API).

---

## 1. Neovide docs

### 1a. Configuration page — https://neovide.dev/configuration.html

- All settings are `vim.g.neovide_*` globals, changeable at runtime. `vim.g.neovide`
  is set only inside Neovide ("treat it as a GUI check").
- Font is the standard `guifont` option: `Primary,Fallback1:hX:b:i:#e-...:#h-...`
  (e.g. `Source Code Pro:h14`).
- Real defaults (read from Neovide 0.16.2 source, `src/renderer/mod.rs`,
  `cursor_renderer/mod.rs`, `window/settings.rs`; the docs page mostly shows
  "example" values that equal these):

| setting | default | doc note |
|---|---|---|
| `neovide_opacity` (alias `neovide_transparency`) | 1.0 | whole window, 0.0–1.0 |
| `neovide_normal_opacity` | 1.0 | only the Normal background; "Set it to 1 to disable" |
| `neovide_window_blurred` | false | blur behind window; doc says macOS only; code calls winit `set_blur` when opacity < 1 on all platforms (PR #2440) |
| `neovide_floating_blur_amount_x/_y` | 2.0 / 2.0 | blur behind floating windows |
| `neovide_floating_shadow` | true | with `floating_z_height` 10, `light_angle_degrees` 45, `light_radius` 5 |
| `neovide_floating_corner_radius` | 0.0 | 0.0–1.0 of line height |
| `neovide_padding_top/bottom/left/right` | 0 | filled with background colour |
| `neovide_scroll_animation_length` | 0.3 s | |
| `neovide_scroll_animation_far_lines` | 1 | lines animated on multi-screen jumps; 0 = snap |
| `neovide_position_animation_length` | 0.15 s | window moves e.g. `:split`; 0 disables |
| `neovide_cursor_animation_length` | 0.150 s | 0 disables |
| `neovide_cursor_short_animation_length` | 0.04 s | moves of 1–2 chars |
| `neovide_cursor_trail_size` | 1.0 | 0.0–1.0 (1.0 = front jumps immediately, see 0.15.0 notes) |
| `neovide_cursor_animate_in_insert_mode` / `_command_line` | true / true | |
| `neovide_cursor_vfx_mode` | "" | railgun, torpedo, pixiedust, sonicboom, ripple, wireframe (string or list) |
| `neovide_cursor_smooth_blink` | false | needs `guicursor` blink settings |
| `neovide_refresh_rate` / `_idle` | 60 / 5 | refresh_rate "only applies without vsync" |
| `neovide_hide_mouse_when_typing` | false | |
| `neovide_scale_factor` | 1.0 | multiplied with OS scale and font size |
| `neovide_text_gamma` / `_contrast` | 0.0 / 0.5 | |
| `neovide_input_macos_option_key_is_meta` | "none" | both / only_left / only_right / none |
| `neovide_theme` | auto | changed in 0.16.0: `background` follows system theme unless you set it |
| `neovide_confirm_quit` | true | |
| `neovide_cursor_hack` | — | "Prevents cursor flicker to the command line. May be buggy." |
| `neovide_progress_bar_*` | enabled | height 5.0, speed 200.0, hide delay 0.2 (since 0.16.0) |

- Removed/changed: `neovide_background_color` removed in 0.16.0 (use `neovide_opacity`);
  `experimental_layer_grouping` (no prefix) groups layers so blur/shadow apply to the
  group, "can cause other rendering problems".

### 1b. Config file — https://neovide.dev/config-file.html

- `$XDG_CONFIG_HOME/neovide/config.toml` (or `$NEOVIDE_CONFIG`). Startup-only options.
- Defaults: `fork=false`, `frame="full"`, `idle=true`, `maximized=false`,
  `vsync=true`, `srgb=false` (Linux/macOS), `tabs=true`, `title-hidden=false`,
  `no-multigrid=false`, `mouse-cursor-icon="arrow"`; optional `wayland-app-id`,
  `x11-wm-class`, `neovim-bin`, `grid`/`size` (exclusive with `maximized`).
- `[font]` table: `normal = []` (bundled Fira Code Nerd Font), `size = 14.0`, plus
  `bold`, `italic`, `features`, `width`, `hinting`, `edging`, `underline_offset`.
- `[box-drawing]` (experimental since 0.15.0): Neovide draws box glyphs itself,
  "eliminates gaps between characters"; sizes `default = [2, 4]` px. The page is
  inconsistent on whether `native` or `font-glyph` is the default [check].

### 1c. FAQ — https://neovide.dev/faq.html

- Cmd/Ctrl copy-paste: Neovide only forwards keys; you map them yourself. Example:
  `vim.keymap.set({"n","i","v","c","t"}, "<D-v>", paste)`; on Linux/Windows use
  `<C-*>`.
- Float/popup transparency: use `winblend` / `pumblend` (0–100).
- Runtime zoom: `change_scale_factor(1.25)` / `(1/1.25)` bound to `<C-=>` / `<C-->`.
- Runtime opacity (macOS example): `<D-]>`/`<D-[>` change `neovide_opacity` by 0.01.
- Neovim is not started from an interactive shell, so `.bashrc`/`.zshrc` env is not
  read; put env in `.zprofile`/`.zlogin`.
- Terminal colours: colorscheme must set `g:terminal_color_0..15`.
- "Turning off all animations": `position_animation_length = 0`,
  `cursor_animation_length = 0.00`, `cursor_trail_size = 0`,
  `cursor_animate_in_insert_mode = false`, `cursor_animate_command_line = false`,
  `scroll_animation_far_lines = 0`, `scroll_animation_length = 0.00`.
- No FAQ entry on Wayland/Hyprland or font choice.

### 1d. Neovide 0.15.0 release notes — https://github.com/neovide/neovide/releases/tag/0.15.0 (2025-04-02)

- "The default cursor animation has been changed to feel more responsive. The front
  of the cursor now moves to the destination immediately, while the trail is
  animating."
- "To restore the feel of older Neovide versions, you can start by lowering
  `neovide_cursor_trail_size` to 0.7".
- The new low-latency cursor "also makes it possible to lower the
  `neovide_scroll_animation_length` setting".
- Box drawing by Neovide added (experimental).

### 1e. Neovide discussion #3077 "favourite defaults" — https://github.com/neovide/neovide/discussions/3077

- fredizzimo (Neovide maintainer): `cursor_trail_size = 1.0`,
  `cursor_animation_length = 0.04`; prefers scroll "slightly faster than the default".
- bassamsdata: `cursor_animation_length = 0.1`, `trail_size = 0.3`,
  `scroll_animation_length = 0.3`; 0.04 was too fast to see.
- bodograumann: turned cursor animation off (`0`, short `0`, no vfx) after trying
  railgun.
- helins: `cursor_animation_length = 0.06`, `trail_size = 1`, "Looking good!".

### 1f. Neovide + Hyprland

- Issue #1936 (Hyprland 0.27): transparency rendered but compositor blur did not
  apply; closed 2024-03-28 by PR #2440 "Apply winit window blur setting on all
  platforms". https://github.com/neovide/neovide/issues/1936
- Issue #1918: fullscreen transparent Neovide on Hyprland showed the wallpaper
  changing behind it. https://github.com/neovide/neovide/issues/1918 [check status]
- Issue #3006 (macOS, milestone 0.17.0): `neovide_transparency` also fades
  statusline/tabline; `neovide_opacity` does not combine with blur.
  https://github.com/neovide/neovide/issues/3006
- Hyprland discussion #12229: high blur passes made transparent windows look opaque;
  lowering blur fixed it. https://github.com/hyprwm/Hyprland/discussions/12229
- No source found giving a recommended Neovide opacity value for Hyprland.

---

## 2. LazyVim — https://github.com/LazyVim/LazyVim (main, fetched 2026-10-23)

- Pitch: "the flexibility to tweak your config as needed, along with the convenience
  of a pre-configured setup"; "Comes with a wealth of plugins pre-configured".
- Requires Neovim >= 0.11.2 (README). Uses lazy.nvim, not vim.pack.
- Core plugin specs (outside extras): 30 repos, incl. bufferline, catppuccin,
  tokyonight, flash, lazydev, noice, persistence, snacks, todo-comments, trouble,
  ts-comments, which-key, gitsigns, grug-far, mason + mason-lspconfig, nvim-lint,
  nui, lspconfig, lualine, plenary, mini.ai/icons/pairs, nvim-treesitter +
  textobjects, conform, nvim-ts-autotag. Default extras add blink.cmp,
  snacks picker and snacks explorer. 117 extra files available.
- Neovide: only two mentions, both "turn off when in Neovide":
  `extras/ui/mini-animate.lua` and `extras/ui/smear-cursor.lua` use
  `cond = vim.g.neovide == nil`. CHANGELOG: "mini.animate: disable when in Neovide".
  No Neovide extra and no `neovide_*` settings.
- Keymap philosophy: space leader, every prefix is a named which-key group:
  `<leader><tab>` tabs, `c` code, `d` debug, `f` file/find, `g` git, `gh` hunks,
  `q` quit/session, `s` search, `u` ui (toggles), `x` diagnostics/quickfix,
  `b` buffer, `w` windows (proxy of `<C-w>`); plus `[`/`]` prev/next, `g` goto,
  `gs` surround, `z` fold.
- Core keymaps (config/keymaps.lua): `<C-h/j/k/l>` window nav, `<A-j>/<A-k>` move
  lines, `<Esc>` clears hlsearch, `<C-s>` save in i/x/n/s, `gco`/`gcO` add comment
  below/above.

## 3. kickstart.nvim — https://github.com/nvim-lua/kickstart.nvim/blob/master/init.lua

- "Kickstart.nvim is *not* a distribution." "The goal is that you can read every
  line of code, top-to-bottom, understand what your configuration is doing, and
  modify it to suit your needs." Single `init.lua`, 1039 lines.
- Now uses the built-in `vim.pack` (so effectively needs 0.12; README says use the
  latest stable); links echasnovski's vim.pack guide; README recommends committing
  the lockfile.
- 19 plugins via `vim.pack.add`: guess-indent, gitsigns, which-key, tokyonight,
  todo-comments, mini.nvim (ai, surround, statusline, icons), plenary, telescope,
  telescope-ui-select, telescope-fzf-native, fidget, nvim-lspconfig, mason,
  mason-lspconfig, mason-tool-installer, conform, LuaSnip (2.*), blink.cmp (1.*),
  nvim-treesitter (main branch). Commented-out extras: debug, indent_line, lint,
  autopairs, neo-tree.
- LSP: built-in `vim.lsp.config()` + `vim.lsp.enable()`; mason-lspconfig with
  `automatic_enable = false`.
- Keymaps: leader and localleader = space; normal `<Esc>` → `nohlsearch`;
  `<leader>q` diagnostics loclist; terminal `<Esc><Esc>` → `<C-\><C-n>`;
  `<C-h/j/k/l>` window focus (`<C-S-hjkl>` move-window lines commented out);
  `<leader>s*` search (sf files, sg grep, sh help, sk keymaps, sd diagnostics,
  sr resume, s. recent, sn nvim config); `<leader><leader>` buffers; `<leader>f`
  format; LSP on the built-in `gr` prefix (grn, gra, grD, …).
  which-key groups: `<leader>s` Search, `<leader>t` Toggle, `<leader>h` Git hunk,
  `gr` LSP actions.
- mini.ai remaps around/inside-next to `aa`/`ii` "to avoid conflicts with the
  built-in incremental selection mappings on Neovim>=0.12".
- Options: number, mouse=a, showmode=false, clipboard=unnamedplus (inside
  `vim.schedule`), breakindent, undofile, ignorecase+smartcase, signcolumn=yes,
  updatetime=250, timeoutlen=300, splitright/below, list + listchars,
  inccommand=split, cursorline, scrolloff=10, confirm; diagnostics
  `virtual_text = true, virtual_lines = false`.
- Neovide: not mentioned.

## 4. folke's dotfiles — https://github.com/folke/dot (nvim/lua/config/options.lua)

- Neovide block (whole thing):
  ```lua
  if vim.g.neovide then
    vim.o.guifont = "Fira Code,Symbols Nerd Font Mono:h34"
    vim.g.neovide_scale_factor = 0.3
  end
  ```
  (Large font scaled down, i.e. ~h10 effective.) No animation/opacity settings, so he
  runs Neovide defaults.
- Same file: `cmdheight = 0`, `mousescroll = "ver:1,hor:1"`, `backup = true`,
  disables python/perl/ruby/node providers, makes all keymaps silent by default.
- A commented-out smear-cursor spec is disabled in kitty and Neovide:
  `cond = not (vim.env.KITTY_PID or vim.g.neovide)`.
- Rest of config is LazyVim.

## 5. echasnovski (mini.nvim author) — https://github.com/echasnovski/nvim

- Structure: tiny `init.lua` + `plugin/10_options.lua`, `20_keymaps.lua`,
  `30_mini.lua`, `40_plugins.lua` (numbered so load order is explicit); `after/lsp/`,
  `after/ftplugin/`. README: `plugin/` avoids `lua/` module name clashes and is
  easier to `:source`.
- Plugin manager: `vim.pack` (shims `vim.pack.add` to `packadd` on <0.12);
  `nvim-pack-lock.json` committed. 11 plugins in the lockfile: mini.nvim,
  nvim-lspconfig, mason, conform, nvim-treesitter (+textobjects),
  friendly-snippets, markdown-preview, neoterm, vim-dispatch, vim-test.
  ~40 mini modules enabled (mini.completion, mini.pick, mini.files, mini.clue,
  mini.statusline, mini.diff, mini.git, mini.snippets, mini.cmdline, …).
  `mini.animate` is commented out (`scroll = { enable = false }`).
- Built-ins used on 0.12: `winborder = 'bold'`, `pumborder = 'bold'`,
  `pummaxwidth = 100`, `completetimeout = 100`,
  `require('vim._core.ui2').enable({ enable = true })`; `vim.lsp.config('*', …)` +
  `vim.lsp.enable({...})`; diagnostics `virtual_lines = false`;
  `-- vim.o.autocomplete = true` left commented (uses mini.completion instead).
- Space leader; mini.clue groups `<Leader>b` Buffer, `e` Explore, `f` Find,
  `g` Git, `l` Language, `L` Lua/Log, `m` Map, `o` Other, `s` Session,
  `t` Terminal, `T` Test, `v` Visits.
- Neovide: zero mentions in the repo.

### 5b. echasnovski, "A guide to vim.pack" (2026-03-13) — https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack

- `vim.pack.add()` = "smart `:packadd`": installs missing plugins (git only, in
  parallel) and loads them.
- Lockfile `nvim-pack-lock.json` lives in config, versioned, not hand-edited;
  bootstraps new machines; `vim.pack.update()` opens a confirm buffer (`:write`
  applies), `target = 'lockfile'` restores.
- Recommends a single `vim.pack.add()` call as "the most robust approach";
  alternative is one call per plugin in `plugin/` files.
- Lazy loading: use "moderately"; extreme lazy loading adds "hidden cognitive
  overhead"; never lazy-load colorscheme/statusline. Patterns: `vim.schedule()` or
  `InsertEnter`/`CmdlineEnter` autocmds. His config starts in ~38 ms.

## 6. Neovim built-ins that replace plugins

Sources: `:h news-0.10`, `:h news-0.11`, `:h news-0.12`
(runtime/doc/news-0.1x.txt on neovim master).

- 0.10: built-in commenting `gc`/`gcc` ("Nvim now includes |commenting| support");
  `]d`/`[d`; LSP inlay hints.
- 0.11:
  - `vim.lsp.config()` "define default configurations for servers… can be specified
    in `lsp/<name>.lua`"; `vim.lsp.enable()` enables them (replaces most of
    nvim-lspconfig's setup role; lspconfig still ships the `lsp/*.lua` files).
  - Default LSP maps: `grn` rename, `grr` references, `gri` implementation,
    `gO` document symbols, `gra` code action (n+v), insert/select `CTRL-S`
    signature help.
  - unimpaired-style maps: `[q ]q [Q ]Q` quickfix, `[b ]b` buffers (plus loclist,
    args, tags); `]d`/`[d` accept a count.
  - Diagnostics: "virtual_text" handler disabled by default; new "virtual_lines"
    handler; `virtual_text.current_line` option.
  - `'winborder'` sets the default border for floating windows.
  - `'completeopt'` gains `fuzzy` and `preinsert`; `vim.lsp.completion.enable()`
    gains `convert`.
  - LSP folding `vim.lsp.foldexpr()`; OSC 52 clipboard fallback; `:terminal`
    understands OSC 52 copy.
- 0.12:
  - "Built-in plugin manager: |vim.pack|".
  - `'autocomplete'` "enables |ins-autocompletion|" (as-you-type, no plugin);
    `'complete'` gains `o` (omnifunc) / `F{func}` sources and `^limit`;
    `'completeopt'` `nearest`; `'pummaxwidth'`, `'pumborder'`, `completetimeout`.
  - `vim.lsp.completion.enable()` gains `cmp` ordering option; inline completion
    (`textDocument/inlineCompletion`), document color, linkedEditingRange,
    onTypeFormatting, codeLens reimplemented, selectionRange.
  - New default maps: `grt` type definition, `grx` codelens run;
    `v_an`/`v_in`/`]n`/`[n` treesitter incremental selection.
  - `:lsp` command manages clients; `vim.lsp.enable()` starts/stops as needed.
  - Default `statusline` shows `vim.diagnostic.status()`, LSP progress, terminal exit
    code, `busy` ◐.
  - `'winborder'` adds "bold" and custom styles.
  - `ui2`: "redesign of the core messages and commandline UI"; "Avoids 'Press ENTER'
    interruptions", highlights cmdline as you type, pager as buffer+window;
    "Currently experimental. To enable it: `require('vim._core.ui2').enable()`".
  - `:Undotree`, `:DiffTool`, `:restart` ("restarts Nvim and reattaches all UIs"),
    `:connect`, `vim.net.request()`, markdown treesitter highlighting on by default,
    `exrc` searched in parent dirs, `diffopt` adds `inline:char`.
  - Terminal: "[Process exited]" now virtual text; exit code in statusline.

## 7. Community Neovide setups

(r/neovim pages were blocked to the fetcher (403 / refused); the r/neovim
"Neovide 0.15.0 released" thread https://www.reddit.com/r/neovim/comments/1jqazko/
repeats the release notes above; comments not read.)

- **snehilshah/nvim** `lua/config/neovide.lua` — https://mintlify.wiki/snehilshah/nvim/reference/config/neovide
  `guifont = "Maple Mono NF:h11"`, `opacity = 0.85`, `normal_opacity = 0.85`,
  `window_blurred = true`, floating blur 6.0/6.0, shadow on (z 10, light 45/5),
  `floating_corner_radius = 2.0` (outside the documented 0–1 range),
  `cursor_smooth_blink = true`, paste on `<C-S-v>` via `nvim_paste(getreg("+"))`.
- **AstroNvim Neovide recipe** — https://docs.astronvim.com/recipes/neovide/
  Only `guifont = "Source Code Pro:h14"`, `linespace = 0`, `scale_factor = 1.0`,
  padding 0, and `<C-=>`/`<C-->`/`<C-0>` zoom maps; no animation changes.
- **linkarzu, "Neovim or Neovide, what is the difference?"** (2024, updated
  2026-06-10, macOS) — https://linkarzu.com/posts/neovim/neovim-vs-neovide/
  Sets `frame = "transparent"` in config.toml; maps `<D-s>/<D-c>/<D-v>`; likes
  "Nice cursor animations", "Smooth scrolling", "smoother than kitty" on big
  markdown; misses kitty image support.
- **mimikun dotfiles** — https://github.com/mimikun/dotfiles (neovide.lua)
  Mostly docs defaults; `guifont = "Cica:h14"`, `neovide_transparency = 0.93`,
  `scroll_animation_length = 0.3`.

### 7b. What public configs actually set (GitHub code search, Lua, 2026-10-23)

Top ~100 "best match" hits per query, not a random sample; doc example values get
copy-pasted. Total matching files in brackets.

- `neovide_scroll_animation_length` [1532]: `0`/`0.0`/`0.00` 38, `0.3` 21,
  `0.1` 14, `0.2` 12, `0.05` 4, `0.25` 3, `0.5` 3, `0.15` 2.
- `neovide_cursor_animation_length` [2204]: `0`/`0.00` 42, `0.05` 9, `0.1` 8,
  `0.08` 6, `0.01` 6, `0.13` 5, `0.03` 5, `0.15` 3, `0.2` 3.
- `neovide_cursor_trail_size`: `0` 13, `0.3` 9, `0.5` 6, `0.8` 4, `0.2` 4, `0.7` 2.
- `neovide_position_animation_length` [613]: `0`/`0.0` 50, `0.15` 14, `0.1` 10,
  `0.05` 4, `0.3` 4, `0.2` 3.
- `neovide_opacity` [1078]: `0.8` 18, `1`/`1.0` 23, `0.9`/`0.90` 13, `0.95` 10,
  `0.85` 8, `0.92` 6. `neovide_normal_opacity`: `0.8` 14, `1`/`1.0` 10, `0.9` 3.
- `guifont` in Neovide files [4200]: JetBrains Mono 24, Hack 7, Caskaydia Cove 4,
  0xProto 4, Fira Code 5, Meslo 3, Iosevka (incl. Term) 4; sizes `:h14` 23,
  `:h11` 13, `:h18` 10, `:h12` 9, `:h13` 8, `:h10` 8, `:h16` 7.

---

## Recurring opinions

- **Plugin count is going down, and built-ins replace whole categories.**
  kickstart 19 plugins, echasnovski 11 repos (one is mini.nvim with ~40 modules),
  LazyVim 30 core + 3 default extras. All three use `vim.lsp.config`/`vim.lsp.enable`
  (LazyVim calls them from its `opts.servers` layer). kickstart and echasnovski both moved to
  `vim.pack` with a committed lockfile; LazyVim stays on lazy.nvim.
- **What still comes from plugins in all three:** treesitter (nvim-treesitter), a
  formatter (conform), mason for installing servers, lspconfig for server defaults,
  a fuzzy picker (telescope / snacks / mini.pick), git signs (gitsigns / mini.diff),
  a key-hint popup (which-key / mini.clue), completion (blink.cmp / mini.completion).
  Nobody here relies on 0.12 `'autocomplete'` yet (echasnovski has it commented out).
- **Built-ins people do adopt:** `gc` commenting (LazyVim adds only `gco/gcO` on
  top), default `gr*` LSP maps (kickstart keeps the `gr` prefix for its LSP maps),
  `winborder` (echasnovski `bold`), ui2 (echasnovski on).
- **Neovide animation:** defaults are scroll 0.3 s, cursor 0.15 s (short 0.04),
  trail 1.0, position 0.15 s. In public configs the single most common choice for
  every animation length is **0 (off)**; among people who keep it on, scroll
  0.1–0.3 and cursor 0.05–0.1. Neovide's own maintainer uses cursor 0.04 + trail
  1.0 and wants scroll "slightly faster" than 0.3. Distros (LazyVim, folke) disable
  in-editor animation plugins (mini.animate, smear-cursor) under Neovide and let
  Neovide do it with defaults.
- **Opacity:** when transparent, 0.8–0.95 (docs example 0.8 is the most copied);
  `normal_opacity` usually equals `opacity`. Several respected configs (folke,
  AstroNvim, kickstart, echasnovski) set no opacity at all.
- **Font:** a Nerd Font or a Nerd-symbols fallback (`"Fira Code,Symbols Nerd Font
  Mono"`); JetBrains Mono is the most common family; sizes cluster at h11–h14.
  Neovide's bundled default is Fira Code Nerd Font 14.
- **Keymaps:** space leader everywhere; leader keys grouped by first letter and
  shown in which-key/mini.clue (f/s find/search, g git, b buffer, c/l code/language,
  t/u toggles/ui, x diagnostics); `<C-h/j/k/l>` window nav (kickstart, LazyVim);
  `<Esc>` clears search highlight (kickstart, LazyVim); terminal `<Esc><Esc>`
  (kickstart); `<C-=>/<C-->` zoom and a self-made paste map in Neovide (FAQ,
  AstroNvim, snehilshah).

## Where they disagree

- **One file vs modules:** kickstart = one 1039-line `init.lua` "read every line";
  echasnovski = numbered `plugin/*.lua` files; LazyVim = framework + `lua/plugins/*`
  specs and 117 opt-in extras.
- **Plugin manager / lazy loading:** lazy.nvim with heavy lazy-loading (LazyVim)
  vs `vim.pack` with "moderate" lazy loading and one `vim.pack.add` (echasnovski,
  kickstart).
- **Ecosystem:** folke's snacks/noice/trouble/flash stack vs echasnovski's
  all-in-mini.nvim vs kickstart's mixed best-of (telescope, blink.cmp, conform).
- **Completion:** blink.cmp (kickstart, LazyVim default) vs mini.completion
  (echasnovski) vs built-in `'autocomplete'`/`vim.lsp.completion` (nobody here yet).
- **Messages/cmdline:** LazyVim ships noice.nvim; echasnovski uses built-in ui2;
  folke personally sets `cmdheight = 0`; kickstart uses stock UI.
- **Neovide animation:** maintainer and Neovide defaults favour animation (trail 1.0,
  fast cursor); a large share of public configs zero everything (FAQ even gives the
  full "off" list); bassamsdata found 0.04 cursor too fast to see.
- **Neovide transparency:** docs and community configs show 0.8–0.85 with blur;
  the big-name configs stay opaque. On Hyprland, blur comes from the compositor;
  Neovide's `window_blurred` is documented as macOS-only, while the code calls winit
  `set_blur` on all platforms [check whether Hyprland honours it].
- **Diagnostics display:** kickstart `virtual_text = true, virtual_lines = false`;
  echasnovski `virtual_lines = false`; 0.11 default has virtual_text off.
