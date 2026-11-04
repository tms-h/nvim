-- Neovide only: font, motion, floats and padding. Colours and opacity are
-- theme.lua.
if not vim.g.neovide then
  return
end

local g = vim.g
local is_macos = require("util").is_macos

vim.o.guifont = "JetBrainsMono Nerd Font Mono:h14"
-- Start two zoom steps below the font size; Alt/Cmd+0 comes back here.
g.default_scale = 1 / 1.25 ^ 2
g.neovide_scale_factor = g.default_scale

-- Motion: quick and consistent. The cursor and scrolling glide for 0.05 s
-- (short cursor hops 0.03 s), also while typing; not on the command line.
-- Windows move at once.
g.neovide_refresh_rate = is_macos and 120 or 240
g.neovide_refresh_rate_idle = 5
g.neovide_cursor_animation_length = 0.05
g.neovide_cursor_short_animation_length = 0.03
g.neovide_cursor_trail_size = 0.3
g.neovide_cursor_animate_in_insert_mode = true
g.neovide_cursor_animate_command_line = false
g.neovide_cursor_vfx_mode = ""
g.neovide_scroll_animation_length = 0.05
g.neovide_scroll_animation_far_lines = 0
g.neovide_position_animation_length = 0

-- Floats (hover, completion docs, picker) sit on the same surface with a
-- soft shadow, a slight blur behind and square corners.
g.neovide_floating_shadow = true
g.neovide_floating_z_height = 10
g.neovide_light_angle_degrees = 45
g.neovide_light_radius = 5
g.neovide_floating_blur_amount_x = 2.0
g.neovide_floating_blur_amount_y = 2.0
g.neovide_floating_corner_radius = 0.0

g.neovide_padding_top = 0
g.neovide_padding_bottom = 0
g.neovide_padding_left = 0
g.neovide_padding_right = 0
-- SUPER+W with unsaved changes: ask to save instead of refusing with E37.
g.neovide_confirm_quit = true
g.neovide_hide_mouse_when_typing = true
g.neovide_remember_window_size = true
if is_macos then
  -- Cmd reaches Neovim as <D-...> (every Cmd chord in keys.lua).
  g.neovide_input_use_logo = true
  g.neovide_input_macos_option_key_is_meta = "only_left"
  -- Blur the desktop behind the glass, like Hyprland's blur on Omarchy.
  g.neovide_window_blurred = true
  -- Keep redrawing while idle: after Rift resizes the window (Alt+F fullscreen),
  -- Neovide otherwise kept the old grid size until the next key or mouse move.
  -- Costs some battery.
  g.neovide_no_idle = true
  -- Fullscreen without a macOS Space or its slide animation, covering the
  -- menu-bar row. Rift's Alt+F (~/.config/rift/scripts/fullscreen.sh) turns
  -- g:neovide_fullscreen on and off through this Neovim's server socket.
  g.neovide_macos_simple_fullscreen = true
end

-- The pointer's position is needed for the divider hover (dividers.lua).
vim.o.mousemoveevent = true
