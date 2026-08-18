local M = {}

M.is_macos = vim.fn.has "macunix" == 1
M.is_windows = vim.fn.has "win32" == 1
M.key = M.is_macos and "D" or "C"

---Build a primary-modifier chord such as <D-p> on macOS or <C-p> on Windows.
---@param sequence string
---@return string
function M.chord(sequence)
  return "<" .. M.key .. "-" .. sequence .. ">"
end

return M
