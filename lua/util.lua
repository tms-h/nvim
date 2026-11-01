local M = {}

-- Which system this is: the one place the config asks.
M.is_macos = vim.fn.has "macunix" == 1
M.is_windows = vim.fn.has "win32" == 1
-- Cmd on macOS. Elsewhere Ctrl would shadow core Vim keys (<C-w> windows,
-- <C-b>/<C-d> scrolling, <C-t> tags, <C-v> block select), so Alt.
local key = M.is_macos and "D" or "A"

---A primary-modifier chord: <D-p> on macOS, <A-p> elsewhere.
---@param sequence string
---@return string
function M.chord(sequence)
  return "<" .. key .. "-" .. sequence .. ">"
end

return M
