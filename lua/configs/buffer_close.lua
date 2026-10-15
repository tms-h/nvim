local M = {}

local pending = {}

-- Closed file tabs, newest last, so Cmd+Shift+T can reopen them like Chrome.
local closed = {}
local max_closed = 50

local function normalize_buffer(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

-- Buffer ids in tab order, as bufferline draws them.
local function tab_order()
  local ok, bufferline = pcall(require, "bufferline")
  if not ok then
    return {}
  end
  return vim.tbl_map(function(element)
    return element.id
  end, bufferline.get_elements().elements)
end

local function index_of(list, value)
  for i, item in ipairs(list) do
    if item == value then
      return i
    end
  end
end

-- Chrome focuses the tab to the right of a closed one, or the left when it was last.
local function neighbour(bufnr)
  local order = tab_order()
  local i = index_of(order, bufnr)
  if not i then
    return nil
  end
  local next_buf = order[i + 1] or order[i - 1]
  if next_buf and vim.api.nvim_buf_is_valid(next_buf) then
    return next_buf
  end
end

-- Remember a file buffer so it can be reopened; terminals and scratch buffers are skipped.
local function remember(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.bo[bufnr].buftype ~= "" then
    return
  end
  local win = vim.fn.bufwinid(bufnr)
  table.insert(closed, {
    path = path,
    cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or vim.api.nvim_buf_get_mark(bufnr, '"'),
    index = index_of(tab_order(), bufnr),
  })
  if #closed > max_closed then
    table.remove(closed, 1)
  end
end

local function delete_now(bufnr, force, opts)
  local previous_keyboard_switch = vim.g.nvim_keyboard_buffer_switch
  if opts and opts.keep_terminal_normal then
    vim.g.nvim_keyboard_buffer_switch = true
  end

  remember(bufnr)
  local next_buf = neighbour(bufnr)
  if next_buf then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.api.nvim_win_set_buf(win, next_buf)
    end
  end
  local ok, err = pcall(require("mini.bufremove").delete, bufnr, force)
  vim.g.nvim_keyboard_buffer_switch = previous_keyboard_switch
  if not ok then
    error(err)
  end
end

function M.delete(bufnr, opts)
  bufnr = normalize_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or pending[bufnr] then
    return
  end

  if not vim.bo[bufnr].modified then
    delete_now(bufnr, false, opts)
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  local name = path == "" and "[No Name]" or vim.fn.fnamemodify(path, ":t")
  local choices = {
    { label = "keep editing", delete = false },
    { label = "delete without saving", delete = true },
  }

  pending[bufnr] = true
  vim.ui.select(choices, {
    prompt = name .. " has unsaved changes",
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    pending[bufnr] = nil
    if not choice or not choice.delete or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    delete_now(bufnr, true, opts)
  end)
end

function M.delete_from_keyboard(bufnr)
  M.delete(bufnr, { keep_terminal_normal = true })
end

-- Count the real editor splits in this tab: floats and the file tree don't
-- count, so a lone editor next to NvimTree still counts as one window.
local function editor_window_count()
  local count = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].filetype ~= "NvimTree" then
      count = count + 1
    end
  end
  return count
end

-- Close the current split and wipe its buffer. With only one split left this
-- behaves like a normal buffer close so the layout never collapses.
function M.close_window_and_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  if editor_window_count() <= 1 then
    M.delete(bufnr, { keep_terminal_normal = true })
    return
  end

  local function close(force)
    remember(bufnr)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = force })
    end
  end

  -- Terminals hold a running job, so they are always force-closed.
  if vim.bo[bufnr].buftype == "terminal" or not vim.bo[bufnr].modified then
    close(true)
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  local name = path == "" and "[No Name]" or vim.fn.fnamemodify(path, ":t")
  vim.ui.select({ "keep editing", "delete without saving" }, {
    prompt = name .. " has unsaved changes",
  }, function(choice)
    if choice == "delete without saving" then
      close(true)
    end
  end)
end

-- Reopen the most recently closed file in its old tab position, like Cmd+Shift+T in Chrome.
-- Files that are open again already are skipped.
function M.reopen()
  local entry
  repeat
    entry = table.remove(closed)
  until not entry or vim.fn.bufloaded(entry.path) == 0
  if not entry then
    vim.notify("No closed tabs to reopen", vim.log.levels.INFO)
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(entry.path))
  local last_line = vim.api.nvim_buf_line_count(0)
  if entry.cursor[1] >= 1 and entry.cursor[1] <= last_line then
    pcall(vim.api.nvim_win_set_cursor, 0, entry.cursor)
  end

  local ok, bufferline = pcall(require, "bufferline")
  if not ok or not entry.index then
    return
  end
  vim.cmd.redrawtabline()
  local from = index_of(tab_order(), vim.api.nvim_get_current_buf())
  -- move_to swaps two tabs, so walk the tab left one step at a time to insert it.
  while from and from > entry.index do
    bufferline.move_to(from - 1, from)
    from = from - 1
  end
end

return M
