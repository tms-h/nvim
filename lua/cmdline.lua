-- Where typed commands appear: a centred box on the row where the finder
-- (Alt/Cmd+P) opens, instead of the bottom row. `:` commands, `/` and `?`
-- searches and input() prompts all show there, and a long line wraps inside
-- the box, so the whole input stays in view in a narrow window. Messages stay
-- on the bottom line, as before (ui2, options.lua).
--
-- How: ui2 already draws the command line in a floating window of its own;
-- this moves that window while you type and puts it back after. ui2 keeps
-- the code that sizes it in a local function (win_config); it is swapped for
-- the one below. If a Neovim update renames it, the stock bottom line stays
-- and tests/run.lua fails.
--
-- Also: ui2 makes its windows 10000 cells wide and relies on Neovim to cut
-- them to the screen. Neovide draws each window on its own (multigrid), where
-- nothing cuts them, so a long command or message ran off the right edge and
-- never wrapped. Every ui2 window gets the real width here.
--
-- Suggestions: typing a `:` command opens the completion menu as you type
-- (`:e ` lists files), the way the old config's popup did. Nothing is picked
-- until Tab or an arrow; Up and Down still walk the command history.
local M = {}

local api = vim.api

local TITLES = { [":"] = " Command ", ["/"] = " Search ", ["?"] = " Search back ", ["="] = " Expression " }

local state = { firstc = "", prompt = "" }

---The box: centred, its top on the finder's top row (pressed against the
---pane titles at the top it looked off), at most 100 cells wide, never wider
---than the screen less a margin.
function M.box(height)
  local cols, lines = vim.o.columns, vim.o.lines
  local width = math.max(math.min(100, math.floor(cols * 0.6)), math.min(60, cols - 4))
  width = math.min(width, cols - 4)
  -- Moved up when the box (and its completion menu) would not fit below;
  -- the border takes a cell on each side.
  local row = math.min(require("finder").window().row, math.max(0, lines - height - 4))
  return {
    relative = "editor",
    row = row,
    col = math.floor((cols - width - 2) / 2),
    width = math.max(width, 10),
    height = math.max(1, math.min(height, lines - row - 4)),
  }
end

---Rows the completion menu takes under the typed line (0 when closed).
function M.menu_rows()
  local info = vim.fn.cmdcomplete_info()
  if not (info.pum_visible == 1 and info.matches) then
    return 0
  end
  local max = vim.o.pumheight > 0 and vim.o.pumheight or 10
  return math.min(#info.matches, max)
end

local function title()
  if state.prompt ~= "" then
    return nil
  end
  return TITLES[state.firstc]
end

---Suggestions as you type (see the top of this file; :h cmdline-autocompletion).
local function suggest()
  vim.o.wildmode = "noselect:lastused,full"
  vim.o.wildoptions = "pum,tagfile"
  api.nvim_create_autocmd("CmdlineChanged", {
    group = api.nvim_create_augroup("CmdlineSuggest", { clear = true }),
    pattern = ":",
    callback = function()
      -- The menu opens under the line wherever the box is on screen, and the
      -- box moves only at the next redraw: with keys typed in one burst
      -- (":e ") the menu opened on the bottom line, outside the box.
      if not M.active then
        api.nvim__redraw { flush = true }
      end
      vim.fn.wildtrigger()
    end,
  })
  for _, key in ipairs { "<Up>", "<Down>" } do
    vim.keymap.set("c", key, function()
      return vim.fn.wildmenumode() == 1 and "<C-e>" .. key or key
    end, { expr = true, desc = "History, not the suggestion list" })
  end
end

function M.setup()
  suggest()
  local ok, ui = pcall(require, "vim._core.ui2")
  if not ok or not ui.cmd then
    return
  end
  local cmd = ui.cmd

  -- Find ui2's local win_config(win, hide, height) through cmdline_show.
  local index
  for i = 1, 30 do
    local name = debug.getupvalue(cmd.cmdline_show, i)
    if name == nil then
      break
    elseif name == "win_config" then
      index = i
      break
    end
  end
  if not index then
    return
  end
  local stock = select(2, debug.getupvalue(cmd.cmdline_show, index))

  local function win_config(win, hide, height)
    if hide then
      -- Back to the bottom line for messages, the stock way.
      api.nvim_win_set_config(win, {
        relative = "laststatus",
        row = 1,
        col = 0,
        width = vim.o.columns,
        height = math.max(ui.cmdheight, 1),
        anchor = "NW",
        border = "none",
      })
      M.active = false
      return stock(win, true, ui.cmdheight)
    end
    -- Width first: the wrapped height depends on it.
    local box = M.box(1)
    if not M.active or api.nvim_win_get_width(win) ~= box.width then
      local cfg = vim.tbl_extend("force", box, {
        border = vim.o.winborder ~= "" and vim.o.winborder or "rounded",
        title = title(),
        title_pos = title() and "center" or nil,
        hide = false,
      })
      api.nvim_win_set_config(win, cfg)
      M.active = true
    end
    -- Completion: the menu opens under the typed line; the box grows
    -- around it, so the list sits inside the box (as in VS Code's palette)
    -- instead of across its border.
    local h = api.nvim_win_text_height(win, {}).all + M.menu_rows()
    box = M.box(h)
    if api.nvim_win_get_height(win) ~= box.height or api.nvim_win_get_config(win).row ~= box.row then
      api.nvim_win_set_config(win, { relative = "editor", row = box.row, col = box.col, height = box.height })
    end
  end
  debug.setupvalue(cmd.cmdline_show, index, win_config)
  M.patched = true

  local show = cmd.cmdline_show
  cmd.cmdline_show = function(content, pos, firstc, prompt, ...)
    local fresh = cmd.level == 0
    state.firstc, state.prompt = firstc or "", prompt or ""
    if fresh then
      M.active = false
    end
    return show(content, pos, firstc, prompt, ...)
  end

  -- Real widths for every ui2 window (see the top of this file).
  local check = ui.check_targets
  ui.check_targets = function(...)
    check(...)
    for kind, win in pairs(ui.wins) do
      if api.nvim_win_is_valid(win) and kind ~= "msg" and not (kind == "cmd" and M.active) then
        if api.nvim_win_get_width(win) ~= vim.o.columns then
          api.nvim_win_set_config(win, { width = vim.o.columns })
        end
      end
    end
  end
  api.nvim_create_autocmd("VimResized", {
    group = api.nvim_create_augroup("CmdlineBox", { clear = true }),
    callback = function()
      ui.check_targets()
      if M.active and api.nvim_win_is_valid(ui.wins.cmd) then
        M.active = false
        win_config(ui.wins.cmd, false, 1)
      end
    end,
  })
end

return M
