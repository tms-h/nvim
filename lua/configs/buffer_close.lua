local M = {}

local pending = {}

local function normalize_buffer(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

function M.delete(bufnr)
  bufnr = normalize_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or pending[bufnr] then
    return
  end

  if not vim.bo[bufnr].modified then
    require("mini.bufremove").delete(bufnr, false)
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
    require("mini.bufremove").delete(bufnr, true)
  end)
end

return M
