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

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local cwd = vim.fn.getcwd()
    if cwd == vim.env.HOME or cwd == "/" then
      local projects = vim.env.HOME .. "/Desktop/Projects"
      if vim.fn.isdirectory(projects) == 1 then
        vim.cmd("cd " .. vim.fn.fnameescape(projects))
      end
    end
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    if vim.fn.argc() == 0 then
      session.load_last_project()
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

local function enter_terminal_input()
  if vim.bo.buftype ~= "terminal" then
    return
  end

  if vim.w.nvim_terminal_original_winhighlight == nil then
    vim.w.nvim_terminal_original_winhighlight = vim.wo.winhighlight
  end
  if vim.w.nvim_terminal_original_cursorline == nil then
    vim.w.nvim_terminal_original_cursorline = vim.wo.cursorline
  end

  local entries = {}
  for entry in vim.wo.winhighlight:gmatch "[^,]+" do
    if not vim.startswith(entry, "Normal:") and not vim.startswith(entry, "WinSeparator:") then
      entries[#entries + 1] = entry
    end
  end
  entries[#entries + 1] = "Normal:TermNormal"
  entries[#entries + 1] = "WinSeparator:TermWinSeparator"
  vim.wo.winhighlight = table.concat(entries, ",")
  vim.wo.cursorline = false

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
    -- Repair windows restored from sessions made before the original value was
    -- tracked: a normal editor must never inherit the terminal background.
    local entries = {}
    for entry in vim.wo.winhighlight:gmatch "[^,]+" do
      if entry ~= "Normal:TermNormal" and entry ~= "WinSeparator:TermWinSeparator" then
        entries[#entries + 1] = entry
      end
    end
    vim.wo.winhighlight = table.concat(entries, ",")
  end

  local original_cursorline = vim.w.nvim_terminal_original_cursorline
  if original_cursorline ~= nil then
    vim.wo.cursorline = original_cursorline
    vim.w.nvim_terminal_original_cursorline = nil
  end
end

local terminal_group = vim.api.nvim_create_augroup("TerminalBehavior", { clear = true })
local terminal_boundary_windows = {}
local terminal_boundary_update_scheduled = false
local clear_separator_hover = function() end

local function separator_highlight(winhl)
  for entry in winhl:gmatch "[^,]+" do
    local group = entry:match "^WinSeparator:(.+)$"
    if group then
      return group
    end
  end
end

local function with_separator_highlight(winhl, group)
  local entries = {}
  for entry in winhl:gmatch "[^,]+" do
    if not vim.startswith(entry, "WinSeparator:") then
      entries[#entries + 1] = entry
    end
  end
  if group then
    entries[#entries + 1] = "WinSeparator:" .. group
  end
  return table.concat(entries, ",")
end

local function update_terminal_boundaries()
  clear_separator_hover()

  local windows = vim.tbl_filter(function(win)
    return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
  local terminals = vim.tbl_filter(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
  end, windows)
  local should_use_terminal_background = {}

  for _, terminal in ipairs(terminals) do
    local terminal_position = vim.api.nvim_win_get_position(terminal)
    local terminal_left = terminal_position[2]
    local terminal_right = terminal_left + vim.api.nvim_win_get_width(terminal) - 1

    for _, win in ipairs(windows) do
      if win ~= terminal and vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= "terminal" then
        local position = vim.api.nvim_win_get_position(win)
        local right = position[2] + vim.api.nvim_win_get_width(win) - 1
        local separator_row = position[1] + vim.api.nvim_win_get_height(win)
        local overlaps_terminal = position[2] <= terminal_right and terminal_left <= right

        if separator_row + 1 == terminal_position[1] and overlaps_terminal then
          should_use_terminal_background[win] = true
        end
      end
    end
  end

  for win, state in pairs(terminal_boundary_windows) do
    if not vim.api.nvim_win_is_valid(win) then
      terminal_boundary_windows[win] = nil
    elseif not should_use_terminal_background[win] then
      local current = vim.wo[win].winhighlight
      if separator_highlight(current) == "TerminalBoundary" then
        vim.wo[win].winhighlight = with_separator_highlight(current, state.original or nil)
      end
      terminal_boundary_windows[win] = nil
    end
  end

  for win in pairs(should_use_terminal_background) do
    if not terminal_boundary_windows[win] then
      local current = vim.wo[win].winhighlight
      terminal_boundary_windows[win] = { original = separator_highlight(current) or false }
      vim.wo[win].winhighlight = with_separator_highlight(current, "TerminalBoundary")
    end
  end
end

local function schedule_terminal_boundary_update()
  if terminal_boundary_update_scheduled then
    return
  end
  terminal_boundary_update_scheduled = true
  vim.schedule(function()
    terminal_boundary_update_scheduled = false
    update_terminal_boundaries()
  end)
end

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
    schedule_terminal_boundary_update()
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  group = terminal_group,
  callback = function()
    if vim.bo.buftype == "terminal" then
      enter_terminal_input()
    else
      restore_editor_background()
    end
    schedule_terminal_boundary_update()
  end,
})

vim.api.nvim_create_autocmd(
  { "VimEnter", "TabEnter", "WinNew", "WinClosed", "WinResized", "VimResized", "TermClose" },
  {
    group = terminal_group,
    callback = function()
      schedule_terminal_boundary_update()
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

-- Neovide cannot change the system pointer shape contextually, but Neovim can
-- tell us when the pointer is over a draggable window separator. Highlight
-- only the separator owned by that window and preserve any existing winhl.
if vim.g.neovide then
  local hovered

  clear_separator_hover = function()
    if not hovered then
      return
    end

    if vim.api.nvim_win_is_valid(hovered.winid) and vim.wo[hovered.winid].winhighlight == hovered.applied then
      vim.wo[hovered.winid].winhighlight = hovered.original
    end
    hovered = nil
  end

  local function add_separator_hover(winhl)
    local entries = {}
    local hover_group = "WinSeparatorHover"
    for entry in winhl:gmatch "[^,]+" do
      if entry == "WinSeparator:NvimTreeWinSeparator" then
        hover_group = "NvimTreeWinSeparatorHover"
      elseif entry == "WinSeparator:TermWinSeparator" then
        hover_group = "TermWinSeparatorHover"
      elseif entry == "WinSeparator:TerminalBoundary" then
        hover_group = "TerminalBoundaryHover"
      end
      if not vim.startswith(entry, "WinSeparator:") then
        entries[#entries + 1] = entry
      end
    end
    entries[#entries + 1] = "WinSeparator:" .. hover_group
    return table.concat(entries, ",")
  end

  local function update_separator_hover()
    local mouse = vim.fn.getmousepos()
    local winid = mouse.winid
    local over_separator = winid ~= 0 and mouse.line == 0 and mouse.column == 0

    if
      not over_separator
      or not vim.api.nvim_win_is_valid(winid)
      or vim.api.nvim_win_get_config(winid).relative ~= ""
    then
      clear_separator_hover()
      return
    end

    if hovered and hovered.winid == winid then
      return
    end
    clear_separator_hover()

    local original = vim.wo[winid].winhighlight
    local applied = add_separator_hover(original)
    vim.wo[winid].winhighlight = applied
    hovered = { winid = winid, original = original, applied = applied }
  end

  vim.keymap.set({ "n", "i", "v", "s", "o", "c", "t" }, "<MouseMove>", update_separator_hover, {
    silent = true,
    desc = "Highlight hovered split divider",
  })

  vim.api.nvim_create_autocmd({ "WinClosed", "VimLeavePre" }, {
    callback = clear_separator_hover,
  })
end
