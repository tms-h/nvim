local opt = vim.opt

opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = -1

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.splitbelow = true
opt.splitright = true
-- Opening a vertical sidebar must not equalize horizontal split heights.
opt.eadirection = "hor"
-- Preserve the first visible line when horizontal splits are resized.
opt.splitkeep = "topline"
opt.wrap = true
opt.termguicolors = true
opt.showmode = false
opt.cmdheight = 0
opt.confirm = true
-- Keep :substitute from visually rewriting the buffer while it is being typed.
opt.inccommand = ""
opt.jumpoptions = "view"
opt.virtualedit = "block"
opt.winborder = "rounded"

opt.list = true
opt.listchars = {
  tab = "» ",
  trail = "·",
  nbsp = "␣",
}

-- Start files unfolded; zc/zo, za and zM/zR remain available on demand.
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldcolumn = "1"

opt.clipboard = "unnamedplus"
opt.undofile = true
opt.undodir = vim.fn.stdpath "state" .. "/undo"
opt.updatetime = 250
opt.timeoutlen = 400
opt.completeopt = { "menuone", "noselect" }

opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true

vim.cmd "filetype plugin indent on"
opt.autoindent = true

if vim.g.neovide then
  -- Let Neovim report pointer movement so split dividers can react on hover.
  opt.mousemoveevent = true

  vim.o.guifont = "JetBrainsMono Nerd Font Mono:h14"

  -- 120Hz for ProMotion, drop to 5fps when idle (saves battery)
  vim.g.neovide_refresh_rate = 120
  vim.g.neovide_refresh_rate_idle = 5

  -- Snappy cursor: fast animation, tight trail
  vim.g.neovide_cursor_animation_length = 0.04
  vim.g.neovide_cursor_trail_size = 0.3
  vim.g.neovide_cursor_animate_in_insert_mode = true
  vim.g.neovide_cursor_animate_command_line = true

  -- No particles, just the classic Neovide smear
  vim.g.neovide_cursor_vfx_mode = ""

  -- Instant scroll and window movement
  vim.g.neovide_scroll_animation_length = 0.12
  vim.g.neovide_scroll_animation_far_lines = 1
  vim.g.neovide_position_animation_length = 0

  -- Subtle frosted-glass effect without sacrificing code contrast.
  vim.g.neovide_opacity = 0.94
  vim.g.neovide_normal_opacity = 0.84
  if vim.fn.has "macunix" == 1 then
    vim.g.neovide_window_blurred = true
  end
  vim.g.neovide_floating_blur_amount_x = 2.0
  vim.g.neovide_floating_blur_amount_y = 2.0
  opt.winblend = 8
  opt.pumblend = 8

  -- Floating window shadows
  vim.g.neovide_floating_shadow = true
  vim.g.neovide_floating_z_height = 10
  vim.g.neovide_light_angle_degrees = 45
  vim.g.neovide_light_radius = 5

  -- QoL
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_remember_window_size = true
  if vim.fn.has "macunix" == 1 then
    vim.g.neovide_input_use_logo = true
    vim.g.neovide_input_macos_option_key_is_meta = "only_left"
  end

  -- Remove the extra inset around the grid. macOS window chrome is handled by
  -- neovide.toml so its real traffic lights remain movable and functional.
  vim.g.neovide_padding_top = 0
  vim.g.neovide_padding_bottom = 0
  vim.g.neovide_padding_left = 0
  vim.g.neovide_padding_right = 0
end
