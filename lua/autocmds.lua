local command_line_group = vim.api.nvim_create_augroup("HiddenCommandLine", { clear = true })
local session = require "configs.session"

local function hide_command_line_row()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local window = vim.api.nvim_tabpage_get_win(tabpage)
    vim.api.nvim_win_call(window, function()
      if vim.opt_local.cmdheight:get() ~= 0 then
        vim.opt_local.cmdheight = 0
      end
    end)
  end
end

-- 'cmdheight' is local to each tab page. Sessions and newly created tabs can
-- therefore bring the otherwise hidden command/message row back.
vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter", "SessionLoadPost", "TabEnter", "VimResized" }, {
  group = command_line_group,
  callback = function()
    vim.schedule(hide_command_line_row)
  end,
})

-- Keep late-loading plugins from permanently reserving the row again.
vim.api.nvim_create_autocmd("OptionSet", {
  group = command_line_group,
  pattern = "cmdheight",
  callback = function()
    if vim.opt_local.cmdheight:get() ~= 0 then
      vim.schedule(hide_command_line_row)
    end
  end,
})

-- Bare `nvim` in a project restores that project's session. Only a launch from
-- $HOME or / (e.g. a GUI launcher) jumps to the most recent project instead.
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    -- `nvim some/folder` works like `code some/folder`: open that project with
    -- its session and the explorer. netrw is off and nvim-tree loads lazily, so
    -- nothing else claims the folder and it would show as a blank buffer.
    if vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
      local folder_buf = vim.api.nvim_get_current_buf()
      session.open_folder(vim.fn.argv(0), { startup = true })
      if vim.api.nvim_buf_is_valid(folder_buf) and vim.fn.isdirectory(vim.api.nvim_buf_get_name(folder_buf)) == 1 then
        pcall(vim.api.nvim_buf_delete, folder_buf, { force = true })
      end
      return
    end
    if vim.fn.argc() ~= 0 then
      return
    end
    local cwd = vim.fn.getcwd()
    if cwd ~= vim.env.HOME and cwd ~= "/" then
      require("persistence").load()
    elseif not session.load_last_project() then
      local projects = vim.env.HOME .. "/Desktop/Projects"
      if vim.fn.isdirectory(projects) == 1 then
        vim.cmd("cd " .. vim.fn.fnameescape(projects))
      end
    end
  end,
})

local function is_explorer_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local filetype = vim.bo[buf].filetype
  local name = vim.api.nvim_buf_get_name(buf)
  if filetype == "NvimTree" or filetype == "oil" or vim.startswith(name, "oil://") then
    return true
  end

  -- Sessions restore nvim-tree's temporary name as a normal buffer. Avoid
  -- treating a genuine file with the same unusual name as an explorer.
  return vim.fn.fnamemodify(name, ":t"):match "^NvimTree_%d+$" ~= nil and vim.fn.filereadable(name) == 0
end

local function session_file_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ""
      and vim.api.nvim_buf_get_name(buf) ~= ""
      and not is_explorer_buffer(buf)
      and not session.is_config_buffer(buf)
    then
      return buf
    end
  end
end

local function remove_explorer_buffers()
  local replacement = session_file_buffer()

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local windows = vim.tbl_filter(function(win)
      return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
    end, vim.api.nvim_tabpage_list_wins(tab))

    for index = #windows, 1, -1 do
      local win = windows[index]
      if is_explorer_buffer(vim.api.nvim_win_get_buf(win)) then
        if #windows > 1 then
          vim.api.nvim_win_close(win, true)
          table.remove(windows, index)
        else
          replacement = replacement or vim.api.nvim_create_buf(true, false)
          vim.api.nvim_win_set_buf(win, replacement)
        end
      end
    end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_explorer_buffer(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- Explorer windows are UI, not files. Remove them before persistence.nvim
-- writes a session so reopening Neovide starts without an explorer split.
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  callback = remove_explorer_buffers,
})

vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    vim.schedule(function()
      -- Also repairs older sessions that contain explorer or config buffers.
      remove_explorer_buffers()
      session.cleanup_restored_config_buffers()

      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_loaded(buf)
          and vim.api.nvim_buf_get_name(buf) == ""
          and vim.api.nvim_buf_line_count(buf) <= 1
          and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
        then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
          vim.api.nvim_buf_call(buf, function()
            if vim.bo.filetype == "" then
              vim.cmd "filetype detect"
            end
            pcall(vim.treesitter.start)
          end)
        end
      end
    end)
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank { timeout = 200 }
  end,
})

