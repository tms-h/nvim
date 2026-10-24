-- The divider under the pointer lights up, on the real line: no float drawn
-- on top, no redraw of the screen. Neovim reports where the pointer is (it
-- needs 'mousemoveevent', set in gui.lua); a move that stays on the same
-- line, or off every line, costs one table lookup.
--
-- Neovim draws a window's right and bottom divider with one colour, so
-- colouring a window lights both of its edges. Two styles:
--   "line"    (default) the hovered line alone turns heavy (┃ ━) in the
--             accent colour where no other edge would light with it, else
--             only heavy. Exactly the line a drag would move changes.
--   "colour"  every window along the line gets the accent colour; a window
--             that also has an edge the other way lights that edge too.
-- Pick with vim.g.divider_hover = "line" | "colour".
local M = {}

local api = vim.api
local focus = require "focus"

-- The heavy line and its joints: heavy along the hovered line, light across
-- it, so the line runs unbroken through every junction.
local HEAVY = {
  v = "vert:┃,vertleft:┨,vertright:┠,verthoriz:╂",
  h = "horiz:━,horizup:┷,horizdown:┯,vertleft:┥,vertright:┝,verthoriz:┿",
}

local function leaves(node, out)
  if node[1] == "leaf" then
    out[#out + 1] = node[2]
  else
    for _, child in ipairs(node[2]) do
      leaves(child, out)
    end
  end
  return out
end

local function far_edge(win, vertical)
  local pos = api.nvim_win_get_position(win)
  return vertical and pos[2] + api.nvim_win_get_width(win) or pos[1] + api.nvim_win_get_height(win)
end

---The windows that draw the divider a drag on `winid`'s edge would move: in
---the innermost split of that direction whose side ends on the line, every
---window whose edge sits on it.
function M.windows_on_divider(winid, vertical)
  local edge = far_edge(winid, vertical)
  local function side_ends_on_edge(child)
    for _, win in ipairs(leaves(child, {})) do
      if far_edge(win, vertical) > edge then
        return false
      end
    end
    return true
  end
  local found
  local function walk(node)
    if node[1] == "leaf" then
      return node[2] == winid
    end
    for index, child in ipairs(node[2]) do
      if walk(child) then
        if not found and node[1] == (vertical and "row" or "col") and index < #node[2] and side_ends_on_edge(child) then
          found = {}
          for _, win in ipairs(leaves(node, {})) do
            if far_edge(win, vertical) == edge then
              found[win] = true
            end
          end
        end
        return true
      end
    end
    return false
  end
  walk(vim.fn.winlayout())
  return found or {}
end

-- Does `win` also draw a divider the other way (which colour would light)?
local function has_other_edge(win, vertical)
  if vertical then
    local below = api.nvim_win_get_position(win)[1] + api.nvim_win_get_height(win)
    -- The global status line sits on the last row above the command line.
    return below < vim.o.lines - vim.o.cmdheight - 1
  end
  local right = api.nvim_win_get_position(win)[2] + api.nvim_win_get_width(win)
  return right < vim.o.columns
end

local lit_key
local heavy = {} -- windows given a heavy glyph

local function clear()
  for win in pairs(heavy) do
    if api.nvim_win_is_valid(win) then
      vim.wo[win].fillchars = ""
    end
  end
  heavy = {}
  focus.set_lit {}
end

local function light(wins, vertical)
  clear()
  local style = vim.g.divider_hover or "line"
  local coloured = {}
  for win in pairs(wins) do
    if style == "colour" or not has_other_edge(win, vertical) then
      coloured[win] = true
    end
    if style == "line" then
      vim.wo[win].fillchars = vim.o.fillchars .. "," .. HEAVY[vertical and "v" or "h"]
      heavy[win] = true
    end
  end
  -- In "line" style the colour goes on only if every window on the line can
  -- take it, so a line is never half lit.
  if style == "line" and vim.tbl_count(coloured) ~= vim.tbl_count(wins) then
    coloured = {}
  end
  focus.set_lit(coloured)
end

function M.update()
  local mouse = vim.fn.getmousepos()
  local winid = mouse.winid
  -- On a divider: Neovim reports line 0, except under a pane with a title
  -- row (winbar, focus.lua), where the bottom divider reads as one more
  -- text line; past the pane's own rows or columns is the divider too.
  local on_divider = winid ~= 0
    and api.nvim_win_is_valid(winid)
    and api.nvim_win_get_config(winid).relative == ""
    and (
      (mouse.line == 0 and mouse.column == 0)
      or mouse.winrow > api.nvim_win_get_height(winid)
      or mouse.wincol > api.nvim_win_get_width(winid)
    )
  if not on_divider then
    if lit_key then
      lit_key = nil
      clear()
    end
    return
  end
  local vertical = mouse.screencol - 1 == far_edge(winid, true)
  local key = winid .. (vertical and "v" or "h")
  if key == lit_key then
    return
  end
  lit_key = key
  light(M.windows_on_divider(winid, vertical), vertical)
end

function M.setup()
  if not vim.g.neovide then
    return
  end
  -- Not after an operator: a mapping there counts as an empty motion (c, a
  -- nudge of the mouse, w would change nothing and start typing).
  vim.keymap.set({ "n", "i", "v", "s", "c", "t" }, "<MouseMove>", M.update, {
    silent = true,
    desc = "Light the divider under the pointer",
  })
  -- A drag or a layout change moves the line: light it where it now is.
  api.nvim_create_autocmd({ "WinResized", "WinClosed", "WinNew", "TabEnter", "VimResized" }, {
    group = api.nvim_create_augroup("DividerHover", { clear = true }),
    callback = function()
      if lit_key then
        lit_key = nil
        vim.schedule(M.update)
      end
    end,
  })
end

return M
