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
-- never wrapped. Every ui2 window gets the real width here, except the message
-- window, which ui2 sizes to its text itself, and the open box.
--
-- Suggestions: typing a `:` command opens the completion menu as you type
-- (`:e ` lists files), the way the old config's popup did. Nothing is picked
-- until Tab or an arrow; Up and Down still walk the command history.
--
-- Typo'd writes: `:w;`, `:w]`, `:wq'` or `:w w` (a slip while spamming :w)
-- wrote a copy of the file to a new file named `;`, `]` or `w` (2026-11-13:
-- a file `;` holding the drill turned up in 001-clock). A write whose only
-- argument is 1-2 punctuation marks, or w, q or ww, and names no file that
-- exists, runs as the plain :w (:wq, :x, :update) with one line saying so
-- instead of the "written" line.
local M = {}

local api = vim.api

local TITLES = { [":"] = " Command ", ["/"] = " Search ", ["?"] = " Search back ", ["="] = " Expression " }

local state = { firstc = "", prompt = "" }
local active = false -- the command window is the box, not the bottom line

---The box: centred, its top on the finder's top row (pressed against the
---pane titles at the top it looked off), 60% of the screen but 60 to 100
---cells wide, never wider than the screen less a margin.
local function box_config(height)
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
local function menu_rows()
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
      if not active then
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

local WRITES = { write = "w", wq = "wq", xit = "x", exit = "exit", update = "update" }

---The plain write a typo'd one meant, and the junk name it would have made;
---nil for any other command line. `:w %.bak`, `:w #`, `:w >>`, `:w !cmd`,
---a range, a modifier, or a name that exists stay as typed.
function M.fix_write(line)
  local ok, cmd = pcall(api.nvim_parse_cmd, line, {})
  if not ok or not WRITES[cmd.cmd] or #cmd.args ~= 1 or #(cmd.range or {}) > 0 then
    return nil
  end
  for _, v in pairs(cmd.mods or {}) do
    if v == true or (type(v) == "number" and v > 0) or (type(v) == "string" and v ~= "") then
      return nil
    end
  end
  local name = cmd.args[1]
  local punct = #name <= 2 and name:match "^%p+$" and not name:find "[%%#<>!]"
  if not (punct or name == "w" or name == "q" or name == "ww") or vim.uv.fs_stat(name) then
    return nil
  end
  return WRITES[cmd.cmd] .. (cmd.bang and "!" or ""), name
end

local function typo_writes()
  api.nvim_create_autocmd("CmdlineLeave", {
    group = api.nvim_create_augroup("TypoWrites", { clear = true }),
    callback = function()
      if vim.v.event.abort or vim.v.event.cmdtype ~= ":" then
        return
      end
      local typed = vim.fn.getcmdline()
      local fixed, name = M.fix_write(typed)
      if fixed then
        -- Its own "written" line is silenced, so the note is the one line
        -- shown (two would read "written [+1]"). Errors still show.
        vim.fn.setcmdline("silent " .. fixed)
        vim.schedule(function()
          vim.notify((":%s read as :%s; no file %q made"):format(typed, fixed, name))
        end)
      end
    end,
  })
end

-- With 'cmdheight' 0 every message counts as too tall for the command line,
-- so ui2 shows it "expanded" until the next key. When that key is `:`, ui2
-- keeps the message and sends the new command's output to its pager and
-- moves the cursor there, as Vim did below a long message: spamming :w (the
-- second :w before any other key) landed in [Pager], and the next :w gave
-- E382 (2026-11-13). Opening the command line now dismisses the shown
-- message, as every other key does, so the next command's message replaces
-- it on the bottom line. A long message stays in g< and :messages, and output
-- too tall for the screen still opens the pager by itself.
local function dismiss_message(ui)
  local msg = ui.msg
  if not msg.cmd_on_key then
    return
  end
  vim.on_key(nil, ui.ns)
  msg.cmd_on_key, msg.cmd.ids = nil, {}
end

function M.setup()
  typo_writes()
  suggest()
  local ok, ui = pcall(require, "vim._core.ui2")
  if not ok or not ui.cmd then
    return
  end
  local cmd = ui.cmd

  -- Find ui2's local win_config(win, hide, height) through cmdline_show.
  local index, stock
  for i = 1, 30 do
    local name, value = debug.getupvalue(cmd.cmdline_show, i)
    if name == "win_config" then
      index, stock = i, value
      break
    end
  end
  if not index then
    return
  end

  -- ui2 also passes a height; the box works out its own.
  local function win_config(win, hide)
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
      active = false
      return stock(win, true, ui.cmdheight)
    end
    -- Width first: the wrapped height depends on it.
    local box = box_config(1)
    if not active or api.nvim_win_get_width(win) ~= box.width then
      local name = title()
      local cfg = vim.tbl_extend("force", box, {
        border = vim.o.winborder ~= "" and vim.o.winborder or "rounded",
        title = name,
        title_pos = name and "center" or nil,
        hide = false,
      })
      api.nvim_win_set_config(win, cfg)
      active = true
    end
    -- Completion: the menu opens under the typed line; the box grows
    -- around it, so the list sits inside the box (as in VS Code's palette)
    -- instead of across its border.
    local h = api.nvim_win_text_height(win, {}).all + menu_rows()
    box = box_config(h)
    if api.nvim_win_get_height(win) ~= box.height or api.nvim_win_get_config(win).row ~= box.row then
      api.nvim_win_set_config(win, { relative = "editor", row = box.row, col = box.col, height = box.height })
    end
  end
  debug.setupvalue(cmd.cmdline_show, index, win_config)

  local show = cmd.cmdline_show
  cmd.cmdline_show = function(content, pos, firstc, prompt, ...)
    state.firstc, state.prompt = firstc or "", prompt or ""
    if cmd.level == 0 then
      active = false
      dismiss_message(ui)
    end
    return show(content, pos, firstc, prompt, ...)
  end

  -- Real widths for every ui2 window (see the top of this file).
  local check = ui.check_targets
  ui.check_targets = function(...)
    check(...)
    for kind, win in pairs(ui.wins) do
      if api.nvim_win_is_valid(win) and kind ~= "msg" and not (kind == "cmd" and active) then
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
      if active and api.nvim_win_is_valid(ui.wins.cmd) then
        active = false
        win_config(ui.wins.cmd, false)
      end
    end,
  })
end

return M