-- Older versions gave terminal windows their own background. Sessions and a
-- buffer's remembered window options can still carry it, so it is stripped.
local function without_terminal_background(winhighlight)
  local entries = {}
  for entry in winhighlight:gmatch "[^,]+" do
    if entry ~= "Normal:TermNormal" and entry ~= "WinSeparator:TermWinSeparator" then
      entries[#entries + 1] = entry
    end
  end
  return table.concat(entries, ",")
end

local function enter_terminal_input()
  if vim.bo.buftype ~= "terminal" then
    return
  end

  if vim.w.nvim_terminal_original_winhighlight == nil then
    vim.w.nvim_terminal_original_winhighlight = without_terminal_background(vim.wo.winhighlight)
  end
  if vim.w.nvim_terminal_original_cursorline == nil then
    vim.w.nvim_terminal_original_cursorline = vim.wo.cursorline
  end

  -- Terminals share the one pane surface: a darker terminal left a strip of
  -- the neighbour's colour on its side of every divider.
  vim.wo.winhighlight = without_terminal_background(vim.wo.winhighlight)
  vim.wo.cursorline = false
  -- A global scrolloff larger than half a short split pins the view to the
  -- terminal cursor, which makes the scrollback impossible to scroll.
  vim.wo.scrolloff = 0

  if not vim.g.nvim_keyboard_buffer_switch then
    vim.cmd "startinsert"
  end
end

local function restore_editor_background()
  local original_winhighlight = vim.w.nvim_terminal_original_winhighlight
  if original_winhighlight ~= nil then
    vim.wo.winhighlight = original_winhighlight
    vim.w.nvim_terminal_original_winhighlight = nil
  else
    -- Repair windows restored from sessions or handed a buffer's remembered
    -- options: a normal editor must never inherit the terminal background.
    vim.wo.winhighlight = without_terminal_background(vim.wo.winhighlight)
  end

  local original_cursorline = vim.w.nvim_terminal_original_cursorline
  if original_cursorline ~= nil then
    vim.wo.cursorline = original_cursorline
    vim.w.nvim_terminal_original_cursorline = nil
  end

  -- Drop the terminal-only override so the window follows the global value.
  vim.wo.scrolloff = -1
end

local terminal_group = vim.api.nvim_create_augroup("TerminalBehavior", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
  group = terminal_group,
  pattern = "term://*",
  callback = function(args)
    -- A click means the user wants to interact with the terminal, even when a
    -- keyboard buffer switch deliberately left it in Terminal-Normal mode.
    vim.keymap.set("n", "<LeftMouse>", "<LeftMouse><cmd>startinsert<cr>", {
      buffer = args.buf,
      silent = true,
      desc = "Terminal: focus input",
    })
    enter_terminal_input()
  end,
})

-- Window-local highlights stay with the window, not the buffer. When a file
-- lands in a window that last showed nvim-tree or a terminal, drop their
-- overrides so the file gets the normal editor background.
local function strip_foreign_highlights()
  local entries = {}
  for entry in vim.wo.winhighlight:gmatch "[^,]+" do
    local group = entry:match ":(.+)$" or ""
    local foreign = vim.startswith(group, "NvimTree") or vim.startswith(group, "StatusLineTerm")
    if not foreign and not vim.tbl_contains(entries, entry) then
      entries[#entries + 1] = entry
    end
  end
  vim.wo.winhighlight = table.concat(entries, ",")
end

vim.api.nvim_create_autocmd("BufEnter", {
  group = terminal_group,
  callback = function()
    if vim.bo.buftype == "terminal" then
      enter_terminal_input()
    else
      restore_editor_background()
      if vim.bo.buftype == "" and vim.api.nvim_win_get_config(0).relative == "" then
        strip_foreign_highlights()
      end
    end
  end,
})

vim.api.nvim_create_autocmd(
  { "VimEnter", "TabEnter", "WinNew", "WinClosed", "WinResized", "VimResized", "TermClose" },
  {
    group = terminal_group,
    callback = function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
          vim.schedule(function()
            pcall(vim.cmd, "redraw!")
          end)
          return
        end
      end
    end,
  }
)

-- Pull config changes made on other machines without delaying startup.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(require("configs.config_sync").pull, 1000)
  end,
})

-- Pick up files changed outside Neovim (agents, git pulls) without a keypress.
vim.o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermLeave" }, {
  group = vim.api.nvim_create_augroup("ReloadFromDisk", { clear = true }),
  callback = function()
    if vim.fn.getcmdwintype() == "" and vim.bo.buftype == "" then
      vim.cmd "silent! checktime"
    end
  end,
})
