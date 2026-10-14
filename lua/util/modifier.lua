local M = {}

M.is_macos = vim.fn.has "macunix" == 1
M.is_windows = vim.fn.has "win32" == 1
-- Cmd on macOS. Elsewhere Ctrl would shadow core Vim keys (<C-w> windows,
-- <C-b>/<C-d> scrolling, <C-t> tag jumps, <C-v> block select), so use Alt.
M.key = M.is_macos and "D" or "A"

---Build a primary-modifier chord such as <D-p> on macOS or <A-p> elsewhere.
---@param sequence string
---@return string
function M.chord(sequence)
  return "<" .. M.key .. "-" .. sequence .. ">"
end

return M
