local M = {}

local pending = {}

local function normalize_buffer(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function delete_now(bufnr, force, opts)
  local previous_keyboard_switch = vim.g.nvim_keyboard_buffer_switch
  if opts and opts.keep_terminal_normal then
    vim.g.nvim_keyboard_buffer_switch = true
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

return M
