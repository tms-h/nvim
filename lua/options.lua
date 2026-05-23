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
opt.wrap = true
opt.termguicolors = true
opt.showmode = false

opt.clipboard = "unnamedplus"
opt.undofile = true
opt.undodir = vim.fn.stdpath("state") .. "/undo"
opt.updatetime = 250
opt.timeoutlen = 400
opt.completeopt = { "menuone", "noselect" }

opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true

vim.cmd("filetype plugin indent on")
opt.autoindent = true

if vim.g.neovide then
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

  -- Floating window shadows
  vim.g.neovide_floating_shadow = true
  vim.g.neovide_floating_z_height = 10
  vim.g.neovide_light_angle_degrees = 45
  vim.g.neovide_light_radius = 5

  -- QoL
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_remember_window_size = true
  vim.g.neovide_input_macos_option_key_is_meta = "only_left"

  -- Padding so text isn't jammed against the edges
  vim.g.neovide_padding_top = 8
  vim.g.neovide_padding_bottom = 4
  vim.g.neovide_padding_left = 8
  vim.g.neovide_padding_right = 8
end
