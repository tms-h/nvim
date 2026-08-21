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

return M
